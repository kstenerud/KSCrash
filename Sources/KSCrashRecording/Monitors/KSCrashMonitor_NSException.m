//
//  KSCrashMonitor_NSException.m
//
//  Created by Karl Stenerud on 2012-01-28.
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

#import "KSCrashMonitor_NSException+Private.h"

#import "KSCompilerDefines.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitorHelper.h"
#import "KSID.h"
#import "KSStackCursor_Backtrace.h"
#import "KSStackCursor_SelfThread.h"
#import "KSThread.h"

#import <Foundation/Foundation.h>
#import <stdatomic.h>

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static struct {
    _Atomic(KSCM_InstalledState) installedState;
    atomic_bool isEnabled;

    /** The exception handler that was in place before we installed ours. */
    NSUncaughtExceptionHandler *previousUncaughtExceptionHandler;

    KSCrash_ExceptionHandlerCallbacks callbacks;

    OnNSExceptionHandlerEnabled *onEnabled;
} g_state;

static bool isEnabled(__unused void *context) { return g_state.isEnabled && g_state.installedState == KSCM_Installed; }

// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

static KS_NOINLINE void initStackCursor(KSStackCursor *cursor, NSException *exception, uintptr_t **callstack,
                                        BOOL isUserReported) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    // Use stacktrace from NSException if present,
    // otherwise use current thread (can happen for user-reported exceptions).
    NSArray *addresses = [exception callStackReturnAddresses];
    NSUInteger numFrames = addresses.count;
    if (numFrames != 0) {
        *callstack = malloc(numFrames * sizeof(**callstack));
        for (NSUInteger i = 0; i < numFrames; i++) {
            (*callstack)[i] = (uintptr_t)[addresses[i] unsignedLongLongValue];
        }
        kssc_initWithBacktrace(cursor, *callstack, (int)numFrames, 0);
    } else {
        /* Skip frames for user-reported:
         * 1. `initStackCursor`
         * 2. `handleException`
         * 3. `customNSExceptionReporter`
         * 4. `+[KSCrash reportNSException:logAllThreads:]`
         *
         * Skip frames for caught exceptions (unlikely scenario):
         * 1. `initStackCursor`
         * 2. `handleException`
         * 3. `handleUncaughtException`
         */
        int const skipFrames = isUserReported ? 4 : 3;
        kssc_initSelfThread(cursor, skipFrames);
    }
    KS_THWART_TAIL_CALL_OPTIMISATION
}

/** Our custom excepetion handler.
 * Fetch the stack trace from the exception and write a report.
 *
 * @param exception The exception that was raised.
 */
