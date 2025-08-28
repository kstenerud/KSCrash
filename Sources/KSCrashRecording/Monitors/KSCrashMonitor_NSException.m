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

static void defaultOnEnabled(__unused NSUncaughtExceptionHandler *uncaughtExceptionHandler,
                             __unused KSCrashCustomNSExceptionReporter *customNSExceptionReporter)
{
}

static struct {
    _Atomic(KSCM_InstalledState) installedState;
    atomic_bool isEnabled;

    /** The exception handler that was in place before we installed ours. */
    NSUncaughtExceptionHandler *previousUncaughtExceptionHandler;

    KSCrash_ExceptionHandlerCallbacks callbacks;

    OnNSExceptionHandlerEnabled *onEnabled;
} g_state = { .onEnabled = defaultOnEnabled };

// ============================================================================
#pragma mark - Callbacks -
// ============================================================================

static KS_NOINLINE void initStackCursor(KSStackCursor *cursor, NSException *exception, uintptr_t *callstack,
                                        BOOL isUserReported) KS_KEEP_FUNCTION_IN_STACKTRACE
{
    // Use stacktrace from NSException if present,
    // otherwise use current thread (can happen for user-reported exceptions).
    NSArray *addresses = [exception callStackReturnAddresses];
    NSUInteger numFrames = addresses.count;
    if (numFrames != 0) {
        callstack = malloc(numFrames * sizeof(*callstack));
        for (NSUInteger i = 0; i < numFrames; i++) {
            callstack[i] = (uintptr_t)[addresses[i] unsignedLongLongValue];
        }
        kssc_initWithBacktrace(cursor, callstack, (int)numFrames, 0);
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
    if (g_state.installedState == KSCM_Installed && g_state.isEnabled) {
        // Gather this info before we require async-safety:
        const char *exceptionName = exception.name.UTF8String;
        const char *exceptionReason = exception.reason.UTF8String;
        NS_VALID_UNTIL_END_OF_SCOPE NSString *userInfoString =
            exception.userInfo != nil ? [NSString stringWithFormat:@"%@", exception.userInfo] : nil;
        const char *userInfo = userInfoString.UTF8String;
        KSLOG_DEBUG(@"Filling out context.");
        thread_t thisThread = (thread_t)ksthread_self();
        KSMachineContext machineContext = { 0 };
        ksmc_getContextForThread(thisThread, &machineContext, true);
        KSStackCursor cursor;
        uintptr_t *callstack = NULL;
        initStackCursor(&cursor, exception, callstack, isUserReported);

        // Now start exception handling
        KSCrash_MonitorContext *crashContext = g_state.callbacks.notify(
            thisThread, (KSCrash_ExceptionHandlingRequirements) { .asyncSafety = false,
                                                                  // User-reported exceptions are not considered fatal.
                                                                  .isFatal = !isUserReported,
                                                                  .shouldRecordAllThreads = logAllThreads != NO,
                                                                  .shouldWriteReport = true });
        if (crashContext->requirements.shouldExitImmediately) {
            goto exit_immediately;
        }

        kscm_fillMonitorContext(crashContext, kscm_nsexception_getAPI());
        crashContext->offendingMachineContext = &machineContext;
        crashContext->registersAreValid = false;
        crashContext->NSException.name = exceptionName;
        crashContext->NSException.userInfo = userInfo;
        crashContext->exceptionName = exceptionName;
        crashContext->crashReason = exceptionReason;
        crashContext->stackCursor = &cursor;
        crashContext->currentSnapshotUserReported = isUserReported;

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
    KSCM_InstalledState expectInstalled = KSCM_NotInstalled;
    if (!atomic_compare_exchange_strong(&g_state.installedState, &expectInstalled, KSCM_Installed)) {
        return;
    }

    KSLOG_DEBUG(@"Backing up original handler.");
    g_state.previousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();

    KSLOG_DEBUG(@"Setting new handler.");
    NSSetUncaughtExceptionHandler(&handleUncaughtException);
    g_state.onEnabled(handleUncaughtException, customNSExceptionReporter);
}

// ============================================================================
#pragma mark - API -
// ============================================================================

static void setEnabled(bool isEnabled)
{
    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_state.isEnabled, &expectEnabled, isEnabled)) {
        // We were already in the expected state
        return;
    }

    if (isEnabled) {
        install();
        g_state.isEnabled = g_state.installedState == KSCM_Installed;
    }
}

static const char *monitorId(void) { return "NSException"; }

static KSCrashMonitorFlag monitorFlags(void) { return KSCrashMonitorFlagNone; }

static bool isEnabled(void) { return g_state.isEnabled; }

static void init(KSCrash_ExceptionHandlerCallbacks *callbacks) { g_state.callbacks = *callbacks; }

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
