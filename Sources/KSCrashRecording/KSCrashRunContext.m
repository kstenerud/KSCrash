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
#import "KSCrashRunSummary.h"
#import "KSFileUtils.h"
#import "KSKeyValueStore.h"

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>

#import "KSLogger.h"

// Defined in KSCrash.m. Forward-declared here to avoid importing KSCrash.h.
FOUNDATION_EXPORT const unsigned char KSCrashFrameworkVersionString[];

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static KSCrashRunContext g_context = { 0 };
static KSCrashRunSummary *g_summary = nil;

static KSCrashRunSummary *buildSummary(const KSCrashRunContext *ctx, const char *userInfoSidecarPath);

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

KSCrashRunSummary *ksruncontext_previousRunSummary(void) { return g_summary; }

void ksruncontext_persistPreviousRunSummary(const char *installPath)
{
    if (g_summary == nil || installPath == NULL || installPath[0] == '\0') {
        return;
    }

    char dir[KSFU_MAX_PATH_LENGTH];
    if (snprintf(dir, sizeof(dir), "%s/Runs", installPath) >= (int)sizeof(dir)) {
        KSLOG_ERROR(@"Run summary path too long: %s/Runs", installPath);
        return;
    }
    if (!ksfu_makePath(dir)) {
        KSLOG_ERROR(@"Failed to create run summary dir %s", dir);
        return;
    }

    char path[KSFU_MAX_PATH_LENGTH];
    if (snprintf(path, sizeof(path), "%s/%s.json", dir, g_context.runID) >= (int)sizeof(path)) {
        KSLOG_ERROR(@"Run summary file path too long: %s/%s.json", dir, g_context.runID);
        return;
    }

    NSData *data = [g_summary jsonData];
    if (data == nil) {
        return;  // Error already logged in -jsonData.
    }

    NSError *error = nil;
    NSString *nsPath = [NSString stringWithUTF8String:path];
    if (![data writeToFile:nsPath options:NSDataWritingAtomic error:&error]) {
        KSLOG_ERROR(@"Failed to write run summary to %s: %@", path, error);
    }
}

// ============================================================================
#pragma mark - Build Summary -
// ============================================================================

// Reserved UserInfo key, mirrors the one in -[KSCrash setUserID:].
static const char kUserIDKey[] = "com.kscrash.userid";

