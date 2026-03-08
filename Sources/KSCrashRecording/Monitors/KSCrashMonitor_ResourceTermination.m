//
//  KSCrashMonitor_ResourceTermination.m
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

#import "KSCrashMonitor_ResourceTermination.h"

#import "KSCrashAppMemory.h"
#import "KSCrashC.h"
#import "KSCrashMonitorHelper.h"
#import "KSCrashMonitor_Lifecycle.h"
#import "KSCrashMonitor_Resource.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportVersion.h"
#import "KSJSONCodecObjC.h"

#import <Foundation/Foundation.h>
#import <signal.h>
#import <stdatomic.h>

#import "KSLogger.h"

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static const char *const kMonitorName = "ResourceTermination";

static atomic_bool g_isEnabled = false;

// ============================================================================
#pragma mark - Termination Reason -
// ============================================================================

const char *ksresourcetermination_reasonToString(KSResourceTerminationReason reason)
{
    switch (reason) {
        case KSResourceTerminationReasonLowBattery:
            return "low_battery";
        case KSResourceTerminationReasonMemoryLimit:
            return "memory_limit";
        case KSResourceTerminationReasonMemoryPressure:
            return "memory_pressure";
        case KSResourceTerminationReasonThermal:
            return "thermal";
        case KSResourceTerminationReasonCPU:
            return "cpu";
        case KSResourceTerminationReasonUnexplained:
            return "unexplained";
        case KSResourceTerminationReasonNone:
        default:
            return "none";
    }
}

/** Determine whether the previous run was terminated due to resource exhaustion.
 *
 *  Returns None if lifecycle indicates a clean shutdown, a crash handler ran,
 *  a hang was in progress (the Watchdog already has a report), or no resource
 *  data is available. Returns Unexplained when the termination was abnormal
 *  but no specific resource threshold was exceeded.
 *
 *  Priority: memoryLimit > memoryPressure > cpu > thermal > battery.
 *  Memory limit (app exceeded its Jetsam allocation) is the most specific signal.
 *  CPU and thermal come next since high resource usage often causes heat and
 *  battery drain — battery is a symptom rather than a root cause.
 */
static KSResourceTerminationReason determineReason(const KSCrash_LifecycleData *lifecycle,
                                                   const KSCrash_ResourceData *res)
{
    if (lifecycle->cleanShutdown || lifecycle->fatalReported || lifecycle->hangInProgress) {
        return KSResourceTerminationReasonNone;
    }

    if (res == NULL) {
        return KSResourceTerminationReasonNone;
    }

    // Memory limit: app exceeded its per-process allocation (Jetsam).
    if (res->memoryLevel >= KSCrashAppMemoryStateCritical) {
        return KSResourceTerminationReasonMemoryLimit;
    }

    // Memory pressure: system-wide memory pressure killed the app.
    if (res->memoryPressure >= KSCrashAppMemoryStateCritical) {
        return KSResourceTerminationReasonMemoryPressure;
    }

    // CPU: total usage > cpuCoreCount * 800 permil (80% of all cores).
    uint32_t totalCPU = (uint32_t)res->cpuUsageUser + (uint32_t)res->cpuUsageSystem;
    uint32_t threshold = (uint32_t)res->cpuCoreCount * 800;
    if (threshold > 0 && totalCPU > threshold) {
        return KSResourceTerminationReasonCPU;
    }

    // Thermal critical.
    if (res->thermalState >= (uint8_t)NSProcessInfoThermalStateCritical) {
        return KSResourceTerminationReasonThermal;
    }

    // Low battery: device powered off while unplugged.
    if (res->batteryLevel <= 1 && res->batteryState == 1) {
        return KSResourceTerminationReasonLowBattery;
    }

    // Abnormal termination but no resource threshold exceeded.
    return KSResourceTerminationReasonUnexplained;
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

/** Build and inject a retroactive report for the terminated previous run. */
static void injectReport(const char *lastRunID, const KSCrash_LifecycleData *lifecycle,
                         KSResourceTerminationReason reason, uint64_t mostRecentMonotonicNs)
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
    errorSection[KSCrashField_Type] = KSCrashExcType_ResourceTermination;
    errorSection[KSCrashField_TerminationReason] = @(ksresourcetermination_reasonToString(reason));
    errorSection[KSCrashField_IsFatal] = @YES;
    errorSection[KSCrashField_IsCleanExit] = @NO;
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
        KSLOG_ERROR(@"Failed to encode ResourceTermination report: %@", error);
        return;
    }

    kscrash_addUserReport((const char *)jsonData.bytes, (int)jsonData.length);
    KSLOG_INFO(@"Injected ResourceTermination report for run %s: %s", lastRunID,
               ksresourcetermination_reasonToString(reason));
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
    const char *lastRunID = kscrash_getLastRunID();
    if (!lastRunID || lastRunID[0] == '\0') {
        KSLOG_DEBUG(@"No previous run ID — first launch, skipping ResourceTermination check");
        return;
    }

    KSCrash_LifecycleData lifecycle = {};
    if (!kslifecycle_getSnapshotForRunID(lastRunID, &lifecycle)) {
        KSLOG_DEBUG(@"Could not read Lifecycle sidecar for run %s", lastRunID);
        return;
    }

    // Read Resource sidecar and determine termination cause.
    KSCrash_ResourceData resource = {};
    bool hasResource = ksresource_getSnapshotForRunID(lastRunID, &resource);

    KSResourceTerminationReason reason = determineReason(&lifecycle, hasResource ? &resource : NULL);

    if (reason == KSResourceTerminationReasonNone) {
        KSLOG_DEBUG(@"Previous run %s: not a resource termination", lastRunID);
        return;
    }

    // Use the most recent per-group timestamp as the report timestamp.
    // Fall back to the lifecycle's last state transition if no resource timestamps exist.
    uint64_t mostRecentTimestampNs = 0;
    if (hasResource) {
        uint64_t candidates[] = { resource.memoryUpdatedAtNs,   resource.cpuUpdatedAtNs,
                                  resource.batteryUpdatedAtNs,  resource.thermalUpdatedAtNs,
                                  resource.lowPowerUpdatedAtNs, resource.dataProtectionUpdatedAtNs };
        for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
            if (candidates[i] > mostRecentTimestampNs) {
                mostRecentTimestampNs = candidates[i];
            }
        }
    }
    if (mostRecentTimestampNs == 0) {
        mostRecentTimestampNs = lifecycle.appStateTransitionTimeNs;
    }

    injectReport(lastRunID, &lifecycle, reason, mostRecentTimestampNs);
}

KSCrashMonitorAPI *kscm_resourcetermination_getAPI(void)
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

__attribute__((unused))  // For tests. Declared as extern in TestCase
KSResourceTerminationReason
kscm_resourcetermination_testcode_determineReason(const KSCrash_LifecycleData *lifecycle,
                                                  const KSCrash_ResourceData *resource)
{
    return determineReason(lifecycle, resource);
}
