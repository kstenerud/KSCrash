//
//  KSCrashMonitor_Lifecycle.m
//
//  Created by Karl Stenerud on 2012-02-05.
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

#import "KSCrashAppStateTracker.h"
#import "KSCrashC.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitorHelper.h"
#import "KSFileUtils.h"
#import "KSSpinLock.h"

// #define KSLogger_LocalLevel TRACE
#import <errno.h>
#import <fcntl.h>
#import <stdatomic.h>
#import <string.h>
#import <time.h>
#import <unistd.h>

#import "KSLogger.h"

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static KSCrash_LifecycleData *g_sidecar = NULL;
static KSSpinLock g_sidecarLock = KSSPINLOCK_INIT;
static KSCrash_ExceptionHandlerCallbacks g_callbacks = { 0 };
static id<KSCrashAppStateTrackerObserving> g_appStateObserver = nil;

static atomic_bool g_isEnabled = false;

// ============================================================================
#pragma mark - Utility -
// ============================================================================

static uint64_t monotonicTimeNs(void) { return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW); }

static double nsToSeconds(uint64_t ns) { return (double)ns / 1000000000.0; }

/** Update the sidecar's transition duration for the current state.
 *  Call under the sidecar lock or when single-threaded.
 */
static void updateSidecarDurations(KSCrash_LifecycleData *sc)
{
    uint64_t now = monotonicTimeNs();
    uint64_t elapsed = now - sc->appStateTransitionTimeNs;
    sc->appStateTransitionTimeNs = now;

    if (sc->applicationIsActive) {
        sc->activeDurationSinceLaunchNs += elapsed;
        sc->activeDurationSinceLastCrashNs += elapsed;
    } else if (!sc->applicationIsInForeground) {
        sc->backgroundDurationSinceLaunchNs += elapsed;
        sc->backgroundDurationSinceLastCrashNs += elapsed;
    }
}

/** Read a previous run's sidecar from disk into a stack-allocated struct.
 *  Returns true if the struct was successfully read and validated.
 */
static bool readPreviousSidecar(const char *lastRunID, KSCrash_LifecycleData *out)
{
    if (lastRunID == NULL || lastRunID[0] == '\0') {
        return false;
    }

    char sidecarPath[KSFU_MAX_PATH_LENGTH];
    if (!g_callbacks.getRunSidecarPathForRunID ||
        !g_callbacks.getRunSidecarPathForRunID("Lifecycle", lastRunID, sidecarPath, sizeof(sidecarPath))) {
        return false;
    }

    int fd = open(sidecarPath, O_RDONLY);
    if (fd == -1) {
        KSLOG_DEBUG(@"No previous lifecycle sidecar at %s (expected on first run)", sidecarPath);
        return false;
    }

    memset(out, 0, sizeof(*out));
    bool ok = ksfu_readBytesFromFD(fd, (char *)out, (int)sizeof(*out));
    close(fd);

    if (!ok || out->magic != KSLIFECYCLE_MAGIC || out->version == 0 ||
        out->version > KSCrash_Lifecycle_CurrentVersion) {
        KSLOG_ERROR(@"Invalid previous lifecycle sidecar at %s", sidecarPath);
        return false;
    }
    return true;
}

// ============================================================================
#pragma mark - State Transition Observer -
// ============================================================================

static void onTransitionState(KSCrashAppTransitionState transitionState)
{
    ks_spinlock_lock(&g_sidecarLock);
    KSCrash_LifecycleData *sc = g_sidecar;
    if (sc == NULL) {
        ks_spinlock_unlock(&g_sidecarLock);
        return;
    }

    switch (transitionState) {
        case KSCrashAppTransitionStateActive:
            // Becoming active: reset transition timer, mark active
            updateSidecarDurations(sc);
            sc->applicationIsActive = true;
            break;

        case KSCrashAppTransitionStateDeactivating:
            // Resigning active: accumulate active duration
            updateSidecarDurations(sc);
            sc->applicationIsActive = false;
            break;

        case KSCrashAppTransitionStateBackground:
            // Entering background: reset transition timer, mark not foreground
            updateSidecarDurations(sc);
            sc->applicationIsInForeground = false;
            break;

        case KSCrashAppTransitionStateForegrounding:
            // Returning to foreground: accumulate background duration, increment sessions
            updateSidecarDurations(sc);
            sc->applicationIsInForeground = true;
            sc->sessionsSinceLaunch++;
            sc->sessionsSinceLastCrash++;
            break;

        case KSCrashAppTransitionStateTerminating:
        case KSCrashAppTransitionStateExiting:
            // Clean shutdown path
            updateSidecarDurations(sc);
            sc->cleanShutdown = true;
            break;

        default:
            // Startup, Launching, StartupPrewarm — just record state
            break;
    }

    sc->transitionState = (uint8_t)transitionState;
    ks_spinlock_unlock(&g_sidecarLock);
}

