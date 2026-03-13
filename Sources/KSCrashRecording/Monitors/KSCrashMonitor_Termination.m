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

#import "KSCrashAppMemory.h"
#import "KSCrashC.h"
#import "KSCrashMonitorHelper.h"
#import "KSCrashMonitor_Lifecycle.h"
#import "KSCrashMonitor_Resource.h"
#import "KSCrashMonitor_System.h"
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

static const char *const kMonitorName = "Termination";

static atomic_bool g_isEnabled = false;
static KSTerminationReason g_reason = KSTerminationReasonNone;

// ============================================================================
#pragma mark - Termination Reason -
// ============================================================================

const char *kstermination_reasonToString(KSTerminationReason reason)
{
    switch (reason) {
        case KSTerminationReasonClean:
            return "clean";
        case KSTerminationReasonCrash:
            return "crash";
        case KSTerminationReasonHang:
            return "hang";
        case KSTerminationReasonFirstLaunch:
            return "first_launch";
        case KSTerminationReasonLowBattery:
            return "low_battery";
        case KSTerminationReasonMemoryLimit:
            return "memory_limit";
        case KSTerminationReasonMemoryPressure:
            return "memory_pressure";
        case KSTerminationReasonThermal:
            return "thermal";
        case KSTerminationReasonCPU:
            return "cpu";
        case KSTerminationReasonOSUpgrade:
            return "os_upgrade";
        case KSTerminationReasonAppUpgrade:
            return "app_upgrade";
        case KSTerminationReasonReboot:
            return "reboot";
        case KSTerminationReasonUnexplained:
            return "unexplained";
        case KSTerminationReasonNone:
        default:
            return "none";
    }
}

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

bool kstermination_producesReport(KSTerminationReason reason)
{
    switch (reason) {
        case KSTerminationReasonCrash:
        case KSTerminationReasonHang:
            return true;
        default:
            return needsStitch(reason);
    }
}

KSTerminationReason kstermination_getReason(void) { return g_reason; }

/** Determine why the previous run was terminated.
 *
 *  Lifecycle guards first: clean shutdown, crash already reported, hang in progress.
 *  Then first-launch detection (no previous system sidecar). Then system changes
 *  (OS upgrade > app upgrade > reboot). Then resource checks (memory limit >
 *  memory pressure > CPU > thermal > battery). Falls back to "unexplained" if
 *  resource data exists but nothing matched.
 */
