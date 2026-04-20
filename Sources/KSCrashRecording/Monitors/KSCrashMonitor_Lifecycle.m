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
#import "KSCrashRunContext.h"
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
#import <os/lock.h>
#import <stdatomic.h>
#import <string.h>
#import <sys/stat.h>
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
static _Atomic KSCrashAppTransitionState g_transitionState = KSCrashAppTransitionStateStartup;

// In-memory state for the distinct-user tracking. Not persisted (only the
// counts in the sidecar are). `g_userLock` guards all three variables.
static os_unfair_lock g_userLock = OS_UNFAIR_LOCK_INIT;
static NSMutableSet<NSString *> *g_perceptibleUsers = nil;
static NSMutableSet<NSString *> *g_imperceptibleUsers = nil;
static NSString *g_currentUserID = nil;

/** Write the current task role to the sidecar if it changed.
 *  Call under the sidecar lock.
 */
static void updateSidecarTaskRole(KSCrash_LifecycleData *sc)
{
    int32_t role = (int32_t)kstaskrole_current();
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

// ============================================================================
#pragma mark - Distinct user tracking -
// ============================================================================
//
// The two sets and g_currentUserID are guarded by g_userLock. The sidecar's
// distinct-count fields are guarded by g_sidecarLock. These locks are never
// held together: each call site updates the in-memory state first, grabs
// the new count, then writes it into the sidecar in a separate critical
// section.

/** Write a user bucket's count into the sidecar. Grabs g_sidecarLock. */
static void writeDistinctUserCountToSidecar(bool perceptible, NSUInteger count)
{
    ks_spinlock_lock(&g_sidecarLock);
    KSCrash_LifecycleData *sc = g_sidecar;
    if (sc != NULL) {
        if (perceptible) {
            sc->distinctPerceptibleUserCount = (uint32_t)count;
        } else {
            sc->distinctImperceptibleUserCount = (uint32_t)count;
        }
    }
    ks_spinlock_unlock(&g_sidecarLock);
}

/** Record `userID` in the bucket for `perceptible`. Return the new bucket
 *  size, or 0 if there was nothing to record. Grabs g_userLock.
 */
static NSUInteger recordUserInBucket(NSString *userID, bool perceptible)
{
    if (userID.length == 0) {
        return 0;
    }
    NSUInteger count = 0;
    os_unfair_lock_lock(&g_userLock);
    if (perceptible) {
        if (g_perceptibleUsers == nil) g_perceptibleUsers = [NSMutableSet set];
        [g_perceptibleUsers addObject:userID];
        count = g_perceptibleUsers.count;
    } else {
        if (g_imperceptibleUsers == nil) g_imperceptibleUsers = [NSMutableSet set];
        [g_imperceptibleUsers addObject:userID];
        count = g_imperceptibleUsers.count;
    }
    os_unfair_lock_unlock(&g_userLock);
    return count;
}

void kscm_lifecycle_observeUser(const char *userID)
{
    NSString *asString = (userID != NULL && userID[0] != '\0') ? [NSString stringWithUTF8String:userID] : nil;

    os_unfair_lock_lock(&g_userLock);
    g_currentUserID = [asString copy];
    os_unfair_lock_unlock(&g_userLock);

    if (asString.length == 0) {
        return;  // nothing to count
    }

    // Read perceptibility from the sidecar. createSidecar() populates this
    // on install from the current app state, so it's accurate before any
    // transition has fired (unlike the atomic g_transitionState which
    // starts at Startup).
    bool perceptible = false;
    ks_spinlock_lock(&g_sidecarLock);
    bool haveSidecar = g_sidecar != NULL;
    if (haveSidecar) {
        perceptible = g_sidecar->userPerceptible != 0;
    }
    ks_spinlock_unlock(&g_sidecarLock);
    if (!haveSidecar) {
        return;  // pre-install no-op
    }

    NSUInteger count = recordUserInBucket(asString, perceptible);
    if (count > 0) {
        writeDistinctUserCountToSidecar(perceptible, count);
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

    // Tolerate short reads: older sidecars were smaller than the current
    // struct. Fields beyond the file are left zero-filled, which is the
    // correct default for any forward-compatible addition (see header:
    // new fields must only be appended, never reordered).
    struct stat st;
    if (fstat(fd, &st) != 0) {
        close(fd);
        return false;
    }
    size_t bytesToRead = (size_t)st.st_size < sizeof(*out) ? (size_t)st.st_size : sizeof(*out);
    bool ok = (bytesToRead > 0) && ksfu_readBytesFromFD(fd, (char *)out, (int)bytesToRead);
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
    atomic_store_explicit(&g_transitionState, transitionState, memory_order_relaxed);

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
            // Returning to foreground: accumulate background duration, increment sessions.
            // Foregrounding is perceptible by definition, so this bumps the
            // perceptible counter. `sessionsSinceLaunch` is kept as the sum so
            // existing readers see the same monotonically-increasing total.
            updateSidecarDurations(sc);
            sc->applicationIsInForeground = true;
            sc->perceptibleSessionsSinceLaunch++;
            sc->sessionsSinceLaunch =
                (int32_t)(sc->perceptibleSessionsSinceLaunch + sc->imperceptibleSessionsSinceLaunch);
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

    bool previousPerceptible = sc->userPerceptible != 0;
    bool newPerceptible = ksapp_transitionStateIsUserPerceptible(transitionState);
    sc->transitionState = (uint8_t)transitionState;
    sc->userPerceptible = newPerceptible;
    updateSidecarTaskRole(sc);
    ks_spinlock_unlock(&g_sidecarLock);

    // Perceptibility flipped: the current user (if any) is now in a new
    // bucket. Recording happens after the sidecar lock is released so the
    // two locks never nest.
    if (newPerceptible != previousPerceptible) {
        os_unfair_lock_lock(&g_userLock);
        NSString *user = g_currentUserID;
        os_unfair_lock_unlock(&g_userLock);
        NSUInteger count = recordUserInBucket(user, newPerceptible);
        if (count > 0) {
            writeDistinctUserCountToSidecar(newPerceptible, count);
        }
    }
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

KSCrashAppTransitionState kslifecycle_currentTransitionState(void)
{
    return atomic_load_explicit(&g_transitionState, memory_order_relaxed);
}

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

static const char *monitorId(__unused void *context) { return "Lifecycle"; }

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    g_callbacks = *callbacks;
}

/** Carry forward cumulative counters from the previous run's lifecycle.
 *
 *  Called from notifyPostSystemEnable. RunContext has already computed whether
 *  the previous run produced a report. Counters are preserved when no report
 *  was produced (clean shutdown, reboot, OS/app upgrade). */
static void carryForwardFromPreviousRun(void)
{
    KSCrash_LifecycleData *sc = g_sidecar;
    if (sc == NULL) {
        return;
    }

    const KSCrashRunContext *ctx = ksruncontext_previousRunContext();
    if (!ctx->lifecycleValid) {
        return;
    }

    // Use += because the current launch's increments have already been applied
    // to the sidecar during createSidecar().
    if (!ctx->producedReport) {
        sc->activeDurationSinceLastCrashNs += ctx->lifecycle.activeDurationSinceLastCrashNs;
        sc->backgroundDurationSinceLastCrashNs += ctx->lifecycle.backgroundDurationSinceLastCrashNs;
        sc->launchesSinceLastCrash += ctx->lifecycle.launchesSinceLastCrash;
        sc->sessionsSinceLastCrash += ctx->lifecycle.sessionsSinceLastCrash;
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

    // The initial launch is one session. Attribute it to perceptible or
    // imperceptible based on whether the user can see the app at this moment.
    // `sessionsSinceLaunch` is kept as the sum so existing readers are unaffected.
    if (sc->userPerceptible) {
        sc->perceptibleSessionsSinceLaunch = 1;
    } else {
        sc->imperceptibleSessionsSinceLaunch = 1;
    }
    sc->sessionsSinceLaunch = (int32_t)(sc->perceptibleSessionsSinceLaunch + sc->imperceptibleSessionsSinceLaunch);

    sc->taskRole = (int32_t)kstaskrole_current();
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

        os_unfair_lock_lock(&g_userLock);
        g_perceptibleUsers = nil;
        g_imperceptibleUsers = nil;
        g_currentUserID = nil;
        os_unfair_lock_unlock(&g_userLock);

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
        api.createStitchedReport = kscm_lifecycle_createStitchedReport;
    }
    return &api;
}
