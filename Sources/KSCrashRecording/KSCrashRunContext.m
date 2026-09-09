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
#import "KSCrashCPUTracker.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportStoreC.h"
#import "KSDate.h"
#import "KSFileUtils.h"
#import "KSJSONCodecObjC.h"
#import "KSKeyValueStore.h"
#import "KSTerminationReason.h"

#import <Foundation/Foundation.h>
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#import "KSLogger.h"

// Defined in KSCrash.m. Forward-declared here to avoid importing KSCrash.h.
FOUNDATION_EXPORT const unsigned char KSCrashFrameworkVersionString[];

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static KSCrashRunContext g_context = { 0 };
static NSDictionary *g_summary = nil;

// KSCRS_RUN_SUMMARY_FILENAME_DIGITS is 19 because it covers INT64_MAX
// (9223372036854775807): any unix-epoch nanosecond value (~1.76e18 today) fits
// without overflow and all files in the dir sort lexically the same as they do
// numerically — tools that just `ls` the dir get the right order for free.
// Nanosecond resolution on the wall clock makes collisions between concurrent
// launches (e.g. app + extension) effectively impossible.

static NSDictionary *buildSummary(const KSCrashRunContext *ctx, const char *userInfoSidecarPath);

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

    if (prevLifecycle->cleanExit) {
        return KSTerminationReasonClean;
    }
    if (prevLifecycle->monitorHandlerRan) {
        return KSTerminationReasonCrash;
    }
    if (prevLifecycle->hangActive) {
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

        // Allow jitter — the reported boot time can shift slightly between reads.
        if (prevSystem->bootTimestamp != 0 && currSystem->bootTimestamp != 0) {
            int64_t diff = currSystem->bootTimestamp - prevSystem->bootTimestamp;
            if (diff > KSCRASH_REBOOT_JITTER_SECONDS || diff < -KSCRASH_REBOOT_JITTER_SECONDS) {
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

    if (prevResource->cpuState >= KSCrashCPUStateCritical) {
        return KSTerminationReasonCPU;
    }

    if (prevResource->thermalState >= (uint8_t)NSProcessInfoThermalStateCritical) {
        return KSTerminationReasonThermal;
    }

    if (prevResource->batteryLevel <= KSCRASH_BATTERY_LEVEL_CRITICAL &&
        prevResource->batteryState == KSCrashBatteryStateUnplugged) {
        return KSTerminationReasonLowBattery;
    }

    return KSTerminationReasonUnexplained;
}

// ============================================================================
#pragma mark - API -
// ============================================================================

void ksruncontext_init(KSCrashSidecarRunPathForRunIDProviderFunc pathForRunID)
{
    const char *lastRunID = kscrash_getLastRunID();
    memset(&g_context, 0, sizeof(g_context));
    g_summary = nil;

    if (!lastRunID || lastRunID[0] == '\0') {
        g_context.terminationReason = KSTerminationReasonFirstLaunch;
        KSLOG_DEBUG(@"No previous run ID — first launch");
        return;
    }

    ksruncontext_contextForRunID(lastRunID, pathForRunID, &g_context);

    // Build the summary from the same sidecar data we just read, while the
    // UserInfo path resolver is still in hand — callers of
    // ksruncontext_previousRunSummary() don't deal with sidecar paths.
    char userInfoPath[KSFU_MAX_PATH_LENGTH];
    const char *userInfoPathPtr = NULL;
    if (pathForRunID != NULL && pathForRunID("UserInfo", lastRunID, userInfoPath, sizeof(userInfoPath))) {
        userInfoPathPtr = userInfoPath;
    }
    g_summary = buildSummary(&g_context, userInfoPathPtr);

    KSLOG_DEBUG(@"Previous run %s: %s", lastRunID, kstermination_reasonToString(g_context.terminationReason));
}

bool ksruncontext_contextForRunID(const char *runID, KSCrashSidecarRunPathForRunIDProviderFunc pathForRunID,
                                  KSCrashRunContext *outContext)
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
        outContext->resourceValid = ksresource_readSnapshotFromPath(sidecarPath, &outContext->resource);
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
    // The lifecycle monitor updates appStateTransitionTimeNs on every state
    // change, including at clean shutdown and crash time, so it is frequently
    // newer than the last periodic resource poll. Fold it into the max rather
    // than using it only when there is no resource data at all; otherwise a run
    // that polled resources near launch and then ran for a while before exiting
    // cleanly or crashing reports ended_at near that stale poll.
    if (outContext->lifecycleValid && outContext->lifecycle.appStateTransitionTimeNs > mostRecentNs) {
        mostRecentNs = outContext->lifecycle.appStateTransitionTimeNs;
    }
    outContext->mostRecentTimestampNs = mostRecentNs;

    return anyValid;
}

const KSCrashRunContext *ksruncontext_previousRunContext(void) { return &g_context; }

void ksruncontext_persistPreviousRunSummary(const char *runSummariesPath)
{
    if (g_summary == nil || runSummariesPath == NULL || runSummariesPath[0] == '\0') {
        return;
    }

    if (!ksfu_makePath(runSummariesPath)) {
        KSLOG_ERROR(@"Failed to create run summary dir %s", runSummariesPath);
        return;
    }

    // Filename is the run's wall-clock start time in nanoseconds, zero-padded
    // to KSCRS_RUN_SUMMARY_FILENAME_DIGITS so all files in the dir lexically sort
    // the same as they do numerically. Nanoseconds (not ms) so concurrent
    // launches can't collide on the same prefix. `wallClockAtStartNs` comes
    // straight from the lifecycle sidecar that produced the summary, so it
    // matches the run being written.
    unsigned long long startedAtNs = (unsigned long long)g_context.lifecycle.wallClockAtStartNs;
    char path[KSFU_MAX_PATH_LENGTH];
    if (snprintf(path, sizeof(path), "%s/%0*llu.run", runSummariesPath, KSCRS_RUN_SUMMARY_FILENAME_DIGITS,
                 startedAtNs) >= (int)sizeof(path)) {
        KSLOG_ERROR(@"Run summary file path too long: %s/%0*llu.run", runSummariesPath,
                    KSCRS_RUN_SUMMARY_FILENAME_DIGITS, startedAtNs);
        return;
    }

    NSError *error = nil;
    NSData *data = [KSJSONCodec encode:g_summary options:KSJSONEncodeOptionNone error:&error];
    if (data == nil) {
        KSLOG_ERROR(@"Failed to encode run summary JSON: %@", error);
        return;
    }

    // C write — the decoder rejects truncated / invalid JSON on read, so a
    // crash mid-write is self-correcting; no atomic rename needed.
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        KSLOG_ERROR(@"Failed to open run summary file %s: errno=%d", path, errno);
        return;
    }
    if (!ksfu_writeBytesToFD(fd, (const char *)data.bytes, (int)data.length)) {
        KSLOG_ERROR(@"Failed to write run summary to %s: errno=%d", path, errno);
    }
    close(fd);
}

