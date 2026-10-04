//
//  KSCrashMonitor_LifecycleStitch.m
//
//  Created by Alexander Cohen on 2026-02-26.
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

#import "KSCrashMonitor_Lifecycle.h"
#import "KSCrashRunContext.h"

#import "KSCrashAppTransitionState.h"
#import "KSCrashReportFields.h"
#import "KSCrashStitch.h"

#import <Foundation/Foundation.h>

CFDictionaryRef kscm_lifecycle_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                    KSCrashSidecarScope scope, __unused void *context)
{
    if (reportDict == NULL) {
        return NULL;
    }
    if (scope != KSCrashSidecarScopeRun) {
        // Not this monitor's scope (e.g. the final pass, which has no sidecar file).
        CFRetain(reportDict);
        return reportDict;
    }
    if (sidecarPath == NULL) {
        return NULL;
    }

    // A read the environment failed is worth retrying: NULL is the retry signal,
    // which finalization honors by leaving the report, session_id included,
    // for a later read. A sidecar that is gone or corrupt
    // never reads better, and it is not session_id's data source (that is the
    // run's .sessions file), so only application_stats is skipped.
    KSCrash_LifecycleData lc = {};
    KSCrashSidecarReadResult readResult = kssidecar_readLifecycle(sidecarPath, &lc);
    if (readResult == KSCrashSidecarReadFailure) {
        return NULL;
    }
    bool haveLifecycleData = readResult == KSCrashSidecarReadOK;

    NSMutableDictionary *dict = [(__bridge NSDictionary *)reportDict mutableCopy];

    if (haveLifecycleData) {
        NSMutableDictionary *statsDict = [NSMutableDictionary dictionary];
        statsDict[KSCrashField_AppActive] = @((BOOL)lc.applicationIsActive);
        statsDict[KSCrashField_AppInFG] = @((BOOL)lc.applicationIsInForeground);
        statsDict[KSCrashField_LaunchesSinceCrash] = @(lc.launchesSinceLastCrash);
        statsDict[KSCrashField_SessionsSinceCrash] = @(lc.sessionsSinceLastCrash);
        statsDict[KSCrashField_ActiveTimeSinceCrash] = @(kslifecycle_nsToSeconds(lc.activeDurationSinceLastCrashNs));
        statsDict[KSCrashField_BGTimeSinceCrash] = @(kslifecycle_nsToSeconds(lc.backgroundDurationSinceLastCrashNs));
        statsDict[KSCrashField_SessionsSinceLaunch] = @(lc.sessionsSinceLaunch);
        statsDict[KSCrashField_ActiveTimeSinceLaunch] = @(kslifecycle_nsToSeconds(lc.activeDurationSinceLaunchNs));
        statsDict[KSCrashField_BGTimeSinceLaunch] = @(kslifecycle_nsToSeconds(lc.backgroundDurationSinceLaunchNs));
        statsDict[KSCrashField_AppTransitionState] =
            @(ksapp_transitionStateToString((KSCrashAppTransitionState)lc.transitionState));
        statsDict[KSCrashField_UserPerceptible] = @((BOOL)lc.userPerceptible);
        statsDict[KSCrashField_TaskRole] = @(kstaskrole_toString(lc.taskRole));

        ksstitch_object(dict, KSCrashField_System)[KSCrashField_AppStats] = statsDict;
    }

    // session_id is added at stitch time, never at crash time; absent when the
    // run recorded no session.
    id reportVal = dict[KSCrashField_Report];
    id storedRunID = [reportVal isKindOfClass:[NSDictionary class]] ? reportVal[KSCrashField_RunID] : nil;
    NSString *runID = [storedRunID isKindOfClass:[NSString class]] ? storedRunID : nil;
    char sessionID[KSID_SIZE] = "";
    if (kslifecycle_copyLastSessionIDForRunID(runID.UTF8String, sessionID, sizeof(sessionID))) {
        ksstitch_object(dict, KSCrashField_Report)[KSCrashField_SessionID] = @(sessionID);
    }

    return (__bridge_retained CFDictionaryRef)dict;
}
