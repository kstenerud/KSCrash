//
//  KSCrashMonitor_WatchdogStitch.m
//
//  Created by Alexander Cohen on 2026-02-01.
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

#import "KSCrashMonitor_WatchdogSidecar.h"

#import "KSCrashAppTransitionState.h"
#import "KSCrashMonitor_Watchdog.h"
#import "KSCrashReportFields.h"
#import "KSCrashRunContext.h"
#import "KSCrashStitch.h"

#import <Foundation/Foundation.h>

#import "KSLogger.h"

CFDictionaryRef kscm_watchdog_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                   KSCrashSidecarScope scope, __unused void *context)
{
    __block KSCrash_HangData sc = {};
    NSDictionary *stitched = ksstitch_stitchedReport(
        (__bridge NSDictionary *)reportDict, sidecarPath, scope, KSCrashSidecarScopeRun,
        ^(const char *path) {
            return kssidecar_readHang(path, &sc);
        },
        ^(NSMutableDictionary *report) {
            // The hang goes into crash.error. A report without one has nowhere to
            // take it, and no later read adds one, so it delivers without the hang.
            id crashValue = report[KSCrashField_Crash];
            if (![crashValue isKindOfClass:[NSDictionary class]] ||
                ![crashValue[KSCrashField_Error] isKindOfClass:[NSDictionary class]]) {
                KSLOG_ERROR(@"Malformed report: no crash.error object to add the hang to");
                return;
            }
            NSMutableDictionary *error =
                ksstitch_object(ksstitch_object(report, KSCrashField_Crash), KSCrashField_Error);

            // The hang section goes on every report from the run, as context (an
            // exception that occurred during a hang, say). Only the Watchdog's own
            // reports have their fatality and error type changed.
            NSMutableDictionary *hang = [NSMutableDictionary dictionary];
            hang[KSCrashField_HangStartNanoseconds] = @(sc.startTimestamp);
            hang[KSCrashField_HangStartRole] = @(kstaskrole_toString(sc.startRole));
            hang[KSCrashField_HangStartTransitionState] = @(ksapp_transitionStateToString(sc.startTransitionState));
            hang[KSCrashField_HangEndNanoseconds] = @(sc.endTimestamp);
            hang[KSCrashField_HangEndRole] = @(kstaskrole_toString(sc.endRole));
            hang[KSCrashField_HangEndTransitionState] = @(ksapp_transitionStateToString(sc.endTransitionState));
            error[KSCrashField_Hang] = hang;

            id reportSection = report[KSCrashField_Report];
            id monitorId =
                [reportSection isKindOfClass:[NSDictionary class]] ? reportSection[KSCrashField_MonitorId] : nil;
            bool isWatchdogReport =
                [monitorId isKindOfClass:[NSString class]] && [monitorId isEqualToString:@"Watchdog"];

            if (sc.recovered) {
                hang[KSCrashField_HangRecovered] = @YES;
                if (isWatchdogReport) {
                    error[KSCrashField_Type] = KSCrashExcType_Hang;
                    [error removeObjectForKey:KSCrashField_Signal];
                    [error removeObjectForKey:KSCrashField_Mach];
                    [error removeObjectForKey:KSCrashField_ExitReason];
                    error[KSCrashField_IsFatal] = @NO;
                    [error removeObjectForKey:KSCrashField_IsCleanExit];
                }
            } else if (isWatchdogReport) {
                error[KSCrashField_IsFatal] = @YES;
                error[KSCrashField_IsCleanExit] = @NO;
            }
        });
    return (__bridge_retained CFDictionaryRef)stitched;
}
