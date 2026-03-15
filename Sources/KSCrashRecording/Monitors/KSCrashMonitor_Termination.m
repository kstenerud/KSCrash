//
//  KSCrashMonitor_Termination.m
//
//  Created by Alexander Cohen on 2026-03-07.
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

#import "KSCrashMonitor_Termination.h"

#import "KSCrashC.h"
#import "KSCrashMonitorHelper.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportVersion.h"
#import "KSCrashRunContext.h"
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>
#import <signal.h>
#import <stdatomic.h>
#import <string.h>

#import "KSLogger.h"

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static const char *const kMonitorName = "Termination";

static atomic_bool g_isEnabled = false;

/** Whether this reason requires stitching an injected report from the Termination monitor. */
static bool needsStitch(KSTerminationReason reason)
{
    switch (reason) {
        case KSTerminationReasonLowBattery:
        case KSTerminationReasonMemoryLimit:
        case KSTerminationReasonMemoryPressure:
        case KSTerminationReasonThermal:
        case KSTerminationReasonCPU:
        case KSTerminationReasonUnexplained:
            return true;
        default:
            return false;
    }
}

// ============================================================================
#pragma mark - Report Generation -
// ============================================================================

/** Convert a monotonic timestamp to unix epoch microseconds using the lifecycle reference pair. */
static uint64_t monotonicToWallClockUs(const KSCrash_LifecycleData *lifecycle, uint64_t monotonicNs)
{
    if (lifecycle->wallClockAtStartNs == 0 || lifecycle->monotonicAtStartNs == 0 || monotonicNs == 0) {
        return 0;
    }
    if (monotonicNs < lifecycle->monotonicAtStartNs) {
        return 0;
    }
    uint64_t wallNs = lifecycle->wallClockAtStartNs + (monotonicNs - lifecycle->monotonicAtStartNs);
    return wallNs / 1000;
}

/** Build and inject a retroactive report for a resource-based termination.
 *
 *  Only resource kills (OOM, thermal, CPU, battery) reach this path —
 *  clean exits, crashes, hangs, and system changes are filtered out by the caller.
 */
static void injectReport(const char *lastRunID, const KSCrash_LifecycleData *lifecycle, KSTerminationReason reason,
                         uint64_t mostRecentMonotonicNs)
{
    NSMutableDictionary *report = [NSMutableDictionary dictionary];

    // report section
    uint64_t timestampUs = monotonicToWallClockUs(lifecycle, mostRecentMonotonicNs);
    NSMutableDictionary *reportSection = [NSMutableDictionary dictionary];
    reportSection[KSCrashField_ID] = [NSUUID UUID].UUIDString;
    reportSection[KSCrashField_Version] = @KSCRASH_REPORT_VERSION;
    reportSection[KSCrashField_RunID] = @(lastRunID);
    reportSection[KSCrashField_Timestamp] = @(timestampUs);
    reportSection[KSCrashField_Type] = KSCrashReportType_Standard;
    reportSection[KSCrashField_MonitorId] = @(kMonitorName);
    report[KSCrashField_Report] = reportSection;

    // crash.error section
    NSMutableDictionary *errorSection = [NSMutableDictionary dictionary];
    errorSection[KSCrashField_Type] = KSCrashExcType_Termination;
    errorSection[KSCrashField_TerminationReason] = @(kstermination_reasonToString(reason));
    errorSection[KSCrashField_IsFatal] = @YES;
    errorSection[KSCrashField_IsCleanExit] = @NO;
    // Synthetic SIGKILL for backward compatibility.
    errorSection[KSCrashExcType_Signal] = @{
        KSCrashField_Signal : @(SIGKILL),
        KSCrashField_Name : @"SIGKILL",
    };

    NSMutableDictionary *crashSection = [NSMutableDictionary dictionary];
    crashSection[KSCrashField_Error] = errorSection;
    report[KSCrashField_Crash] = crashSection;

    NSError *error = nil;
    NSData *jsonData = [KSJSONCodec encode:report options:KSJSONEncodeOptionNone error:&error];
    if (!jsonData) {
        KSLOG_ERROR(@"Failed to encode Termination report: %@", error);
        return;
    }

    kscrash_addUserReport((const char *)jsonData.bytes, (int)jsonData.length);
    KSLOG_INFO(@"Injected Termination report for run %s: %s", lastRunID, kstermination_reasonToString(reason));
}

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

static const char *monitorId(__unused void *context) { return kMonitorName; }

static void setEnabled(bool isEnabled, __unused void *context)
{
    bool expected = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expected, isEnabled)) {
        return;
    }
}

static bool isEnabled_func(__unused void *context) { return atomic_load(&g_isEnabled); }

static void notifyPostSystemEnable(__unused void *context)
{
    const KSCrashRunContext *ctx = ksruncontext_previousRunContext();
    if (!needsStitch(ctx->terminationReason) || !ctx->lifecycleValid) {
        return;
    }

    injectReport(ctx->runID, &ctx->lifecycle, ctx->terminationReason, ctx->mostRecentTimestampNs);
}

KSCrashMonitorAPI *kscm_termination_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled_func;
        api.notifyPostSystemEnable = notifyPostSystemEnable;
    }
    return &api;
}

