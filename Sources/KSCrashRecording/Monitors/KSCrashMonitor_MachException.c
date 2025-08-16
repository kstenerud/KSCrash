//
//  KSCrashMonitor_MachException.c
//
//  Created by Karl Stenerud on 2012-02-04.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

// Theory of Operation
// ===================
//
// Everything in the Mach kernel revolves around messaging, including the exception subsystem.
//
// To install a Mach exception handler:
// - Create a new Mach port.
// - Give the port receive and send rights.
// - Call 'task_set_exception_ports()' to install this exception handler.
// - Spin up a thread and have it call 'mach_msg()' to wait for an exception message.
// - When it receives a message, respond to that message.
//
// Note that only one exception handler can be installed at a time for a particular exception
// (technically, one at each level: [thread, task, host] - but we only care about the task level).
// This means that the runtime technically doesn't support multiple handlers, but we can get around
// this with a trick.
//
// Once an exception request message has been received, the offending thread won't resume until the
// exception request message is replied to. The "RetCode" field of the reply message tells the
// kernel what the process should do next:
// - KERN_SUCCESS means "I've handled the exception and it's okay to retry the faulting instruction."
//   The process will re-run the instruction that caused the exception and continue processing from there.
// - KERN_FAILURE means "I couldn't handle this exception." The process will look for a higher-up
//   handler (in this case, a host handler) and run that. If no higher-up handlers exist, the process terminates.
//
// In order to chain to other Mach exception handlers, we do the following:
// - On start, use 'task_get_exception_ports()' to save any already established exception handlers.
// - Next, use 'task_set_exception_ports()' to set our own handler ports.
// - After handling an exception, restore the original ports, then check their masks to see
//   if they can handle the exception type we're dealing with.
//   - If they can handle this exception, respond to the exception request message with 'KERN_SUCCESS'.
//     The process will re-run the faulting instruction (which will fault again) and then the kernel
//     will send another exception message to the original port we just restored.
//   - If they can't handle this exception, respond to the exception request message with 'KERN_FAILURE'.
//     The kernel will pass control to the host port (if any), and finish crashing the app.

#include "KSCrashMonitor_MachException.h"

#include "KSCPU.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#include "KSCrashMonitor_Signal.h"
#include "KSID.h"
#include "KSStackCursor_MachineContext.h"
#include "KSSystemCapabilities.h"
#include "KSThread.h"

// #define KSLogger_LocalLevel TRACE
#include "KSLogger.h"

#if KSCRASH_HAS_MACH

#include <mach/exc.h>
#include <mach/mach.h>
#include <mach/machine/thread_state.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>

// ============================================================================
#pragma mark - Constants -
// ============================================================================

static const char *kThreadPrimary = "KSCrash Exception Handler (Primary" KSCRASH_NAMESPACE_STRING ")";
static const char *kThreadSecondary = "KSCrash Exception Handler (Secondary" KSCRASH_NAMESPACE_STRING ")";

enum {
    kContextIdxSystem = 0,
    kContextIdxSecondary = 1,
    kContextIdxPrimary = 2,
    kContextCount = 3,
};

#if __LP64__
#define MACH_ERROR_CODE_MASK 0xFFFFFFFFFFFFFFFF
#else
#define MACH_ERROR_CODE_MASK 0xFFFFFFFF
#endif

static const exception_mask_t kInterestingExceptions =
    EXC_MASK_BAD_ACCESS | EXC_MASK_BAD_INSTRUCTION | EXC_MASK_ARITHMETIC | EXC_MASK_SOFTWARE | EXC_MASK_BREAKPOINT;

// ============================================================================
#pragma mark - Types -
// ============================================================================

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wused-but-marked-unused"
typedef __Request__exception_raise_t ExceptionRequest;
typedef __Reply__exception_raise_t ExceptionReply;
#pragma clang diagnostic pop

typedef struct {
    exception_mask_t masks[EXC_TYPES_COUNT];
    exception_handler_t ports[EXC_TYPES_COUNT];
    exception_behavior_t behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t count;
} MachExceptionHandlerRestorePoint;