// ============================================================================
#pragma mark - Build Summary -
// ============================================================================

// Reserved UserInfo key, mirrors the one in -[KSCrash setUserID:].
static const char kUserIDKey[] = "com.kscrash.userid";

typedef struct {
    // Mutable result: the last string value seen for kUserIDKey, or nil if
    // only tombstones / absent. Retained by the iteration callbacks so the
    // outer function takes ownership at the end. `__strong` is explicit so
    // ARC retains on assignment and releases on struct destruction.
    __strong NSString *userID;
} UserIDReadContext;

static void userInfoOnString(const char *key, uint16_t keyLen, const char *value, uint16_t valueLen, void *ctx)
{
    UserIDReadContext *out = (UserIDReadContext *)ctx;
    if (keyLen != sizeof(kUserIDKey) - 1 || memcmp(key, kUserIDKey, keyLen) != 0) {
        return;
    }
    NSString *str = [[NSString alloc] initWithBytes:value length:valueLen encoding:NSUTF8StringEncoding];
    if (str) {
        out->userID = str;
    }
}

static void userInfoOnRemoved(const char *key, uint16_t keyLen, void *ctx)
{
    UserIDReadContext *out = (UserIDReadContext *)ctx;
    if (keyLen != sizeof(kUserIDKey) - 1 || memcmp(key, kUserIDKey, keyLen) != 0) {
        return;
    }
    out->userID = nil;
}

