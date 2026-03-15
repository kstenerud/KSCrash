//
//  KSCrashRunContext.m
//
//  Created by Alexander Cohen on 2026-03-15.
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

#import "KSCrashRunContext.h"

#import "KSCrashAppMemory.h"
#import "KSCrashC.h"
#import "KSFileUtils.h"

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <stdatomic.h>
#import <string.h>
#import <unistd.h>

#import "KSLogger.h"

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static KSCrashRunContext g_context = { 0 };
static _Atomic(KSCrashSidecarRunPathForRunIDProviderFunc) g_pathForRunID = NULL;

// ============================================================================
#pragma mark - Sidecar Reading -
// ============================================================================

static bool readResourceData(const char *path, KSCrash_ResourceData *out)
{
    if (!path || !out) {
        return false;
    }

    int fd = open(path, O_RDONLY);
    if (fd == -1) {
        return false;
    }

    memset(out, 0, sizeof(*out));
    bool ok = ksfu_readBytesFromFD(fd, (char *)out, (int)sizeof(*out));
    close(fd);

    if (!ok || out->magic != KSRESOURCE_MAGIC || out->version == 0 || out->version > KSCrash_Resource_CurrentVersion) {
        return false;
    }
    return true;
}

// ============================================================================
#pragma mark - Determine Reason -
// ============================================================================

/** Determine why the previous run was terminated.
 *
 *  Priority: lifecycle guards (clean/crash/hang) > system changes
 *  (OS upgrade > app upgrade > reboot) > resource checks (memory >
 *  CPU > thermal > battery) > unexplained.
 */
static KSTerminationReason determineReason(const KSCrash_LifecycleData *prevLifecycle,
                                           const KSCrash_ResourceData *prevResource,
                                           const KSCrash_SystemData *prevSystem, const KSCrash_SystemData *currSystem)
{
    if (prevLifecycle == NULL) {
        return KSTerminationReasonFirstLaunch;
    }

    // Lifecycle guards checked before missing-sidecar guard: if the lifecycle
    // records a crash or hang, a missing resource/system sidecar must not
    // erase that evidence.

    if (prevLifecycle->cleanShutdown) {
        return KSTerminationReasonClean;
    }
    if (prevLifecycle->fatalReported) {
        return KSTerminationReasonCrash;
    }
    if (prevLifecycle->hangInProgress) {
        return KSTerminationReasonHang;
    }

    // A prior run existed but resource or system data is missing — can't
    // classify further.
    if (prevResource == NULL || prevSystem == NULL) {
        return KSTerminationReasonUnexplained;
    }

    // --- System changes ---

    if (currSystem != NULL) {
        if (strcmp(prevSystem->systemVersion, currSystem->systemVersion) != 0 ||
            strcmp(prevSystem->osVersion, currSystem->osVersion) != 0) {
            return KSTerminationReasonOSUpgrade;
        }

        if (strcmp(prevSystem->bundleShortVersion, currSystem->bundleShortVersion) != 0 ||
            strcmp(prevSystem->bundleVersion, currSystem->bundleVersion) != 0) {
            return KSTerminationReasonAppUpgrade;
        }

        // Allow 30s jitter — the reported boot time can shift slightly between reads.
        if (prevSystem->bootTimestamp != 0 && currSystem->bootTimestamp != 0) {
            int64_t diff = currSystem->bootTimestamp - prevSystem->bootTimestamp;
            if (diff > 30 || diff < -30) {
                return KSTerminationReasonReboot;
            }
        }
    }

    // --- Resource-based termination ---

    if (prevResource->memoryLevel >= KSCrashAppMemoryStateCritical) {
        return KSTerminationReasonMemoryLimit;
    }

    if (prevResource->memoryPressure >= KSCrashAppMemoryStateCritical) {
        return KSTerminationReasonMemoryPressure;
    }

    // 80% of all cores.
    uint32_t totalCPU = (uint32_t)prevResource->cpuUsageUser + (uint32_t)prevResource->cpuUsageSystem;
    uint32_t cpuThreshold = (uint32_t)prevResource->cpuCoreCount * 800;
    if (cpuThreshold > 0 && totalCPU > cpuThreshold) {
        return KSTerminationReasonCPU;
    }

    if (prevResource->thermalState >= (uint8_t)NSProcessInfoThermalStateCritical) {
        return KSTerminationReasonThermal;
    }

    if (prevResource->batteryLevel <= 1 && prevResource->batteryState == 1) {
        return KSTerminationReasonLowBattery;
    }

    return KSTerminationReasonUnexplained;
}

// ============================================================================
#pragma mark - API -
// ============================================================================

