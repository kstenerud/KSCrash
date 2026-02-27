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
    static KSCrash_AppState state;
    memset(&state, 0, sizeof(state));

    ks_spinlock_lock(&g_sidecarLock);
    KSCrash_LifecycleData *sc = g_sidecar;
    if (sc != NULL) {
        // Compute up-to-date durations without modifying the sidecar
        uint64_t now = monotonicTimeNs();
        uint64_t elapsed = now - sc->appStateTransitionTimeNs;

        uint64_t activeSinceLaunchNs = sc->activeDurationSinceLaunchNs;
        uint64_t bgSinceLaunchNs = sc->backgroundDurationSinceLaunchNs;
        uint64_t activeSinceCrashNs = sc->activeDurationSinceLastCrashNs;
        uint64_t bgSinceCrashNs = sc->backgroundDurationSinceLastCrashNs;

        if (sc->applicationIsActive) {
            activeSinceLaunchNs += elapsed;
            activeSinceCrashNs += elapsed;
        } else if (!sc->applicationIsInForeground) {
            bgSinceLaunchNs += elapsed;
            bgSinceCrashNs += elapsed;
        }

        state.activeDurationSinceLaunch = nsToSeconds(activeSinceLaunchNs);
        state.backgroundDurationSinceLaunch = nsToSeconds(bgSinceLaunchNs);
        state.activeDurationSinceLastCrash = nsToSeconds(activeSinceCrashNs);
        state.backgroundDurationSinceLastCrash = nsToSeconds(bgSinceCrashNs);
        state.sessionsSinceLaunch = sc->sessionsSinceLaunch;
        state.sessionsSinceLastCrash = sc->sessionsSinceLastCrash;
        state.launchesSinceLastCrash = sc->launchesSinceLastCrash;
        state.crashedLastLaunch = sc->crashedLastLaunch;
        state.applicationIsActive = sc->applicationIsActive;
        state.applicationIsInForeground = sc->applicationIsInForeground;
        state.appStateTransitionTime = nsToSeconds(sc->appStateTransitionTimeNs);
    }
    ks_spinlock_unlock(&g_sidecarLock);

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

static void setEnabled(bool isEnabled, __unused void *context)
{
    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expectEnabled, isEnabled)) {
        return;
    }

    if (isEnabled) {
        // Read previous run's sidecar to determine crashedLastLaunch and carry forward counters
        const char *lastRunID = kscrash_getLastRunID();
        KSCrash_LifecycleData prev = {};
        bool hasPrev = readPreviousSidecar(lastRunID, &prev);

        bool crashedLastLaunch = false;
        uint64_t activeSinceLastCrashNs = 0;
        uint64_t bgSinceLastCrashNs = 0;
        int32_t launchesSinceLastCrash = 0;
        int32_t sessionsSinceLastCrash = 0;

        if (hasPrev) {
            crashedLastLaunch = !prev.cleanShutdown;
            if (crashedLastLaunch) {
                // Previous run crashed: reset cumulative counters
                activeSinceLastCrashNs = 0;
                bgSinceLastCrashNs = 0;
                launchesSinceLastCrash = 0;
                sessionsSinceLastCrash = 0;
            } else {
                // Clean shutdown: carry forward cumulatives + per-launch durations
                activeSinceLastCrashNs = prev.activeDurationSinceLastCrashNs + prev.activeDurationSinceLaunchNs;
                bgSinceLastCrashNs = prev.backgroundDurationSinceLastCrashNs + prev.backgroundDurationSinceLaunchNs;
                launchesSinceLastCrash = prev.launchesSinceLastCrash;
                sessionsSinceLastCrash = prev.sessionsSinceLastCrash;
            }
        }

        // mmap new sidecar for current run
        char sidecarPath[KSFU_MAX_PATH_LENGTH];
        if (!g_callbacks.getRunSidecarPath ||
            !g_callbacks.getRunSidecarPath("Lifecycle", sidecarPath, sizeof(sidecarPath))) {
            KSLOG_ERROR(@"Failed to get run sidecar path for Lifecycle monitor");
            atomic_store(&g_isEnabled, false);
            return;
        }

        void *ptr = ksfu_mmap(sidecarPath, sizeof(KSCrash_LifecycleData));
        if (!ptr) {
            KSLOG_ERROR(@"Failed to mmap lifecycle sidecar at %s", sidecarPath);
            atomic_store(&g_isEnabled, false);
            return;
        }
        KSCrash_LifecycleData *sc = (KSCrash_LifecycleData *)ptr;

        // Populate
        sc->cleanShutdown = false;
        sc->crashedLastLaunch = crashedLastLaunch;
        sc->activeDurationSinceLaunchNs = 0;
        sc->backgroundDurationSinceLaunchNs = 0;
        sc->sessionsSinceLaunch = 1;
        sc->appStateTransitionTimeNs = monotonicTimeNs();
        sc->activeDurationSinceLastCrashNs = activeSinceLastCrashNs;
        sc->backgroundDurationSinceLastCrashNs = bgSinceLastCrashNs;
        sc->launchesSinceLastCrash = launchesSinceLastCrash + 1;
        sc->sessionsSinceLastCrash = sessionsSinceLastCrash + 1;

        // Set initial state from AppStateTracker
        KSCrashAppTransitionState ts = KSCrashAppStateTracker.sharedInstance.transitionState;
        sc->transitionState = (uint8_t)ts;
        sc->applicationIsActive = (ts == KSCrashAppTransitionStateActive);
        sc->applicationIsInForeground = ksapp_transitionStateIsUserPerceptible(ts);

        // Write magic/version last, then publish under spinlock
        sc->magic = KSLIFECYCLE_MAGIC;
        sc->version = KSCrash_Lifecycle_CurrentVersion;

        ks_spinlock_lock(&g_sidecarLock);
        g_sidecar = sc;
        ks_spinlock_unlock(&g_sidecarLock);

        // Subscribe to AppStateTracker
        g_appStateObserver =
            [KSCrashAppStateTracker.sharedInstance addObserverWithBlock:^(KSCrashAppTransitionState transitionState) {
                onTransitionState(transitionState);
            }];
    } else {
        [KSCrashAppStateTracker.sharedInstance removeObserver:g_appStateObserver];
        g_appStateObserver = nil;

        ks_spinlock_lock(&g_sidecarLock);
        KSCrash_LifecycleData *old = g_sidecar;
        g_sidecar = NULL;
        ks_spinlock_unlock(&g_sidecarLock);
        if (old) {
            ksfu_munmap(old, sizeof(KSCrash_LifecycleData));
        }
    }
}

static bool isEnabled_func(__unused void *context) { return g_isEnabled; }

static void addContextualInfoToEvent(__unused KSCrash_MonitorContext *eventContext, __unused void *context)
{
    // Update transition duration in the sidecar. The stitch reads it at delivery time.
    if (!ks_spinlock_lock_bounded(&g_sidecarLock)) {
        return;
    }
    if (g_sidecar != NULL) {
        updateSidecarDurations(g_sidecar);
    }
    ks_spinlock_unlock(&g_sidecarLock);
}

/** Implemented in KSCrashMonitor_LifecycleStitch.m */
extern char *kscm_lifecycle_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope,
                                         void *context);

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