static NSString *readUserIDFromSidecar(const char *sidecarPath)
{
    if (sidecarPath == NULL || sidecarPath[0] == '\0') {
        return nil;
    }
    KSKeyValueStore *store = kskvs_create(sidecarPath, KSKVSModeRead, NULL, NULL);
    if (store == NULL) {
        return nil;
    }

    UserIDReadContext ctx = { .userID = nil };
    KSKVSCallbacks callbacks = {
        .onString = userInfoOnString,
        .onRemoved = userInfoOnRemoved,
    };
    kskvs_iterate(store, &callbacks, &ctx);
    kskvs_destroy(store);

    return ctx.userID;
}

// Returns the given C string as an NSString, or @"" if null/empty. Used for
// system-sidecar fields that must appear in the summary as non-null strings.
static NSString *safeString(const char *cstr)
{
    if (cstr == NULL || cstr[0] == '\0') {
        return @"";
    }
    return [NSString stringWithUTF8String:cstr] ?: @"";
}

// Wire string for the lifecycle sidecar's host kind byte.
static NSString *hostKindWireString(uint8_t hostKind)
{
    switch (hostKind) {
        case KSCrashRunSummaryHostKindApp:
            return @"app";
        case KSCrashRunSummaryHostKindExtension:
            return @"extension";
        case KSCrashRunSummaryHostKindXCTest:
            return @"xctest";
        case KSCrashRunSummaryHostKindOther:
        default:
            return @"other";
    }
}

