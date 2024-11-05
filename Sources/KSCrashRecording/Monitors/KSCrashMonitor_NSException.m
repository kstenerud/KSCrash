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

#import "KSCrashMonitor_NSException.h"

#import <Foundation/Foundation.h>
#import "KSCompilerDefines.h"
#import "KSCrash+Private.h"
#import "KSCrash.h"
#include "KSCrashMonitorContext.h"
#import "KSCrashMonitorContextHelper.h"
#include "KSID.h"
#import "KSStackCursor_Backtrace.h"
#import "KSStackCursor_SelfThread.h"
#include "KSThread.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static volatile bool g_isEnabled = 0;

static KSCrash_MonitorContext g_monitorContext;

/** The exception handler that was in place before we installed ours. */
static NSUncaughtExceptionHandler *g_previousUncaughtExceptionHandler;

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
    if (g_isEnabled) {
        thread_act_array_t threads = NULL;
        mach_msg_type_number_t numThreads = 0;
        if (logAllThreads) {
            ksmc_suspendEnvironment(&threads, &numThreads);
        }
        if (isUserReported == NO) {
            // User-reported exceptions are not considered fatal.
            kscm_notifyFatalExceptionCaptured(false);
        }

        KSLOG_DEBUG(@"Filling out context.");
        char eventID[37];
        ksid_generate(eventID);
        KSMC_NEW_CONTEXT(machineContext);
        ksmc_getContextForThread(ksthread_self(), machineContext, true);
        KSStackCursor cursor;
        uintptr_t *callstack = NULL;
        initStackCursor(&cursor, exception, callstack, isUserReported);

        NS_VALID_UNTIL_END_OF_SCOPE NSString *userInfoString =
            exception.userInfo != nil ? [NSString stringWithFormat:@"%@", exception.userInfo] : nil;

        KSCrash_MonitorContext *crashContext = &g_monitorContext;
        memset(crashContext, 0, sizeof(*crashContext));
        ksmc_fillMonitorContext(crashContext, kscm_nsexception_getAPI());
        crashContext->eventID = eventID;
        crashContext->offendingMachineContext = machineContext;
        crashContext->registersAreValid = false;
        crashContext->NSException.name = [[exception name] UTF8String];
        crashContext->NSException.userInfo = [userInfoString UTF8String];
        crashContext->exceptionName = crashContext->NSException.name;
        crashContext->crashReason = [[exception reason] UTF8String];
        crashContext->stackCursor = &cursor;
        crashContext->currentSnapshotUserReported = isUserReported;

        KSLOG_DEBUG(@"Calling main crash handler.");
        kscm_handleException(crashContext);

        free(callstack);
        if (logAllThreads && isUserReported) {
            ksmc_resumeEnvironment(threads, numThreads);
        }
        if (isUserReported == NO && g_previousUncaughtExceptionHandler != NULL) {
            KSLOG_DEBUG(@"Calling original exception handler.");
            g_previousUncaughtExceptionHandler(exception);
        }
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

// ============================================================================
#pragma mark - API -
// ============================================================================

static void setEnabled(bool isEnabled)
{
    if (isEnabled != g_isEnabled) {
        g_isEnabled = isEnabled;
        if (isEnabled) {
            KSLOG_DEBUG(@"Backing up original handler.");
            g_previousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();

            KSLOG_DEBUG(@"Setting new handler.");
            NSSetUncaughtExceptionHandler(&handleUncaughtException);
            KSCrash.sharedInstance.uncaughtExceptionHandler = &handleUncaughtException;
            KSCrash.sharedInstance.customNSExceptionReporter = &customNSExceptionReporter;
        } else {
            KSLOG_DEBUG(@"Restoring original handler.");
            NSSetUncaughtExceptionHandler(g_previousUncaughtExceptionHandler);
        }
    }
}

static const char *monitorId(void) { return "NSException"; }

static KSCrashMonitorFlag monitorFlags(void) { return KSCrashMonitorFlagFatal; }

static bool isEnabled(void) { return g_isEnabled; }

KSCrashMonitorAPI *kscm_nsexception_getAPI(void)
{
    static KSCrashMonitorAPI api = {
        .monitorId = monitorId, .monitorFlags = monitorFlags, .setEnabled = setEnabled, .isEnabled = isEnabled
    };
    return &api;
}
