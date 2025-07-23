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
// Once an exception request message has been received, the process won't resume until the
// exception request message is replied to. The "RetCode" field of the reply message tells the
// process what to do next:
// - KERN_SUCCESS means "I've handled the exception and it's okay to retry the faulting instruction."
//   The process will re-run the instruction that caused the exception and continue processing from there.
// - KERN_FAILURE means "I couldn't handle this exception." The process will look for a higher-up
//   handler (in this case, a host handler) and run that. If no higher-up handlers exist, the process terminates.
//
// In order to chain to other Mach exception handlers, we do the following:
// - On start, use 'task_get_exception_ports()' to save any existing exception handler.
// - On Mach exception, look through the saved exception handler list for any port whose mask
//   matches the exception we're handling.
// - If we find a suitable port, use 'task_set_exception_ports()' to set it as the Mach exception
//   handler, then respond to the exception request message with 'KERN_SUCCESS'. The process will
//   re-run the faulting instruction (which will fault again) and then the kernel will send another
//   exception message to the port we just designated.
// - If we don't find a suitable handler, then there are no more exception handlers to chain to.
//   Respond to the exception request message with 'KERN_FAILURE', and the app will finish crashing.

#include "KSCrashMonitor_MachException.h"

#include "KSCPU.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorContextHelper.h"
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
#include <stdio.h>

// ============================================================================
#pragma mark - Constants -
// ============================================================================

static const char *kThreadPrimary = "KSCrash Exception Handler (Primary)";
// static const char *kThreadSecondary = "KSCrash Exception Handler (Secondary)";

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
} MachExceptionHandlerData;

struct ExceptionContext;
typedef void(ExceptionCallback)(struct ExceptionContext *);

typedef struct ExceptionContext {
    // These are set by initExceptionHandler()
    const char *threadName;
    ExceptionCallback *handleException;
    ExceptionRequest *request;    // Will point to requestBuffer
    mach_msg_size_t requestSize;  // will be sizeof(requestBuffer)
    // Make the buffer from an array of uint64 in order to enforce memory alignment.
    // Notice that the buffer will be 8x larger than "required". The mach subsystem
    // will secretly tack on extra data for its own purposes, so we need this.
    uint64_t requestBuffer[sizeof(ExceptionRequest)];

    // These are set by startNewExceptionHandler()
    pthread_t posixThread;
    thread_t machThread;
    mach_port_t exceptionPort;
    MachExceptionHandlerData previousHandlers;

    // These are used while the handler thread is running
    bool isHandlingException;
} ExceptionContext;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static volatile bool g_isEnabled = false;

static KSCrash_MonitorContext g_monitorContext;
static KSStackCursor g_stackCursor;

static ExceptionContext g_primaryContext = { 0 };

// ============================================================================
#pragma mark - Utility -
// ============================================================================

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

/** Try to restore any previously saved exception ports.
 * Returns true (did restore) or false (did not restore) so that the caller knows how to structure the reply message.
 * Note: This can only be called ONCE per MachExceptionHandlerData. Multiple calls will no-op and return false.
 */
static bool restorePreviousExceptionPorts(const exception_mask_t matchingMask,
                                          MachExceptionHandlerData *previousExceptionData)
{
    mach_msg_type_number_t foundIndex = 0;
    for (foundIndex = 0; foundIndex < previousExceptionData->count; foundIndex++) {
        if (MACH_PORT_VALID(previousExceptionData->ports[foundIndex]) &&
            (previousExceptionData->masks[foundIndex] & matchingMask) != 0) {
            break;
        }
    }
    if (foundIndex >= previousExceptionData->count) {
        KSLOG_DEBUG("No previous mach exception handlers present that can handle this exception.");
        return false;
    }

    // Prevent this exception data from being used again
    previousExceptionData->count = 0;

    KSLOG_DEBUG("Restoring previous mach exception handler.");
    kern_return_t kr = task_set_exception_ports(
        mach_task_self(), previousExceptionData->masks[foundIndex], previousExceptionData->ports[foundIndex],
        previousExceptionData->behaviors[foundIndex], previousExceptionData->flavors[foundIndex]);
    if (kr != KERN_SUCCESS) {
        mach_error("task_set_exception_ports", kr);
        return false;
    }
    return true;
}

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

static void initExceptionHandler(ExceptionContext *ctx, const char *threadName, ExceptionCallback *handleException)
{
    memset(ctx, 0, sizeof(*ctx));
    ctx->threadName = threadName;
    ctx->handleException = handleException;
    ctx->request = (ExceptionRequest *)ctx->requestBuffer;
    ctx->requestSize = sizeof(ctx->requestBuffer);
}

static void deallocExceptionHandler(ExceptionContext *ctx)
{
    // If this context is handling an exception, let it finish and dealloc naturally.
    if (!ctx->isHandlingException) {
        mach_port_t exceptionPort = ctx->exceptionPort;
        thread_t machThread = ctx->machThread;
        pthread_t posixThread = ctx->posixThread;
        memset(ctx, 0, sizeof(*ctx));

        if (MACH_PORT_VALID(exceptionPort)) {
            mach_port_deallocate(mach_task_self(), exceptionPort);
        }
        if (posixThread != 0 && machThread != mach_thread_self()) {
            pthread_cancel(posixThread);
        }
    }
}