struct ExceptionContext;
typedef void(ExceptionCallback)(struct ExceptionContext *);

typedef struct {
    // ================================
    // These are only set once.
    // ================================

    const char *threadName;
    ExceptionRequest *request;    // Will point to requestBuffer
    mach_msg_size_t requestSize;  // will be sizeof(requestBuffer)
    // Make the buffer from an array of uint64 in order to enforce memory alignment.
    // Notice that the buffer will be 8x larger than "required". The mach subsystem
    // will secretly tack on extra data for its own purposes, so we need this.
    uint64_t requestBuffer[sizeof(ExceptionRequest)];
    pthread_t posixThread;
    thread_t machThread;
    mach_port_t exceptionPort;
    MachExceptionHandlerRestorePoint machExceptionHandlerRestorePoint;
    int contextIndex;

    // ================================
    // These are changeable state.
    // ================================

    KSStackCursor stackCursor;
    atomic_bool isHandlingException;

} ExceptionContext;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static struct {
    ExceptionContext contexts[kContextCount];
    KSCrash_ExceptionHandlerCallbacks callbacks;
    int currentRestorePoint;
} g_state;

static atomic_bool g_isEnabled = false;

// ============================================================================
#pragma mark - Utility -
// ============================================================================

#define MACH_ERROR(KR, MSG)               \
    do {                                  \
        mach_error(MSG, KR);              \
        KSLOG_ERROR(MSG ": kr = %d", KR); \
    } while (0)

#define EXC_UNIX_BAD_SYSCALL 0x10000 /* SIGSYS */
#define EXC_UNIX_BAD_PIPE 0x10001    /* SIGPIPE */
#define EXC_UNIX_ABORT 0x10002       /* SIGABRT */

static int signalForMachException(exception_type_t exception, mach_exception_code_t code)
{
    switch (exception) {
        case EXC_ARITHMETIC:
            return SIGFPE;
        case EXC_BAD_ACCESS:
            return code == KERN_INVALID_ADDRESS ? SIGSEGV : SIGBUS;
        case EXC_BAD_INSTRUCTION:
            return SIGILL;
        case EXC_BREAKPOINT:
            return SIGTRAP;
        case EXC_EMULATION:
            return SIGEMT;
        case EXC_SOFTWARE:
            switch (code) {
                case EXC_UNIX_BAD_SYSCALL:
                    return SIGSYS;
                case EXC_UNIX_BAD_PIPE:
                    return SIGPIPE;
                case EXC_UNIX_ABORT:
                    return SIGABRT;
                case EXC_SOFT_SIGNAL:
                    return SIGKILL;
                default:
                    return 0;
            }
        default:
            return 0;
    }
}

static exception_type_t machExceptionForSignal(int sigNum)
{
    switch (sigNum) {
        case SIGFPE:
            return EXC_ARITHMETIC;
        case SIGSEGV:
            return EXC_BAD_ACCESS;
        case SIGBUS:
            return EXC_BAD_ACCESS;
        case SIGILL:
            return EXC_BAD_INSTRUCTION;
        case SIGTRAP:
            return EXC_BREAKPOINT;
        case SIGEMT:
            return EXC_EMULATION;
        case SIGSYS:
            return EXC_UNIX_BAD_SYSCALL;
        case SIGPIPE:
            return EXC_UNIX_BAD_PIPE;
        case SIGABRT:
            // The Apple reporter uses EXC_CRASH instead of EXC_UNIX_ABORT
            return EXC_CRASH;
        case SIGKILL:
            return EXC_SOFT_SIGNAL;
        default:
            return 0;
    }
}

static exception_mask_t maskForException(exception_type_t exc)
{
    // In mach/excepton_types.h, these are all set up as 1 << type
    return 1 << exc;
}