void ksruncontext_init(KSCrashSidecarRunPathForRunIDProviderFunc pathForRunID)
{
    atomic_store(&g_pathForRunID, pathForRunID);

    const char *lastRunID = kscrash_getLastRunID();
    memset(&g_context, 0, sizeof(g_context));

    if (!lastRunID || lastRunID[0] == '\0') {
        g_context.terminationReason = KSTerminationReasonFirstLaunch;
        KSLOG_DEBUG(@"No previous run ID — first launch");
        return;
    }

    ksruncontext_contextForRunID(lastRunID, &g_context);

    KSLOG_DEBUG(@"Previous run %s: %s", lastRunID, kstermination_reasonToString(g_context.terminationReason));
}

bool ksruncontext_contextForRunID(const char *runID, KSCrashRunContext *outContext)
{
    if (!outContext) {
        return false;
    }

    memset(outContext, 0, sizeof(*outContext));

    if (!runID || runID[0] == '\0') {
        outContext->terminationReason = KSTerminationReasonFirstLaunch;
        return false;
    }

    strlcpy(outContext->runID, runID, sizeof(outContext->runID));

    KSCrashSidecarRunPathForRunIDProviderFunc pathForRunID = atomic_load(&g_pathForRunID);
    if (!pathForRunID) {
        outContext->terminationReason = KSTerminationReasonUnexplained;
        return false;
    }

    char sidecarPath[KSFU_MAX_PATH_LENGTH];
    bool anyValid = false;

    if (pathForRunID("Lifecycle", runID, sidecarPath, sizeof(sidecarPath))) {
        outContext->lifecycleValid = kslifecycle_readData(sidecarPath, &outContext->lifecycle);
        anyValid |= outContext->lifecycleValid;
    }

    if (pathForRunID("Resource", runID, sidecarPath, sizeof(sidecarPath))) {
        outContext->resourceValid = readResourceData(sidecarPath, &outContext->resource);
        anyValid |= outContext->resourceValid;
    }

    if (pathForRunID("System", runID, sidecarPath, sizeof(sidecarPath))) {
        outContext->systemValid = kscm_system_getSystemDataForPath(sidecarPath, &outContext->system);
        anyValid |= outContext->systemValid;
    }

    KSCrash_SystemData currSystem = {};
    bool hasCurrSystem = kscm_system_getSystemData(&currSystem);

    outContext->terminationReason =
        determineReason(outContext->lifecycleValid ? &outContext->lifecycle : NULL,
                        outContext->resourceValid ? &outContext->resource : NULL,
                        outContext->systemValid ? &outContext->system : NULL, hasCurrSystem ? &currSystem : NULL);
    outContext->producedReport = kstermination_producesReport(outContext->terminationReason);

    // Most recent resource timestamp — used as the report timestamp when
    // the Termination monitor injects a retroactive report.
    uint64_t mostRecentNs = 0;
    if (outContext->resourceValid) {
        uint64_t candidates[] = {
            outContext->resource.memoryUpdatedAtNs,   outContext->resource.cpuUpdatedAtNs,
            outContext->resource.batteryUpdatedAtNs,  outContext->resource.thermalUpdatedAtNs,
            outContext->resource.lowPowerUpdatedAtNs, outContext->resource.dataProtectionUpdatedAtNs,
        };
        for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
            if (candidates[i] > mostRecentNs) {
                mostRecentNs = candidates[i];
            }
        }
    }
    if (outContext->lifecycleValid && mostRecentNs == 0) {
        mostRecentNs = outContext->lifecycle.appStateTransitionTimeNs;
    }
    outContext->mostRecentTimestampNs = mostRecentNs;

    return anyValid;
}

const KSCrashRunContext *ksruncontext_previousRunContext(void) { return &g_context; }

// ============================================================================
#pragma mark - Testing API -
// ============================================================================

__attribute__((unused))  // For tests. Declared as extern in TestCase
KSTerminationReason
ksruncontext_testcode_determineReason(const KSCrash_LifecycleData *prevLifecycle,
                                      const KSCrash_ResourceData *prevResource, const KSCrash_SystemData *prevSystem,
                                      const KSCrash_SystemData *currSystem)
{
    return determineReason(prevLifecycle, prevResource, prevSystem, currSystem);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void ksruncontext_testcode_setReason(KSTerminationReason reason)
{
    g_context.terminationReason = reason;
    g_context.producedReport = kstermination_producesReport(reason);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void ksruncontext_testcode_setLifecycleData(const KSCrash_LifecycleData *data)
{
    if (data) {
        g_context.lifecycleValid = true;
        g_context.lifecycle = *data;
    } else {
        g_context.lifecycleValid = false;
        memset(&g_context.lifecycle, 0, sizeof(g_context.lifecycle));
    }
}