static KSTerminationReason determineReason(const KSCrash_LifecycleData *prevLifecycle,
                                           const KSCrash_ResourceData *prevResource,
                                           const KSCrash_SystemData *prevSystem, const KSCrash_SystemData *currSystem)
{
    // --- First launch (missing any previous sidecar means no prior run to analyze) ---

    if (prevLifecycle == NULL || prevResource == NULL || prevSystem == NULL) {
        return KSTerminationReasonFirstLaunch;
    }

    // --- Already-handled exits ---

    if (prevLifecycle->cleanShutdown) {
        return KSTerminationReasonClean;
    }
    if (prevLifecycle->fatalReported) {
        return KSTerminationReasonCrash;
    }
    if (prevLifecycle->hangInProgress) {
        return KSTerminationReasonHang;
    }

    // --- System changes (priority: OS upgrade > app upgrade > reboot) ---

    if (currSystem != NULL) {
        // OS upgrade: systemVersion or osVersion changed.
        if (strcmp(prevSystem->systemVersion, currSystem->systemVersion) != 0 ||
            strcmp(prevSystem->osVersion, currSystem->osVersion) != 0) {
            return KSTerminationReasonOSUpgrade;
        }

        // App upgrade: marketing version or build number changed.
        if (strcmp(prevSystem->bundleShortVersion, currSystem->bundleShortVersion) != 0 ||
            strcmp(prevSystem->bundleVersion, currSystem->bundleVersion) != 0) {
            return KSTerminationReasonAppUpgrade;
        }

        // Reboot: boot timestamp changed (different boot cycle).
        // Skip if either is zero (couldn't read it). Allow 30s jitter since
        // the reported boot time can shift slightly between reads.
        if (prevSystem->bootTimestamp != 0 && currSystem->bootTimestamp != 0) {
            int64_t diff = currSystem->bootTimestamp - prevSystem->bootTimestamp;
            if (diff > 30 || diff < -30) {
                return KSTerminationReasonReboot;
            }
        }
    }

    // --- Resource-based termination (priority: memory > CPU > thermal > battery) ---

    // Memory limit: app exceeded its per-process allocation (Jetsam).
    if (prevResource->memoryLevel >= KSCrashAppMemoryStateCritical) {
        return KSTerminationReasonMemoryLimit;
    }

    // Memory pressure: system-wide memory pressure killed the app.
    if (prevResource->memoryPressure >= KSCrashAppMemoryStateCritical) {
        return KSTerminationReasonMemoryPressure;
    }

    // CPU: total usage > cpuCoreCount * 800 permil (80% of all cores).
    uint32_t totalCPU = (uint32_t)prevResource->cpuUsageUser + (uint32_t)prevResource->cpuUsageSystem;
    uint32_t cpuThreshold = (uint32_t)prevResource->cpuCoreCount * 800;
    if (cpuThreshold > 0 && totalCPU > cpuThreshold) {
        return KSTerminationReasonCPU;
    }

    // Thermal critical.
    if (prevResource->thermalState >= (uint8_t)NSProcessInfoThermalStateCritical) {
        return KSTerminationReasonThermal;
    }

    // Low battery: device powered off while unplugged.
    if (prevResource->batteryLevel <= 1 && prevResource->batteryState == 1) {
        return KSTerminationReasonLowBattery;
    }

    return KSTerminationReasonUnexplained;
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
    const char *lastRunID = kscrash_getLastRunID();
    if (!lastRunID || lastRunID[0] == '\0') {
        g_reason = KSTerminationReasonFirstLaunch;
        KSLOG_DEBUG(@"No previous run ID — first launch");
        return;
    }

    // Read all sidecars. Missing ones are passed as NULL — determineReason
    // treats any NULL previous sidecar as a first launch.
    KSCrash_LifecycleData lifecycle = {};
    bool hasLifecycle = kslifecycle_getSnapshotForRunID(lastRunID, &lifecycle);

    KSCrash_SystemData prevSystem = {};
    KSCrash_SystemData currSystem = {};
    bool hasPrevSystem = kscm_system_getSystemDataForRunID(lastRunID, &prevSystem);
    bool hasCurrSystem = kscm_system_getSystemData(&currSystem);

    KSCrash_ResourceData resource = {};
    bool hasResource = ksresource_getSnapshotForRunID(lastRunID, &resource);

    g_reason = determineReason(hasLifecycle ? &lifecycle : NULL, hasResource ? &resource : NULL,
                               hasPrevSystem ? &prevSystem : NULL, hasCurrSystem ? &currSystem : NULL);

    KSLOG_DEBUG(@"Previous run %s: %s", lastRunID, kstermination_reasonToString(g_reason));

    if (!needsStitch(g_reason)) {
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
    if (hasLifecycle && mostRecentTimestampNs == 0) {
        mostRecentTimestampNs = lifecycle.appStateTransitionTimeNs;
    }

    injectReport(lastRunID, &lifecycle, g_reason, mostRecentTimestampNs);
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

__attribute__((unused))  // For tests. Declared as extern in TestCase
KSTerminationReason
kscm_termination_testcode_determineReason(const KSCrash_LifecycleData *prevLifecycle,
                                          const KSCrash_ResourceData *prevResource,
                                          const KSCrash_SystemData *prevSystem, const KSCrash_SystemData *currSystem)
{
    return determineReason(prevLifecycle, prevResource, prevSystem, currSystem);
}
