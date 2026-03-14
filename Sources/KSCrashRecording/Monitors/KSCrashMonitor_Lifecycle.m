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
#import "KSCrashHang.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitorHelper.h"
#import "KSCrashMonitor_Termination.h"
#import "KSDate.h"
#import "KSFileUtils.h"
#import "KSSpinLock.h"
#import "KSSystemCapabilities.h"

// #define KSLogger_LocalLevel TRACE
#import <dispatch/dispatch.h>
#import <errno.h>
#import <fcntl.h>
#import <mach/mach.h>
#import <mach/task_policy.h>
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
static id g_appStateObserver = nil;
static KSHangObserverToken g_hangObserverToken = KSHangObserverTokenNotFound;
static dispatch_source_t g_taskRoleHeartbeatTimer = NULL;

static atomic_bool g_isEnabled = false;

// ============================================================================
#pragma mark - Utility -
// ============================================================================

int kslifecycle_currentTaskRole(void)
{
#if KSCRASH_HOST_TV || KSCRASH_HOST_WATCH
    return TASK_UNSPECIFIED;
#else
    task_category_policy_data_t policy;
    mach_msg_type_number_t count = TASK_CATEGORY_POLICY_COUNT;
    boolean_t getDefault = false;

    kern_return_t kr =
        task_policy_get(mach_task_self(), TASK_CATEGORY_POLICY, (task_policy_t)&policy, &count, &getDefault);

    return kr == KERN_SUCCESS ? policy.role : TASK_UNSPECIFIED;
#endif
}

const char *kslifecycle_stringFromTaskRole(int role)
{
    switch (role) {
        case TASK_RENICED:
            return "RENICED";
        case TASK_UNSPECIFIED:
            return "UNSPECIFIED";
        case TASK_FOREGROUND_APPLICATION:
            return "FOREGROUND_APPLICATION";
        case TASK_BACKGROUND_APPLICATION:
            return "BACKGROUND_APPLICATION";
        case TASK_CONTROL_APPLICATION:
            return "CONTROL_APPLICATION";
        case TASK_GRAPHICS_SERVER:
            return "GRAPHICS_SERVER";
        case TASK_THROTTLE_APPLICATION:
            return "THROTTLE_APPLICATION";
        case TASK_NONUI_APPLICATION:
            return "NONUI_APPLICATION";
        case TASK_DEFAULT_APPLICATION:
            return "DEFAULT_APPLICATION";
#if defined(TASK_DARWINBG_APPLICATION)
        case TASK_DARWINBG_APPLICATION:
            return "DARWINBG_APPLICATION";
#endif
#if defined(TASK_USER_INIT_APPLICATION)
        case TASK_USER_INIT_APPLICATION:
            return "USER_INIT_APPLICATION";
#endif
        default:
            return "UNKNOWN";
    }
}

/** Write the current task role to the sidecar if it changed.
 *  Call under the sidecar lock.
 */
static void updateSidecarTaskRole(KSCrash_LifecycleData *sc)
{
    int32_t role = (int32_t)kslifecycle_currentTaskRole();
    if (sc->taskRole != role) {
        sc->taskRole = role;
    }
}

// ============================================================================
#pragma mark - Task Role Heartbeat -
// ============================================================================