// ============================================================================
#pragma mark - Handler Primitives -
// ============================================================================

static void waitForException(ExceptionContext *ctx)
{
    KSLOG_DEBUG("Waiting for mach exception");

    ctx->request->Head.msgh_local_port = ctx->exceptionPort;
    ctx->request->Head.msgh_size = ctx->requestSize;

    kern_return_t kr = mach_msg(&ctx->request->Head, MACH_RCV_MSG | MACH_RCV_LARGE, 0, ctx->request->Head.msgh_size,
                                ctx->exceptionPort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if (kr == KERN_SUCCESS) {
        KSLOG_DEBUG("Trapped mach exception code 0x%llx, subcode 0x%llx", ctx->request->code[0], ctx->request->code[1]);
    } else {
        mach_error("mach_msg", kr);
    }
}

static void sendExceptionReply(ExceptionContext *ctx, bool didRestoreExceptionPorts)
{
    ExceptionReply reply = { 0 };
    simulatedExcServer(ctx->request, &reply);

    if (didRestoreExceptionPorts) {
        KSLOG_DEBUG(
            "Replying KERN_SUCCESS so that the process will re-run the instruction "
            "that caused the fault, fail again, and call the previous handler");
        reply.RetCode = KERN_SUCCESS;
    } else {
        KSLOG_DEBUG(
            "Replying KERN_FAILURE so that the process won't try any further "
            "action from this exception raise");
        reply.RetCode = KERN_FAILURE;
    }

    kern_return_t kr = mach_msg(&reply.Head, MACH_SEND_MSG, reply.Head.msgh_size, 0, MACH_PORT_NULL,
                                MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if (kr != KERN_SUCCESS) {
        mach_error("mach_msg", kr);
    } else {
        KSLOG_DEBUG("Mach exception reply sent.");
    }
}

static void *exceptionHandlerThreadMain(void *data)
{
    ExceptionContext *ctx = (ExceptionContext *)data;
    pthread_setname_np(ctx->threadName);

    waitForException(ctx);

    ctx->isHandlingException = true;
    ctx->handleException(ctx);
    exception_mask_t mask = maskForException(ctx->request->exception);
    bool didRestorePorts = restorePreviousExceptionPorts(mask, &ctx->previousHandlers);
    ctx->isHandlingException = false;

    sendExceptionReply(ctx, didRestorePorts);
    deallocExceptionHandler(ctx);

    return NULL;
}

/** Start a new exception handler.
 * Note: ctx must be initialized using initExceptionContext() before calling this function.
 */
static bool startNewExceptionHandler(ExceptionContext *ctx)
{
    const mach_port_t taskSelf = mach_task_self();
    kern_return_t kr = KERN_SUCCESS;

    if (ctx->threadName == NULL) {
        KSLOG_ERROR("ctx->threadName must not be null. Please call initExceptionContext(ctx) first.");
        return false;
    }
    if (ctx->handleException == NULL) {
        KSLOG_ERROR("ctx->handleException must not be null. Please call initExceptionContext(ctx) first.");
        return false;
    }

    KSLOG_DEBUG("Installing mach exception handler %s", ctx->threadName);

    kr = task_get_exception_ports(taskSelf, kInterestingExceptions, ctx->previousHandlers.masks,
                                  &ctx->previousHandlers.count, ctx->previousHandlers.ports,
                                  ctx->previousHandlers.behaviors, ctx->previousHandlers.flavors);
    if (kr != KERN_SUCCESS) {
        mach_error("task_get_exception_ports", kr);
        goto onFailure;
    }

    kr = mach_port_allocate(taskSelf, MACH_PORT_RIGHT_RECEIVE, &ctx->exceptionPort);
    if (kr != KERN_SUCCESS) {
        mach_error("mach_port_allocate", kr);
        goto onFailure;
    }

    kr = mach_port_insert_right(taskSelf, ctx->exceptionPort, ctx->exceptionPort, MACH_MSG_TYPE_MAKE_SEND);
    if (kr != KERN_SUCCESS) {
        mach_error("mach_port_insert_right", kr);
        goto onFailure;
    }

    kr = task_set_exception_ports(taskSelf, kInterestingExceptions, ctx->exceptionPort,
                                  (exception_behavior_t)(EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES), THREAD_STATE_NONE);
    if (kr != KERN_SUCCESS) {
        mach_error("task_set_exception_ports", kr);
        goto onFailure;
    }

    if (pthread_create(&ctx->posixThread, NULL, exceptionHandlerThreadMain, (void *)ctx) != 0) {
        perror("pthread_create");
        goto onFailure;
    }
    pthread_detach(ctx->posixThread);
    ctx->machThread = pthread_mach_thread_np(ctx->posixThread);

    ksmc_addReservedThread(ctx->machThread);

    KSLOG_DEBUG("Mach exception handler installed on thread %d", ctx->machThread);
    return true;

onFailure:
    deallocExceptionHandler(ctx);
    return false;
}

static void stopExceptionHandler(ExceptionContext *ctx)
{
    if (!ctx->isHandlingException) {
        restorePreviousExceptionPorts(kInterestingExceptions, &ctx->previousHandlers);
        deallocExceptionHandler(ctx);
    }
}

// ============================================================================
#pragma mark - Primary Handler -
// ============================================================================

static void handleExceptionPrimary(ExceptionContext *ctx)
{
    if (!g_isEnabled) {
        return;
    }

    thread_act_array_t threads = NULL;
    mach_msg_type_number_t numThreads = 0;
    ksmc_suspendEnvironment(&threads, &numThreads);
    kscm_notifyFatalExceptionCaptured(true);

    KSLOG_DEBUG("Exception handler is installed. Continuing exception handling.");

    // Fill out crash information
    KSLOG_DEBUG("Fetching machine state.");
    KSMachineContext machineContext = { 0 };
    KSCrash_MonitorContext *crashContext = &g_monitorContext;
    crashContext->offendingMachineContext = &machineContext;
    kssc_initCursor(&g_stackCursor, NULL, NULL);
    if (ksmc_getContextForThread(ctx->request->thread.name, &machineContext, true)) {
        kssc_initWithMachineContext(&g_stackCursor, KSSC_MAX_STACK_DEPTH, &machineContext);
        KSLOG_TRACE("Fault address %p, instruction address %p", kscpu_faultAddress(machineContext),
                    kscpu_instructionAddress(machineContext));
        if (ctx->request->exception == EXC_BAD_ACCESS) {
            crashContext->faultAddress = kscpu_faultAddress(&machineContext);
        } else {
            crashContext->faultAddress = kscpu_instructionAddress(&machineContext);
        }
    }

    KSLOG_DEBUG("Filling out context.");
    ksmc_fillMonitorContext(crashContext, kscm_machexception_getAPI());
    crashContext->registersAreValid = true;
    crashContext->mach.type = ctx->request->exception;
    crashContext->mach.code = ctx->request->code[0] & (int64_t)MACH_ERROR_CODE_MASK;
    crashContext->mach.subcode = ctx->request->code[1] & (int64_t)MACH_ERROR_CODE_MASK;
    if (crashContext->mach.code == KERN_PROTECTION_FAILURE && crashContext->isStackOverflow) {
        // A stack overflow should return KERN_INVALID_ADDRESS, but
        // when a stack blasts through the guard pages at the top of the stack,
        // it generates KERN_PROTECTION_FAILURE. Correct for this.
        crashContext->mach.code = KERN_INVALID_ADDRESS;
    }
    crashContext->signal.signum = signalForMachException(crashContext->mach.type, crashContext->mach.code);
    crashContext->stackCursor = &g_stackCursor;

    kscm_handleException(crashContext);

    KSLOG_DEBUG("Crash handling complete. Restoring original handlers.");
    ksmc_resumeEnvironment(threads, numThreads);
}

static void startPrimaryExceptionHandler(void)
{
    ExceptionContext *ctx = &g_primaryContext;
    initExceptionHandler(ctx, kThreadPrimary, handleExceptionPrimary);
    startNewExceptionHandler(ctx);
}

// ============================================================================
#pragma mark - API -
// ============================================================================

static const char *monitorId(void) { return "MachException"; }

static KSCrashMonitorFlag monitorFlags(void)
{
    return KSCrashMonitorFlagFatal | KSCrashMonitorFlagAsyncSafe | KSCrashMonitorFlagDebuggerUnsafe;
}

static void setEnabled(bool isEnabled)
{
    if (isEnabled != g_isEnabled) {
        g_isEnabled = isEnabled;
        if (isEnabled) {
            // TODO: Re-add recrash detection
            startPrimaryExceptionHandler();
        } else {
            stopExceptionHandler(&g_primaryContext);
        }
    }
}

static bool isEnabled(void) { return g_isEnabled; }

static void addContextualInfoToEvent(struct KSCrash_MonitorContext *eventContext)
{
    const char *signalName = kscm_getMonitorId(kscm_signal_getAPI());

    if (signalName && strcmp(eventContext->monitorId, signalName) == 0) {
        eventContext->mach.type = machExceptionForSignal(eventContext->signal.signum);
    } else if (strcmp(eventContext->monitorId, monitorId()) != 0) {
        eventContext->mach.type = EXC_CRASH;
    }
}

#endif

KSCrashMonitorAPI *kscm_machexception_getAPI(void)
{
#if KSCRASH_HAS_MACH
    static KSCrashMonitorAPI api = {

        .monitorId = monitorId,
        .monitorFlags = monitorFlags,
        .setEnabled = setEnabled,
        .isEnabled = isEnabled,
        .addContextualInfoToEvent = addContextualInfoToEvent
    };
    return &api;
#else
    return NULL;
#endif
}