static NSDictionary *buildSummary(const KSCrashRunContext *ctx, const char *userInfoSidecarPath)
{
    if (ctx == NULL || !ctx->systemValid || !ctx->lifecycleValid) {
        return nil;
    }

    const KSCrash_LifecycleData *lc = &ctx->lifecycle;
    const KSCrash_SystemData *sys = &ctx->system;

    // Wall-clock timestamps. `started_at` is the sidecar-creation wall anchor;
    // `ended_at` converts the last-seen monotonic timestamp through the same
    // reference pair, falling back to the start when it can't be computed
    // (corrupt sidecar or a non-positive delta).
    int64_t startedAtMs = (int64_t)(lc->wallClockAtStartNs / 1000000ULL);
    uint64_t endedWallNs = ksdate_monotonicToWallClockNanoseconds(ctx->mostRecentTimestampNs, lc->wallClockAtStartNs,
                                                                  lc->monotonicAtStartNs);
    int64_t endedAtMs = endedWallNs != 0 ? (int64_t)(endedWallNs / 1000000ULL) : startedAtMs;

    // Durations accumulate in the sidecar only on state transitions, so the
    // currently-open slice (from the last transition to "now") is not yet
    // folded in when the process dies without a transition. That's the common
    // path for abnormal terminations (OOM, CPU / thermal kill, reboot,
    // unexplained kill) — no lifecycle or crash callback fires, so without
    // this tail extension a run that spent its whole time foregrounded would
    // summarize as ~0 ms active. Clean shutdown and fatal crashes already
    // close the slice via updateSidecarDurations, so adding the tail here
    // would double-count — except that those paths set appStateTransitionTimeNs
    // forward to the time of closure, making the tail zero by construction.
    uint64_t activeNs = lc->activeDurationSinceLaunchNs;
    uint64_t backgroundNs = lc->backgroundDurationSinceLaunchNs;
    if (ctx->mostRecentTimestampNs > lc->appStateTransitionTimeNs) {
        uint64_t tailNs = ctx->mostRecentTimestampNs - lc->appStateTransitionTimeNs;
        if (lc->applicationIsActive) {
            activeNs += tailNs;
        } else if (!lc->applicationIsInForeground) {
            backgroundNs += tailNs;
        }
    }

    NSString *sdkVersion = [NSString stringWithUTF8String:(const char *)KSCrashFrameworkVersionString] ?: @"";
    NSString *runID = [NSString stringWithUTF8String:ctx->runID] ?: @"";
    NSString *deviceID = safeString(sys->deviceAppHash);
    NSString *userID = readUserIDFromSidecar(userInfoSidecarPath);

    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:14];
    dict[KSCrashRunSummaryField_SchemaVersion] = @1;
    dict[KSCrashRunSummaryField_SDKVersion] = sdkVersion;
    dict[KSCrashRunSummaryField_RunID] = runID;
    dict[KSCrashRunSummaryField_DeviceID] = deviceID;
    if (userID != nil) {
        dict[KSCrashRunSummaryField_UserID] = userID;
    }
    dict[KSCrashRunSummaryField_StartedAtMs] = @(startedAtMs);
    dict[KSCrashRunSummaryField_EndedAtMs] = @(endedAtMs);
    dict[KSCrashRunSummaryField_IsBeingDebugged] = sys->isBeingDebugged != 0 ? @YES : @NO;
    dict[KSCrashRunSummaryField_Outcome] = @{
        KSCrashRunSummaryField_TerminationReason : @(kstermination_reasonToString(ctx->terminationReason)),
        KSCrashRunSummaryField_UserPerceptible : lc->userPerceptible != 0 ? @YES : @NO,
    };
    dict[KSCrashRunSummaryField_DurationsMs] = @{
        KSCrashRunSummaryField_Active : @((int64_t)(activeNs / 1000000ULL)),
        KSCrashRunSummaryField_Background : @((int64_t)(backgroundNs / 1000000ULL)),
    };
    // Records are merged from the run's .sessions file at send time, never on
    // this synchronous startup path; the wire form omits the empty list.
    dict[KSCrashRunSummaryField_Sessions] = @ {};
    NSMutableDictionary *appDict = [NSMutableDictionary dictionary];
    appDict[KSCrashRunSummaryField_BundleID] = safeString(sys->bundleID);
    appDict[KSCrashRunSummaryField_Version] = safeString(sys->bundleVersion);
    appDict[KSCrashRunSummaryField_ShortVersion] = safeString(sys->bundleShortVersion);
    appDict[KSCrashRunSummaryField_HostKind] = hostKindWireString(lc->hostKind);
    // Same producer-side value the reports carry; absent when the sidecar has
    // none rather than an empty string.
    if (sys->buildType[0] != '\0') {
        appDict[KSCrashRunSummaryField_BuildType] = safeString(sys->buildType);
    }
    dict[KSCrashRunSummaryField_App] = appDict;
    dict[KSCrashRunSummaryField_OS] = @ {
        KSCrashRunSummaryField_Name : safeString(sys->systemName),
        KSCrashRunSummaryField_Version : safeString(sys->systemVersion),
        KSCrashRunSummaryField_Build : safeString(sys->osVersion),
    };
    dict[KSCrashRunSummaryField_Device] = @{
        KSCrashRunSummaryField_Model : safeString(sys->machine),
        KSCrashRunSummaryField_ModelFamily : safeString(sys->model),
        KSCrashRunSummaryField_Architecture : safeString(sys->cpuArchitecture),
        KSCrashRunSummaryField_BinaryArchitecture : safeString(sys->binaryArchitecture),
        KSCrashRunSummaryField_IsTranslated : sys->procTranslated != 0 ? @YES : @NO,
        KSCrashRunSummaryField_IsJailbroken : sys->isJailbroken != 0 ? @YES : @NO,
    };
    return dict;
}

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

__attribute__((unused))  // For tests. Declared as extern in TestCase
NSDictionary *
ksruncontext_testcode_buildSummary(const KSCrashRunContext *ctx, const char *userInfoSidecarPath)
{
    return buildSummary(ctx, userInfoSidecarPath);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void ksruncontext_testcode_setCachedSummary(NSDictionary *summary, const char *runID)
{
    g_summary = summary;
    if (runID != NULL) {
        strlcpy(g_context.runID, runID, sizeof(g_context.runID));
    } else {
        g_context.runID[0] = '\0';
    }
}