static bool canCurrentPortsHandleException(exception_type_t exc)
{
    const exception_mask_t matchingMask = maskForException(exc);
    const MachExceptionHandlerRestorePoint *ports =
        &g_state.contexts[g_state.currentRestorePoint].machExceptionHandlerRestorePoint;
    for (mach_msg_type_number_t i = 0; i < ports->count; i++) {
        if (MACH_PORT_VALID(ports->ports[i]) && (ports->masks[i] & matchingMask) != 0) {
            return true;
        }
    }
    return false;
}

static bool saveExceptionPortsRestorePoint(int contextIndex)
{
    MachExceptionHandlerRestorePoint *restorePoint = &g_state.contexts[contextIndex].machExceptionHandlerRestorePoint;
    kern_return_t kr =
        task_get_exception_ports(mach_task_self(), kInterestingExceptions, restorePoint->masks, &restorePoint->count,
                                 restorePoint->ports, restorePoint->behaviors, restorePoint->flavors);
    if (kr != KERN_SUCCESS) {
        MACH_ERROR(kr, "task_get_exception_ports");
        return false;
    }
    return true;
}

static bool restoreExceptionPorts(int restoreToIndex)
{
    KSLOG_DEBUG("Restoring exception ports to index %d: %s", restoreToIndex,
                g_state.contexts[restoreToIndex].threadName);

    g_state.currentRestorePoint = restoreToIndex;

    MachExceptionHandlerRestorePoint *restorePoint = &g_state.contexts[restoreToIndex].machExceptionHandlerRestorePoint;
    kern_return_t kr;
    for (mach_msg_type_number_t i = 0; i < restorePoint->count; i++) {
        if (restorePoint->masks[i] != 0) {
            kr = task_set_exception_ports(mach_task_self(), restorePoint->masks[i], restorePoint->ports[i],
                                          restorePoint->behaviors[i], restorePoint->flavors[i]);
            if (kr != KERN_SUCCESS) {
                MACH_ERROR(kr, "task_set_exception_ports");
                return false;
            }
        }
    }

    return true;
}

static bool restoreNextLevelExceptionPorts(ExceptionContext *ctx)
{
    return restoreExceptionPorts(ctx->contextIndex - 1);
}

static bool restoreOriginalExceptionPorts(void) { return restoreExceptionPorts(kContextIdxSystem); }

/** Simulate exc_server()
 * We don't actually want to run exc_server(), so instead just fill out the reply as if it had been run.
 * Note: You'll need to fill out RetCode yourself!
 */
static void simulatedExcServer(ExceptionRequest *request, ExceptionReply *reply)
{
    // XNU always replies with an ID 100 higher than the request ID.
    // See: https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/ipc_kobject.c#L428
    const mach_msg_id_t xnu_reply_msg_increment = 100;

    reply->NDR.int_rep = 1;

    reply->Head.msgh_bits = MACH_MSGH_BITS_REMOTE(request->Head.msgh_bits);
    reply->Head.msgh_size = sizeof(*reply);
    reply->Head.msgh_remote_port = request->Head.msgh_remote_port;
    reply->Head.msgh_id = request->Head.msgh_id + xnu_reply_msg_increment;
}

static void deallocExceptionHandler(ExceptionContext *ctx)
{
    // If this context is handling an exception, let it finish and dealloc naturally.
    if (ctx->isHandlingException) {
        KSLOG_DEBUG("Thread %s: Still handling an exception, so not deallocating yet", ctx->threadName);
        return;
    }

    KSLOG_DEBUG("Thread %s: Deallocating exception handler", ctx->threadName);

    mach_port_t exceptionPort = ctx->exceptionPort;
    thread_t machThread = ctx->machThread;
    pthread_t posixThread = ctx->posixThread;
    memset(ctx, 0, sizeof(*ctx));

    if (MACH_PORT_VALID(exceptionPort)) {
        // This port has both send and receive rights, which must be deallocated in separate steps.
        // https://github.com/apple-oss-distributions/xnu/blob/a1e26a70f38d1d7daa7b49b258e2f8538ad81650/doc/mach_ipc/guard_exceptions.md#port-right-mismanagement
        kern_return_t kr;
        mach_port_t thisTask = mach_task_self();
        mach_port_context_t context = 0;
        if ((kr = mach_port_get_context(thisTask, exceptionPort, &context)) != KERN_SUCCESS) {
            MACH_ERROR(kr, "mach_port_get_context");
        }
        if ((kr = mach_port_destruct(thisTask, exceptionPort, 0, context)) != KERN_SUCCESS) {
            MACH_ERROR(kr, "mach_port_destruct");
        }
        if ((kr = mach_port_deallocate(thisTask, exceptionPort)) != KERN_SUCCESS) {
            MACH_ERROR(kr, "mach_port_deallocate");
        }
    }
    if (posixThread != 0 && machThread != mach_thread_self()) {
        pthread_cancel(posixThread);
    }
}