// ============================================================================
#pragma mark - kscrashstate_currentState -
// ============================================================================

const KSCrash_AppState *kscrashstate_currentState(void)
{
    static _Thread_local KSCrash_AppState state;
    memset(&state, 0, sizeof(state));

    ks_spinlock_lock(&g_sidecarLock);
    KSCrash_LifecycleData *sc = g_sidecar;
    KSCrash_LifecycleData snapshot;
    bool hasData = (sc != NULL);
    if (hasData) {
        snapshot = *sc;
    }
    ks_spinlock_unlock(&g_sidecarLock);

    if (hasData) {
        uint64_t now = monotonicTimeNs();
        uint64_t elapsed = now - snapshot.appStateTransitionTimeNs;

        uint64_t activeSinceLaunchNs = snapshot.activeDurationSinceLaunchNs;
        uint64_t bgSinceLaunchNs = snapshot.backgroundDurationSinceLaunchNs;
        uint64_t activeSinceCrashNs = snapshot.activeDurationSinceLastCrashNs;
        uint64_t bgSinceCrashNs = snapshot.backgroundDurationSinceLastCrashNs;

        if (snapshot.applicationIsActive) {
            activeSinceLaunchNs += elapsed;
            activeSinceCrashNs += elapsed;
        } else if (!snapshot.applicationIsInForeground) {
            bgSinceLaunchNs += elapsed;
            bgSinceCrashNs += elapsed;
        }

        state.activeDurationSinceLaunch = nsToSeconds(activeSinceLaunchNs);
        state.backgroundDurationSinceLaunch = nsToSeconds(bgSinceLaunchNs);
        state.activeDurationSinceLastCrash = nsToSeconds(activeSinceCrashNs);
        state.backgroundDurationSinceLastCrash = nsToSeconds(bgSinceCrashNs);
        state.sessionsSinceLaunch = snapshot.sessionsSinceLaunch;
        state.sessionsSinceLastCrash = snapshot.sessionsSinceLastCrash;
        state.launchesSinceLastCrash = snapshot.launchesSinceLastCrash;
        state.crashedLastLaunch = snapshot.crashedLastLaunch;
        state.applicationIsActive = snapshot.applicationIsActive;
        state.applicationIsInForeground = snapshot.applicationIsInForeground;
        state.appStateTransitionTime = nsToSeconds(snapshot.appStateTransitionTimeNs);
    }

    return &state;
}

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

static const char *monitorId(__unused void *context) { return "Lifecycle"; }

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    g_callbacks = *callbacks;
}

/** Carry forward cumulative counters from the previous run's sidecar into the new one. */
static void carryForwardFromPreviousRun(KSCrash_LifecycleData *sc)
{
    const char *lastRunID = kscrash_getLastRunID();
    KSCrash_LifecycleData prev = {};
    if (!readPreviousSidecar(lastRunID, &prev)) {
        return;
    }

    sc->crashedLastLaunch = !prev.cleanShutdown;
    if (!sc->crashedLastLaunch) {
        // sinceLastCrashNs already includes the previous run's per-launch durations
        // (updateSidecarDurations adds elapsed to both fields), so just carry it forward.
        sc->activeDurationSinceLastCrashNs = prev.activeDurationSinceLastCrashNs;
        sc->backgroundDurationSinceLastCrashNs = prev.backgroundDurationSinceLastCrashNs;
        sc->launchesSinceLastCrash = prev.launchesSinceLastCrash;
        sc->sessionsSinceLastCrash = prev.sessionsSinceLastCrash;
    }
}