static void startTaskRoleHeartbeat(void)
{
#ifdef KSCRASH_NAMESPACE
    const char *label = "com.kscrash." KSCRASH_NAMESPACE_STRING ".lifecycle.heartbeat";
#else
    const char *label = "com.kscrash.lifecycle.heartbeat";
#endif
    dispatch_queue_t queue = dispatch_queue_create_with_target(label, DISPATCH_QUEUE_SERIAL,
                                                               dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    g_taskRoleHeartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(g_taskRoleHeartbeatTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                              1 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(g_taskRoleHeartbeatTimer, ^{
        if (!atomic_load(&g_isEnabled)) return;
        ks_spinlock_lock(&g_sidecarLock);
        KSCrash_LifecycleData *sc = g_sidecar;
        if (sc != NULL) {
            updateSidecarTaskRole(sc);
        }
        ks_spinlock_unlock(&g_sidecarLock);
    });
    dispatch_resume(g_taskRoleHeartbeatTimer);
}

static void stopTaskRoleHeartbeat(void)
{
    if (g_taskRoleHeartbeatTimer) {
        dispatch_source_cancel(g_taskRoleHeartbeatTimer);
        g_taskRoleHeartbeatTimer = NULL;
    }
}

// ============================================================================
#pragma mark - Utility -
// ============================================================================

/** Update the sidecar's transition duration for the current state.
 *  Call under the sidecar lock or when single-threaded.
 */
static void updateSidecarDurations(KSCrash_LifecycleData *sc)
{
    uint64_t now = ksdate_continuousNanoseconds();
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

bool kslifecycle_readData(const char *path, KSCrash_LifecycleData *out)
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

    if (!ok || out->magic != KSLIFECYCLE_MAGIC || out->version == 0 ||
        out->version > KSCrash_Lifecycle_CurrentVersion) {
        return false;
    }
    return true;
}

bool kslifecycle_getSnapshotForRunID(const char *runID, KSCrash_LifecycleData *outData)
{
    if (!runID || !outData || runID[0] == '\0') {
        return false;
    }
    if (!g_callbacks.getRunSidecarPathForRunID) {
        return false;
    }

    char sidecarPath[KSFU_MAX_PATH_LENGTH];
    if (!g_callbacks.getRunSidecarPathForRunID("Lifecycle", runID, sidecarPath, sizeof(sidecarPath))) {
        return false;
    }

    return kslifecycle_readData(sidecarPath, outData);
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
    sc->userPerceptible = ksapp_transitionStateIsUserPerceptible(transitionState);
    updateSidecarTaskRole(sc);
    ks_spinlock_unlock(&g_sidecarLock);
}

// ============================================================================
#pragma mark - kscrashstate_currentState -
// ============================================================================

KSCrash_AppState kscrashstate_lifecycleAppState(void)
{
    KSCrash_AppState state = { 0 };

    ks_spinlock_lock(&g_sidecarLock);
    KSCrash_LifecycleData *sc = g_sidecar;
    KSCrash_LifecycleData snapshot;
    bool hasData = (sc != NULL);
    if (hasData) {
        snapshot = *sc;
    }
    ks_spinlock_unlock(&g_sidecarLock);

    if (hasData) {
        uint64_t now = ksdate_continuousNanoseconds();
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

        state.activeDurationSinceLaunch = kslifecycle_nsToSeconds(activeSinceLaunchNs);
        state.backgroundDurationSinceLaunch = kslifecycle_nsToSeconds(bgSinceLaunchNs);
        state.activeDurationSinceLastCrash = kslifecycle_nsToSeconds(activeSinceCrashNs);
        state.backgroundDurationSinceLastCrash = kslifecycle_nsToSeconds(bgSinceCrashNs);
        state.sessionsSinceLaunch = snapshot.sessionsSinceLaunch;
        state.sessionsSinceLastCrash = snapshot.sessionsSinceLastCrash;
        state.launchesSinceLastCrash = snapshot.launchesSinceLastCrash;
        state.applicationIsActive = snapshot.applicationIsActive;
        state.applicationIsInForeground = snapshot.applicationIsInForeground;
        state.appStateTransitionTime = kslifecycle_nsToSeconds(snapshot.appStateTransitionTimeNs);
    }

    return state;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
const KSCrash_AppState *kscrashstate_currentState(void)
{
    static _Thread_local KSCrash_AppState state;
    state = kscrashstate_lifecycleAppState();
    return &state;
}
#pragma clang diagnostic pop

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

static const char *monitorId(__unused void *context) { return "Lifecycle"; }

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    g_callbacks = *callbacks;
}

/** Carry forward cumulative counters from the previous run's sidecar.
 *
 *  Called from notifyPostSystemEnable so that the Termination monitor has
 *  already determined its reason. Counters are preserved when the previous
 *  run did not produce a crash report (clean shutdown, reboot, OS/app upgrade). */
static void carryForwardFromPreviousRun(void)
{
    KSCrash_LifecycleData *sc = g_sidecar;
    if (sc == NULL) {
        return;
    }

    const char *lastRunID = kscrash_getLastRunID();
    KSCrash_LifecycleData prev = {};
    if (!kslifecycle_getSnapshotForRunID(lastRunID, &prev)) {
        return;
    }

    // The Termination monitor has already run by notifyPostSystemEnable time.
    // Carry forward when the previous run did NOT produce a report — i.e., it
    // was not a crash, hang, resource kill, or unexplained termination.
    // Use += because the current launch's increments have already been applied
    // to the sidecar during createSidecar().
    KSTerminationReason reason = kstermination_getReason();
    if (!kstermination_producesReport(reason)) {
        sc->activeDurationSinceLastCrashNs += prev.activeDurationSinceLastCrashNs;
        sc->backgroundDurationSinceLastCrashNs += prev.backgroundDurationSinceLastCrashNs;
        sc->launchesSinceLastCrash += prev.launchesSinceLastCrash;
        sc->sessionsSinceLastCrash += prev.sessionsSinceLastCrash;
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
    sc->monotonicAtStartNs = ksdate_continuousNanoseconds();
    sc->wallClockAtStartNs = ksdate_wallClockNanoseconds();
    sc->appStateTransitionTimeNs = sc->monotonicAtStartNs;

    // Counter carry-forward is deferred to notifyPostSystemEnable so the
    // Termination monitor has already determined its reason by that point.

    sc->launchesSinceLastCrash++;
    sc->sessionsSinceLastCrash++;

    KSCrashAppTransitionState ts = KSCrashAppStateTracker.sharedInstance.transitionState;
    sc->transitionState = (uint8_t)ts;
    sc->applicationIsActive = (ts == KSCrashAppTransitionStateActive);
    // Foreground means the app has actually entered the foreground (Active,
    // Deactivating, Foregrounding).  Startup/Launching are pre-foreground and
    // must not be counted — userPerceptible is intentionally broader.
    sc->applicationIsInForeground =
        (ts == KSCrashAppTransitionStateActive || ts == KSCrashAppTransitionStateDeactivating ||
         ts == KSCrashAppTransitionStateForegrounding);
    sc->userPerceptible = ksapp_transitionStateIsUserPerceptible(ts);

    sc->taskRole = (int32_t)kslifecycle_currentTaskRole();
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

static void onHangChange(KSHangChangeType change, __unused uint64_t startTimestamp, __unused uint64_t endTimestamp,
                         __unused void *context)
{
    if (change != KSHangChangeTypeStarted && change != KSHangChangeTypeEnded) {
        return;
    }
    ks_spinlock_lock(&g_sidecarLock);
    KSCrash_LifecycleData *sc = g_sidecar;
    if (sc != NULL) {
        sc->hangInProgress = (change == KSHangChangeTypeStarted);
    }
    ks_spinlock_unlock(&g_sidecarLock);
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

        startTaskRoleHeartbeat();

    } else {
        stopTaskRoleHeartbeat();

        if (g_hangObserverToken != KSHangObserverTokenNotFound) {
            kshang_removeHangObserver(g_hangObserverToken);
            g_hangObserverToken = KSHangObserverTokenNotFound;
        }

        g_appStateObserver = nil;

        releaseSidecar();
    }
}

static bool isEnabled_func(__unused void *context) { return g_isEnabled; }

// Runs after all monitors have been enabled. The Termination monitor has
// already determined its reason, so we can now carry forward counters.
// Also registers the hang observer (Watchdog didn't exist during setEnabled).
static void notifyPostSystemEnable(__unused void *context)
{
    carryForwardFromPreviousRun();

    if (g_hangObserverToken != KSHangObserverTokenNotFound) {
        return;
    }
    g_hangObserverToken = kshang_addHangObserver(onHangChange, NULL);
}

static void addContextualInfoToEvent(KSCrash_MonitorContext *eventContext, __unused void *context)
{
    bool isFatal = eventContext != NULL && eventContext->requirements.isFatal;
    // For fatal events, write cleanShutdown and fatalReported before acquiring the
    // lock. These are small stores to mmap'd memory that must succeed unconditionally
    // — if the bounded lock times out we still need the next launch to see the correct
    // state. In practice, fatal events run with other threads suspended so lock
    // contention is unlikely, but this is defense-in-depth.
    if (isFatal && g_sidecar != NULL) {
        g_sidecar->cleanShutdown = eventContext->requirements.isCleanExit;
        g_sidecar->fatalReported = true;
    }
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

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionState state)
{
    onTransitionState(state);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscm_lifecycle_testcode_hangChange(KSHangChangeType change)
{
    onHangChange(change, 0, 0, NULL);
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
void kscm_lifecycle_testcode_setTaskRole(int32_t role)
{
    ks_spinlock_lock(&g_sidecarLock);
    if (g_sidecar != NULL) {
        g_sidecar->taskRole = role;
    }
    ks_spinlock_unlock(&g_sidecarLock);
}

KSCrashMonitorAPI *kscm_lifecycle_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = monitorInit;
        api.monitorId = monitorId;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled_func;
        api.notifyPostSystemEnable = notifyPostSystemEnable;
        api.addContextualInfoToEvent = addContextualInfoToEvent;
        api.stitchReport = kscm_lifecycle_stitchReport;
    }
    return &api;
}
