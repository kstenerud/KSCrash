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

#import <Foundation/Foundation.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Watchdog.h"

extern bool kscm_watchdog_testcode_isRunning(void);

/** The context handed back to the monitor, reused across events: the monitor
 *  reads it and hands it straight to the handler, which keeps nothing. */
static KSCrash_MonitorContext g_context;

/** This process's scratch folder for the hang's run sidecar and report, so a hang
 *  is recorded the way an installed monitor records one, outside any store. */
static char g_directory[PATH_MAX];
static _Atomic(int) g_reportCount = 0;

static KSCrash_MonitorContext *stubNotify(__unused thread_t thread,
                                          __unused KSCrash_ExceptionHandlingRequirements requirements)
{
    memset(&g_context, 0, sizeof(g_context));
    return &g_context;
}

static bool stubRunSidecarPath(const char *monitorId, char *pathBuffer, size_t pathBufferLength)
{
    return (size_t)snprintf(pathBuffer, pathBufferLength, "%s/%s.ksscr", g_directory, monitorId) < pathBufferLength;
}

/** Creates a placeholder report file and hands its path back, as the handler
 *  does for a report it wrote, so the monitor follows the hang to its end. */
static void stubHandleWithResult(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result,
                                 __unused bool finalize)
{
    if (result == NULL) {
        return;
    }
    result->reportId[0] = '\0';
    result->path[0] = '\0';
    char path[PATH_MAX];
    int count = atomic_fetch_add(&g_reportCount, 1);
    if ((size_t)snprintf(path, sizeof(path), "%s/hang-%d.json", g_directory, count) >= sizeof(path)) {
        return;
    }
    FILE *file = fopen(path, "w");
    if (file == NULL) {
        return;
    }
    fclose(file);
    snprintf(result->reportId, sizeof(result->reportId), "hang-%d", count);
    strlcpy(result->path, path, sizeof(result->path));
}

void hangtest_arm(void)
{
    // The monitor refuses to arm under a debugger unless forced. Without this a
    // hang test arms from the command line but not when run from Xcode, where
    // it would quietly observe nothing and skip.
    setenv("KSCRASH_FORCE_ENABLE_WATCHDOG", "1", 1);

    NSString *directory = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"KSCrashHangTest-%d", getpid()]];
    mkdir(directory.fileSystemRepresentation, 0755);
    strlcpy(g_directory, directory.fileSystemRepresentation, sizeof(g_directory));

    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify,
                                                    .handleWithResult = stubHandleWithResult,
                                                    .getRunSidecarPath = stubRunSidecarPath };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);
}

void hangtest_disarm(void)
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(false, NULL);
    // A hang in progress finishes before a disabled monitor stops, and the main
    // thread is what ends it, so let the main thread go idle until it has.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (kscm_watchdog_testcode_isRunning() && deadline.timeIntervalSinceNow > 0) {
        if ([NSThread isMainThread]) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        } else {
            [NSThread sleepForTimeInterval:0.01];
        }
    }
    if (!kscm_watchdog_testcode_isRunning()) {
        [[NSFileManager defaultManager] removeItemAtPath:@(g_directory) error:nil];
    }
    unsetenv("KSCRASH_FORCE_ENABLE_WATCHDOG");
}

bool hangtest_isArmed(void) { return kshang_isEnabled(); }