typedef struct {
    // Mutable result: the last string value seen for kUserIDKey, or nil if
    // only tombstones / absent. Retained by the iteration callbacks so the
    // outer function takes ownership at the end.
    NSString *userID;
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
    KSKeyValueStore *store = kskvs_create(sidecarPath, KSKVSModeRead, NULL);
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

static KSCrashRunSummaryHostKind hostKindFromCurrentBundle(void)
{
    NSString *ext = [[NSBundle mainBundle] bundlePath].pathExtension.lowercaseString;
    if ([ext isEqualToString:@"app"]) {
        return KSCrashRunSummaryHostKindApp;
    }
    if ([ext isEqualToString:@"appex"]) {
        return KSCrashRunSummaryHostKindExtension;
    }
    if ([ext isEqualToString:@"xctest"]) {
        return KSCrashRunSummaryHostKindXCTest;
    }
    return KSCrashRunSummaryHostKindOther;
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

static KSCrashRunSummary *buildSummary(const KSCrashRunContext *ctx, const char *userInfoSidecarPath)
{
    if (ctx == NULL || !ctx->systemValid || !ctx->lifecycleValid) {
        return nil;
    }

    const KSCrash_LifecycleData *lc = &ctx->lifecycle;
    const KSCrash_SystemData *sys = &ctx->system;

    // Wall-clock timestamps. `started_at` is captured at sidecar creation.
    // `ended_at` = started + (mostRecentMonotonic - monotonicAtStart). If
    // the monotonic delta is non-positive (shouldn't happen, but defend
    // against corrupt sidecars), fall back to the start timestamp.
    int64_t startedAtMs = (int64_t)(lc->wallClockAtStartNs / 1000000ULL);
    int64_t endedAtMs = startedAtMs;
    if (ctx->mostRecentTimestampNs >= lc->monotonicAtStartNs) {
        uint64_t elapsedNs = ctx->mostRecentTimestampNs - lc->monotonicAtStartNs;
        endedAtMs = (int64_t)((lc->wallClockAtStartNs + elapsedNs) / 1000000ULL);
    }

    KSCrashRunSummaryOutcome *outcome =
        [[KSCrashRunSummaryOutcome alloc] initWithTerminationReason:ctx->terminationReason
                                                      cleanShutdown:lc->cleanShutdown != 0
                                                      fatalReported:lc->fatalReported != 0
                                                    userPerceptible:lc->userPerceptible != 0];

    KSCrashRunSummaryDurations *durations = [[KSCrashRunSummaryDurations alloc]
        initWithActiveMs:(int64_t)(lc->activeDurationSinceLaunchNs / 1000000ULL)
            backgroundMs:(int64_t)(lc->backgroundDurationSinceLaunchNs / 1000000ULL)];

    KSCrashRunSummarySessions *sessions =
        [[KSCrashRunSummarySessions alloc] initWithPerceptibleCount:(NSInteger)lc->perceptibleSessionsSinceLaunch
                                                 imperceptibleCount:(NSInteger)lc->imperceptibleSessionsSinceLaunch];

    KSCrashRunSummaryUsers *users =
        [[KSCrashRunSummaryUsers alloc] initWithPerceptibleCount:(NSInteger)lc->distinctPerceptibleUserCount
                                              imperceptibleCount:(NSInteger)lc->distinctImperceptibleUserCount];

    KSCrashRunSummaryApp *app = [[KSCrashRunSummaryApp alloc] initWithBundleID:safeString(sys->bundleID)
                                                                       version:safeString(sys->bundleVersion)
                                                                  shortVersion:safeString(sys->bundleShortVersion)
                                                                      hostKind:hostKindFromCurrentBundle()];

    KSCrashRunSummaryOS *os = [[KSCrashRunSummaryOS alloc] initWithName:safeString(sys->systemName)
                                                                version:safeString(sys->systemVersion)
                                                                  build:safeString(sys->osVersion)];

    KSCrashRunSummaryDevice *device = [[KSCrashRunSummaryDevice alloc] initWithModel:safeString(sys->machine)
                                                                         modelFamily:safeString(sys->model)
                                                                        architecture:safeString(sys->cpuArchitecture)
                                                                  binaryArchitecture:safeString(sys->binaryArchitecture)
                                                                        isTranslated:sys->procTranslated != 0
                                                                        isJailbroken:sys->isJailbroken != 0];

    NSString *sdkVersion = [NSString stringWithUTF8String:(const char *)KSCrashFrameworkVersionString] ?: @"";
    NSString *runID = [NSString stringWithUTF8String:ctx->runID] ?: @"";
    NSString *deviceID = safeString(sys->deviceAppHash);
    NSString *userID = readUserIDFromSidecar(userInfoSidecarPath);

    return [[KSCrashRunSummary alloc] initWithSchemaVersion:1
                                                 sdkVersion:sdkVersion
                                                      runID:runID
                                                   deviceID:deviceID
                                                     userID:userID
                                                      users:users
                                                startedAtMs:startedAtMs
                                                  endedAtMs:endedAtMs
                                                    outcome:outcome
                                                  durations:durations
                                                   sessions:sessions
                                                        app:app
                                                         os:os
                                                     device:device];
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
KSCrashRunSummary *
ksruncontext_testcode_buildSummary(const KSCrashRunContext *ctx, const char *userInfoSidecarPath)
{
    return buildSummary(ctx, userInfoSidecarPath);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void ksruncontext_testcode_setCachedSummary(KSCrashRunSummary *summary, const char *runID)
{
    g_summary = summary;
    if (runID != NULL) {
        strlcpy(g_context.runID, runID, sizeof(g_context.runID));
    } else {
        g_context.runID[0] = '\0';
    }
}