static KS_NOINLINE void handleException(NSException *exception, BOOL isUserReported,
                                        BOOL logAllThreads) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    KSLOG_DEBUG(@"Trapped exception %@", exception);
    if (isEnabled(NULL)) {
        // Gather this info before we require async-safety (ObjC messaging is not signal-safe):
        const char *exceptionName = exception.name.UTF8String;
        const char *exceptionReason = exception.reason.UTF8String;
        NS_VALID_UNTIL_END_OF_SCOPE NSString *userInfoString =
            exception.userInfo != nil ? [NSString stringWithFormat:@"%@", exception.userInfo] : nil;
        const char *userInfo = userInfoString.UTF8String;

        // Capture the exception's own backtrace (from callStackReturnAddresses).
        // This uses ObjC, so it must happen before notify() enters async-safe mode.
        KSStackCursor exceptionCursor;
        uintptr_t *callstack = NULL;
        initStackCursor(&exceptionCursor, exception, &callstack, isUserReported);

        // Capture the handler's actual call stack while we're still in the handler frame.
        // User-reported skip 3: handleException + customNSExceptionReporter + reportNSException:
        // Uncaught skip 2: handleException + handleUncaughtException
        KSStackCursor handlerCursor;
        int const handlerSkipFrames = isUserReported ? 3 : 2;
        kssc_initSelfThread(&handlerCursor, handlerSkipFrames);

        KSLOG_DEBUG(@"Filling out context.");
        thread_t thisThread = (thread_t)ksthread_self();

        // Notify suspends other threads, establishing async-safe mode.
        KSCrash_MonitorContext *crashContext = g_state.callbacks.notify(
            thisThread, (KSCrash_ExceptionHandlingRequirements) { .asyncSafety = false,
                                                                  // User-reported exceptions are not considered fatal.
                                                                  .isFatal = !isUserReported,
                                                                  .shouldRecordAllThreads = logAllThreads != NO,
                                                                  .shouldWriteReport = true });
        if (crashContext->requirements.shouldExitImmediately) {
            goto exit_immediately;
        }

        // Capture machine context after notify() so the thread list matches the suspended state.
        KSMachineContext machineContext = { 0 };
        ksmc_getContextForThread(thisThread, &machineContext, true);

        kscm_fillMonitorContext(crashContext, kscm_nsexception_getAPI());
        crashContext->offendingMachineContext = &machineContext;
        crashContext->registersAreValid = false;
        crashContext->NSException.name = exceptionName;
        crashContext->NSException.userInfo = userInfo;
        crashContext->exceptionName = exceptionName;
        crashContext->crashReason = exceptionReason;
        crashContext->currentSnapshotUserReported = isUserReported;

        // The handler backtrace goes into stackCursor (shown as the crashed thread's backtrace).
        // The exception's origin backtrace goes into exceptionStackCursor (last_exception_backtrace).
        crashContext->stackCursor = &handlerCursor;
        crashContext->exceptionStackCursor = &exceptionCursor;

        KSLOG_DEBUG(@"Calling main crash handler.");
        g_state.callbacks.handle(crashContext);

    exit_immediately:
        free(callstack);
    }
    if (!isUserReported && g_state.previousUncaughtExceptionHandler != NULL) {
        KSLOG_DEBUG(@"Calling original exception handler.");
        g_state.previousUncaughtExceptionHandler(exception);
    }
    KS_THWART_TAIL_CALL_OPTIMISATION
}

static void customNSExceptionReporter(NSException *exception, BOOL logAllThreads) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    handleException(exception, YES, logAllThreads);
    KS_THWART_TAIL_CALL_OPTIMISATION
}

static void handleUncaughtException(NSException *exception) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    handleException(exception, NO, YES);
    KS_THWART_TAIL_CALL_OPTIMISATION
}

static void install(void)
{
    KSCM_InstalledState expectedState = KSCM_NotInstalled;
    if (!atomic_compare_exchange_strong(&g_state.installedState, &expectedState, KSCM_Installed)) {
        return;
    }

    KSLOG_DEBUG(@"Backing up original handler.");
    g_state.previousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
    KSLOG_DEBUG(@"Setting new handler.");
    NSSetUncaughtExceptionHandler(&handleUncaughtException);
}

// ============================================================================
#pragma mark - API -
// ============================================================================

static void setEnabled(bool enabled, __unused void *context)
{
    bool expectedState = !enabled;
    if (!atomic_compare_exchange_strong(&g_state.isEnabled, &expectedState, enabled)) {
        // We were already in the expected state
        return;
    }

    if (enabled) {
        install();
        if (isEnabled(NULL) && g_state.onEnabled != NULL) {
            g_state.onEnabled(handleUncaughtException, customNSExceptionReporter);
        }
    }
}

static const char *monitorId(__unused void *context) { return "NSException"; }

static KSCrashMonitorFlag monitorFlags(__unused void *context) { return KSCrashMonitorFlagNone; }

static void init(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    g_state.callbacks = *callbacks;
}

KSCrashMonitorAPI *kscm_nsexception_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = init;
        api.monitorId = monitorId;
        api.monitorFlags = monitorFlags;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
    }
    return &api;
}

void kscm_nsexception_setOnEnabledHandler(OnNSExceptionHandlerEnabled *onEnabled) { g_state.onEnabled = onEnabled; }