// ============================================================================
#pragma mark - Handler Primitives -
// ============================================================================

static exception_type_t waitForException(ExceptionContext *ctx)
{
    KSLOG_DEBUG("Thread %s: Waiting for mach exception", ctx->threadName);

    ctx->request->Head.msgh_local_port = ctx->exceptionPort;
    ctx->request->Head.msgh_size = ctx->requestSize;

    kern_return_t kr = mach_msg(&ctx->request->Head, MACH_RCV_MSG | MACH_RCV_LARGE, 0, ctx->request->Head.msgh_size,
                                ctx->exceptionPort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if (kr == KERN_SUCCESS) {
        KSLOG_DEBUG("Thread %s: Trapped mach exception code 0x%llx, subcode 0x%llx", ctx->threadName,
                    ctx->request->code[0], ctx->request->code[1]);
    } else {
        MACH_ERROR(kr, "mach_msg");
    }
    return ctx->request->exception;
}

static void sendExceptionReply(ExceptionContext *ctx, bool exceptionPortsCanHandleThisException)
{
    ExceptionReply reply = { 0 };
    simulatedExcServer(ctx->request, &reply);

    if (exceptionPortsCanHandleThisException) {
        KSLOG_DEBUG(
            "Thread %s: Replying KERN_SUCCESS so that the process will re-run the instruction "
            "that caused the fault, fail again, and call the original handlers",
            ctx->threadName);
        reply.RetCode = KERN_SUCCESS;
    } else {
        KSLOG_DEBUG(
            "Thread %s: Replying KERN_FAILURE so that the process won't try any further "
            "action from this exception raise, and just crash",
            ctx->threadName);
        reply.RetCode = KERN_FAILURE;
    }

    kern_return_t kr = mach_msg(&reply.Head, MACH_SEND_MSG, reply.Head.msgh_size, 0, MACH_PORT_NULL,
                                MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if (kr != KERN_SUCCESS) {
        MACH_ERROR(kr, "mach_msg");
    } else {
        KSLOG_DEBUG("Thread %s: Mach exception reply sent.", ctx->threadName);
    }
}

static void handleException(ExceptionContext *exceptionCtx)
{
    KSCrash_MonitorContext *monitorCtx =
        g_state.callbacks.notify(exceptionCtx->request->thread.name, (KSCrash_ExceptionHandlingPolicy) {
                                                                         .requiresAsyncSafety = 1,
                                                                         .isFatal = true,
                                                                         .shouldRecordThreads = true,
                                                                     });
    if (monitorCtx->currentPolicy.shouldExitImmediately) {
        KSLOG_DEBUG("Thread %s: Should exit immediately, so returning", exceptionCtx->threadName);
        return;
    }

    KSLOG_DEBUG("Thread %s: Fetching machine state.", exceptionCtx->threadName);
    KSMachineContext machineContext = { 0 };
    monitorCtx->offendingMachineContext = &machineContext;
    kssc_initCursor(&exceptionCtx->stackCursor, NULL, NULL);
    if (ksmc_getContextForThread(exceptionCtx->request->thread.name, &machineContext, true)) {
        kssc_initWithMachineContext(&exceptionCtx->stackCursor, KSSC_MAX_STACK_DEPTH, &machineContext);
        KSLOG_TRACE("Thread %s: Fault address %p, instruction address %p", exceptionCtx->threadName,
                    kscpu_faultAddress(&machineContext), kscpu_instructionAddress(&machineContext));
        if (exceptionCtx->request->exception == EXC_BAD_ACCESS) {
            monitorCtx->faultAddress = kscpu_faultAddress(&machineContext);
        } else {
            monitorCtx->faultAddress = kscpu_instructionAddress(&machineContext);
        }
    }

    KSLOG_DEBUG("Thread %s: Filling out context.", exceptionCtx->threadName);
    kscm_fillMonitorContext(monitorCtx, kscm_machexception_getAPI());
    monitorCtx->registersAreValid = true;
    monitorCtx->mach.type = exceptionCtx->request->exception;
    monitorCtx->mach.code = exceptionCtx->request->code[0] & (int64_t)MACH_ERROR_CODE_MASK;
    monitorCtx->mach.subcode = exceptionCtx->request->code[1] & (int64_t)MACH_ERROR_CODE_MASK;
    if (monitorCtx->mach.code == KERN_PROTECTION_FAILURE && monitorCtx->isStackOverflow) {
        // A stack overflow should return KERN_INVALID_ADDRESS, but
        // when a stack blasts through the guard pages at the top of the stack,
        // it generates KERN_PROTECTION_FAILURE. Correct for this.
        monitorCtx->mach.code = KERN_INVALID_ADDRESS;
    }
    monitorCtx->signal.signum = signalForMachException(monitorCtx->mach.type, monitorCtx->mach.code);
    monitorCtx->stackCursor = &exceptionCtx->stackCursor;

    g_state.callbacks.handle(monitorCtx);
}

static void *exceptionHandlerThreadMain(void *data)
{
    ExceptionContext *ctx = (ExceptionContext *)data;
    pthread_setname_np(ctx->threadName);

    exception_type_t exc = waitForException(ctx);
    KSLOG_DEBUG("Trapped Mach exception on %s", ctx->threadName);

    // At this point, an exception has occurred and we need to deal with it.
    // We start by restoring the ports for the next level exception handler
    // in case we crash while handling this exception.

    if (g_isEnabled) {
        if (restoreNextLevelExceptionPorts(ctx)) {
            KSLOG_DEBUG("Thread %s: Handling mach exception %x", ctx->threadName, exc);
            ctx->isHandlingException = true;
            handleException(ctx);
            ctx->isHandlingException = false;
            KSLOG_DEBUG("Thread %s: Crash handling complete. Restoring original handlers.", ctx->threadName);
        } else {
            KSLOG_DEBUG("Thread %s: Could not set next level exception ports", ctx->threadName);
        }
    }

    // Regardless of whether we managed to deal with the exception or not,
    // we restore the original handlers and then send a suitable mach reply.
    KSLOG_DEBUG("Thread %s: Restoring original exception ports", ctx->threadName);
    restoreOriginalExceptionPorts();
    KSLOG_DEBUG("Thread %s: Replying to exception message", ctx->threadName);
    sendExceptionReply(ctx, canCurrentPortsHandleException(exc));
    deallocExceptionHandler(ctx);

    return NULL;
}

static bool startNewExceptionHandler(int contextIndex, const char *threadName)
{
    ExceptionContext *ctx = &g_state.contexts[contextIndex];
    memset(ctx, 0, sizeof(*ctx));
    ctx->threadName = threadName;
    ctx->contextIndex = contextIndex;
    ctx->request = (ExceptionRequest *)ctx->requestBuffer;
    ctx->requestSize = sizeof(ctx->requestBuffer);

    const mach_port_t taskSelf = mach_task_self();
    kern_return_t kr = KERN_SUCCESS;

    KSLOG_DEBUG("Thread %s: Installing mach exception handler", ctx->threadName);

    kr = mach_port_allocate(taskSelf, MACH_PORT_RIGHT_RECEIVE, &ctx->exceptionPort);
    if (kr != KERN_SUCCESS) {
        MACH_ERROR(kr, "mach_port_allocate");
        goto onFailure;
    }

    kr = mach_port_insert_right(taskSelf, ctx->exceptionPort, ctx->exceptionPort, MACH_MSG_TYPE_MAKE_SEND);
    if (kr != KERN_SUCCESS) {
        MACH_ERROR(kr, "mach_port_insert_right");
        goto onFailure;
    }

    kr = task_set_exception_ports(taskSelf, kInterestingExceptions, ctx->exceptionPort,
                                  (exception_behavior_t)(EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES), THREAD_STATE_NONE);
    if (kr != KERN_SUCCESS) {
        MACH_ERROR(kr, "task_set_exception_ports");
        goto onFailure;
    }

    if (!saveExceptionPortsRestorePoint(contextIndex)) {
        goto onFailure;
    }

    if (pthread_create(&ctx->posixThread, NULL, exceptionHandlerThreadMain, (void *)ctx) != 0) {
        perror("pthread_create");
        goto onFailure;
    }
    pthread_detach(ctx->posixThread);
    ctx->machThread = pthread_mach_thread_np(ctx->posixThread);

    ksmc_addReservedThread(ctx->machThread);

    KSLOG_DEBUG("Thread %s: Mach exception handler installed on thread %d", ctx->threadName, ctx->machThread);
    return true;

onFailure:
    deallocExceptionHandler(ctx);
    return false;
}

static void stopExceptionHandlers(void)
{
    restoreOriginalExceptionPorts();
    // Deallocation order doesn't matter since we've already restored the original ports.
    deallocExceptionHandler(&g_state.contexts[kContextIdxPrimary]);
    deallocExceptionHandler(&g_state.contexts[kContextIdxSecondary]);
}

static bool startExceptionHandlers(void)
{
    if (!saveExceptionPortsRestorePoint(kContextIdxSystem)) {
        KSLOG_ERROR("Could not save the original mach exception ports. Disabling the mach exception handler.");
        return false;
    }

    g_state.contexts[0].threadName = "Original handlers";

    // Start the secondary handler first because all handlers will try to enable
    // the ports at the next lower index. If we start the primary first, the
    // secondary's ports would still be blank for a short while.
    startNewExceptionHandler(kContextIdxSecondary, kThreadSecondary);
    startNewExceptionHandler(kContextIdxPrimary, kThreadPrimary);

    return true;
}

// ============================================================================
#pragma mark - API -
// ============================================================================

static const char *monitorId(void) { return "MachException"; }

static KSCrashMonitorFlag monitorFlags(void) { return KSCrashMonitorFlagAsyncSafe | KSCrashMonitorFlagDebuggerUnsafe; }

static void setEnabled(bool isEnabled)
{
    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expectEnabled, isEnabled)) {
        // We were already in the expected state
        return;
    }

    if (isEnabled) {
        if (!startExceptionHandlers()) {
            g_isEnabled = false;
        }
    } else {
        stopExceptionHandlers();
    }
}

static bool isEnabled(void) { return g_isEnabled; }

static void addContextualInfoToEvent(struct KSCrash_MonitorContext *eventContext)
{
    const char *signalName = kscm_signal_getAPI()->monitorId();

    if (signalName && strcmp(eventContext->monitorId, signalName) == 0) {
        eventContext->mach.type = machExceptionForSignal(eventContext->signal.signum);
    } else if (strcmp(eventContext->monitorId, monitorId()) != 0) {
        eventContext->mach.type = EXC_CRASH;
    }
}

static void init(KSCrash_ExceptionHandlerCallbacks *callbacks) { g_state.callbacks = *callbacks; }

#endif

KSCrashMonitorAPI *kscm_machexception_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
#if KSCRASH_HAS_MACH
        api.init = init;
        api.monitorId = monitorId;
        api.monitorFlags = monitorFlags;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
        api.addContextualInfoToEvent = addContextualInfoToEvent;
#endif
    }
    return &api;
}
