//
//  HangMonitorTestControl.m
//
//  Created by Alexander Cohen on 2026-09-19.
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

#import "HangMonitorTestControl.h"

#import <stdlib.h>
#import <string.h>

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Watchdog.h"

/** The context handed back to the monitor, reused across events: the monitor
 *  reads it and hands it straight to the handler, which keeps nothing. */
static KSCrash_MonitorContext g_context;

static KSCrash_MonitorContext *stubNotify(__unused thread_t thread,
                                          __unused KSCrash_ExceptionHandlingRequirements requirements)
{
    memset(&g_context, 0, sizeof(g_context));
    return &g_context;
}

/** Answers as the handler does when no report was written, which leaves the
 *  monitor with no report path and so nothing to finalize or delete later. */
static void stubHandleWithResult(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result,
                                 __unused bool finalize)
{
    if (result == NULL) {
        return;
    }
    result->reportId[0] = '\0';
    result->path[0] = '\0';
}

void hangtest_arm(void)
{
    // The monitor refuses to arm under a debugger unless forced. Without this a
    // hang test arms from the command line but not when run from Xcode, where
    // it would quietly observe nothing and skip.
    setenv("KSCRASH_FORCE_ENABLE_WATCHDOG", "1", 1);

    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify, .handleWithResult = stubHandleWithResult };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);
}

void hangtest_disarm(void)
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(false, NULL);
    unsetenv("KSCRASH_FORCE_ENABLE_WATCHDOG");
}

bool hangtest_isArmed(void) { return kshang_isEnabled(); }