/** Create and initialize the mmap'd sidecar for the current run. Returns NULL on failure. */
static KSCrash_LifecycleData *createSidecar(void)
{
    char sidecarPath[KSFU_MAX_PATH_LENGTH];
    if (!g_callbacks.getRunSidecarPath ||
        !g_callbacks.getRunSidecarPath("Lifecycle", sidecarPath, sizeof(sidecarPath))) {
        KSLOG_ERROR(@"Failed to get run sidecar path for Lifecycle monitor");
        return NULL;
    }

    void *ptr = ksfu_mmap(sidecarPath, sizeof(KSCrash_LifecycleData));
    if (!ptr) {
        KSLOG_ERROR(@"Failed to mmap lifecycle sidecar at %s", sidecarPath);
        return NULL;
    }

    KSCrash_LifecycleData *sc = (KSCrash_LifecycleData *)ptr;
    sc->sessionsSinceLaunch = 1;
    sc->appStateTransitionTimeNs = monotonicTimeNs();

    carryForwardFromPreviousRun(sc);

    sc->launchesSinceLastCrash++;
    sc->sessionsSinceLastCrash++;

    KSCrashAppTransitionState ts = KSCrashAppStateTracker.sharedInstance.transitionState;
    sc->transitionState = (uint8_t)ts;
    sc->applicationIsActive = (ts == KSCrashAppTransitionStateActive);
    sc->applicationIsInForeground = ksapp_transitionStateIsUserPerceptible(ts);

    sc->magic = KSLIFECYCLE_MAGIC;
    sc->version = KSCrash_Lifecycle_CurrentVersion;
    return sc;
}

static void releaseSidecar(void)
{
    ks_spinlock_lock(&g_sidecarLock);
    KSCrash_LifecycleData *old = g_sidecar;
    g_sidecar = NULL;
    ks_spinlock_unlock(&g_sidecarLock);

    if (old) {
        ksfu_munmap(old, sizeof(KSCrash_LifecycleData));
    }
}

static void setEnabled(bool isEnabled, __unused void *context)
{
    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expectEnabled, isEnabled)) {
        return;
    }

    if (isEnabled) {
        KSCrash_LifecycleData *sc = createSidecar();
        if (!sc) {
            atomic_store(&g_isEnabled, false);
            return;
        }

        ks_spinlock_lock(&g_sidecarLock);
        g_sidecar = sc;
        ks_spinlock_unlock(&g_sidecarLock);

        g_appStateObserver =
            [KSCrashAppStateTracker.sharedInstance addObserverWithBlock:^(KSCrashAppTransitionState transitionState) {
                onTransitionState(transitionState);
            }];
    } else {
        [KSCrashAppStateTracker.sharedInstance removeObserver:g_appStateObserver];
        g_appStateObserver = nil;

        releaseSidecar();
    }
}

static bool isEnabled_func(__unused void *context) { return g_isEnabled; }

static void addContextualInfoToEvent(KSCrash_MonitorContext *eventContext, __unused void *context)
{
    if (!ks_spinlock_lock_bounded(&g_sidecarLock)) {
        return;
    }
    if (g_sidecar != NULL) {
        updateSidecarDurations(g_sidecar);
        // A fatal crash overrides any prior clean-shutdown signal (e.g., crash during termination handlers).
        if (eventContext->requirements.isFatal) {
            g_sidecar->cleanShutdown = false;
        }
    }
    ks_spinlock_unlock(&g_sidecarLock);
}

/** Implemented in KSCrashMonitor_LifecycleStitch.m */
extern char *kscm_lifecycle_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope,
                                         void *context);

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionState state)
{
    onTransitionState(state);
}

KSCrashMonitorAPI *kscm_lifecycle_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = monitorInit;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled_func;
        api.addContextualInfoToEvent = addContextualInfoToEvent;
        api.stitchReport = kscm_lifecycle_stitchReport;
    }
    return &api;
}
