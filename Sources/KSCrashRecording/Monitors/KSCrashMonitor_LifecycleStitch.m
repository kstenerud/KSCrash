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
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>

#import "KSLogger.h"

char *kscm_lifecycle_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope,
                                  __unused void *context)
{
    if (!report || !sidecarPath || scope != KSCrashSidecarScopeRun) {
        return NULL;
    }

    KSCrash_LifecycleData lc = {};
    if (!kslifecycle_readData(sidecarPath, &lc)) {
        KSLOG_ERROR(@"Failed to read lifecycle sidecar at %s", sidecarPath);
        return NULL;
    }

    // Decode the report JSON
    NSData *reportData = [NSData dataWithBytesNoCopy:(void *)report length:strlen(report) freeWhenDone:NO];
    NSDictionary *decoded = [KSJSONCodec decode:reportData options:KSJSONDecodeOptionNone error:nil];
    if (![decoded isKindOfClass:[NSDictionary class]]) {
        KSLOG_ERROR(@"Failed to decode report JSON");
        return NULL;
    }
    NSMutableDictionary *dict = [decoded mutableCopy];

    // Navigate to or create report.system
    NSMutableDictionary *systemDict;
    id systemVal = dict[KSCrashField_System];
    if ([systemVal isKindOfClass:[NSDictionary class]]) {
        systemDict = [systemVal mutableCopy];
    } else {
        systemDict = [NSMutableDictionary dictionary];
    }

    // Build application_stats from the sidecar struct
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

    systemDict[KSCrashField_AppStats] = statsDict;
    dict[KSCrashField_System] = systemDict;

    // Encode back to JSON
    NSError *error = nil;
    NSData *newData = [KSJSONCodec encode:dict options:KSJSONEncodeOptionNone error:&error];
    if (!newData) {
        KSLOG_ERROR(@"Failed to encode stitched report: %@", error);
        return NULL;
    }

    char *result = (char *)malloc(newData.length + 1);
    if (!result) {
        return NULL;
    }
    memcpy(result, newData.bytes, newData.length);
    result[newData.length] = '\0';
    return result;
}
