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
#import "KSCrashRunSummary.h"
#import "KSCrashSessionLog.h"
#import "KSDate.h"
#import "KSFileUtils.h"
#import "KSID.h"
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
// The run's per-event session log. Pointer read/written under g_sidecarLock;
// the log object has its own lock for writes. Only observeUser and
// onTransitionState touch it, and the SessionLog itself refuses a USER when
// no session is open, so we don't need cross-object write ordering here.
static KSCrashSessionLog *g_sessionLog = nil;
static KSCrash_ExceptionHandlerCallbacks g_callbacks = { 0 };
static id g_appStateObserver = nil;
static KSHangObserverToken g_hangObserverToken = KSHangObserverTokenNotFound;
static dispatch_source_t g_taskRoleHeartbeatTimer = NULL;

static atomic_bool g_isEnabled = false;
static _Atomic KSCrashAppTransitionState g_transitionState = KSCrashAppTransitionStateStartup;

// Tri-state perceptibility of an app transition state, internal to session
// counting. Yes: user-perceptible. No: not. Maybe: launch states where it is
// not yet known whether the app will reach the foreground.
typedef enum {
    KSCrashLifecyclePerceptibilityNo = 0,
    KSCrashLifecyclePerceptibilityYes,
    KSCrashLifecyclePerceptibilityMaybe,
} KSCrashLifecyclePerceptibility;

static KSCrashLifecyclePerceptibility perceptibilityForState(KSCrashAppTransitionState state)
{
    switch (state) {
        case KSCrashAppTransitionStateActive:
        case KSCrashAppTransitionStateDeactivating:
        case KSCrashAppTransitionStateForegrounding:
            return KSCrashLifecyclePerceptibilityYes;
        case KSCrashAppTransitionStateStartup:
        case KSCrashAppTransitionStateLaunching:
            return KSCrashLifecyclePerceptibilityMaybe;
        default:
            return KSCrashLifecyclePerceptibilityNo;
    }
}

// Maps the currently-running bundle to the matching host kind enum. Called
// once at sidecar creation — the bundle doesn't change during a run, so we
// capture the producer's host kind into the sidecar where it survives for
// the next process to read. Different process types (app vs extension) that
// share a KSCrash install dir then don't mislabel each other's summaries.
static KSCrashRunSummaryHostKind hostKindForCurrentBundle(void)
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

/** Record `userID` in the bucket for `perceptible`. Call under g_userLock. */
static NSUInteger recordUserInBucketLocked(NSString *userID, bool perceptible)
{
    if (userID.length == 0) {
        return 0;
    }
    if (perceptible) {
        if (g_perceptibleUsers == nil) g_perceptibleUsers = [NSMutableSet set];
        [g_perceptibleUsers addObject:userID];
        return g_perceptibleUsers.count;
    }
    if (g_imperceptibleUsers == nil) g_imperceptibleUsers = [NSMutableSet set];
    [g_imperceptibleUsers addObject:userID];
    return g_imperceptibleUsers.count;
}

/** Locking wrapper for callers that are not already sequencing a user event. */
static NSUInteger recordUserInBucket(NSString *userID, bool perceptible)
{
    os_unfair_lock_lock(&g_userLock);
    NSUInteger count = recordUserInBucketLocked(userID, perceptible);
    os_unfair_lock_unlock(&g_userLock);
    return count;
}

void kscm_lifecycle_observeUser(const char *userID)
{
    // Gate on enable so pre-install writes can't stash a g_currentUserID that
    // would leak into a later setEnabled(true) session. The monitor always
    // clears g_currentUserID on disable, so post-enable writes stay correct.
    if (!atomic_load(&g_isEnabled)) {
        return;
    }

    NSString *asString = (userID != NULL && userID[0] != '\0') ? [NSString stringWithUTF8String:userID] : nil;

    // g_userLock is the ordering point shared with session begins. Keep it
    // through the log write so a lifecycle transition cannot snapshot one
    // user and open its session after a newer user has already been appended
    // to the preceding session.
    os_unfair_lock_lock(&g_userLock);
    g_currentUserID = [asString copy];
    if (asString.length == 0) {
        // Sign-out doesn't record an event, but it must break the
        // session log's adjacent-user dedup: alice → nil → alice is
        // two distinct activations, and the session log's contract is
        // "at_ms is when this user became active." Without this the
        // second alice call is suppressed as adjacent-same, and we
        // lose the activation timestamp.
        ks_spinlock_lock(&g_sidecarLock);
        KSCrashSessionLog *log = g_sessionLog;
        ks_spinlock_unlock(&g_sidecarLock);
        [log forgetLastUserID];
        os_unfair_lock_unlock(&g_userLock);
        return;
    }

    // Snapshot the log pointer, current bucket, and anchor while this user
    // event owns the ordering lock. Both event paths acquire g_userLock before
    // g_sidecarLock, then release the spinlock before doing log I/O.
    ks_spinlock_lock(&g_sidecarLock);
    KSCrashSessionLog *log = g_sessionLog;
    bool haveSidecar = g_sidecar != NULL;
    bool perceptible = haveSidecar ? g_sidecar->userPerceptible != 0 : false;
    uint64_t wallClockAtStartNs = haveSidecar ? g_sidecar->wallClockAtStartNs : 0;
    uint64_t monotonicAtStartNs = haveSidecar ? g_sidecar->monotonicAtStartNs : 0;
    ks_spinlock_unlock(&g_sidecarLock);

    if (log != nil && haveSidecar) {
        int64_t atMs =
            kslifecycle_epochMsFromMonotonicNs(ksdate_continuousNanoseconds(), wallClockAtStartNs, monotonicAtStartNs);
        [log recordUserID:asString atMs:atMs];
    }

    if (!haveSidecar) {
        os_unfair_lock_unlock(&g_userLock);
        return;
    }

    NSUInteger count = recordUserInBucketLocked(asString, perceptible);
    os_unfair_lock_unlock(&g_userLock);
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

/** Count the owed perceptible session, once. Returns true if it counted on
 *  this call, so the caller can mint the session's id. Call under g_sidecarLock. */
static bool countPerceptibleSessionIfPending(KSCrash_LifecycleData *sc)
{
    if (sc->perceptibleSessionPending) {
        sc->perceptibleSessionPending = 0;
        sc->perceptibleSessionsSinceLaunch++;
        return true;
    }
    return false;
}

/** Mint a new session id into the inactive slot of the sidecar's
 *  double-buffered session_id field, then publish it by flipping the
 *  one-byte slot selector. Call under g_sidecarLock.
 *
 *  The double-buffered layout exists so a crash mid-`ksid_generate`
 *  cannot leave a hybrid old/new UUID visible to the next launch: the
 *  writer only ever touches the *inactive* slot, and the release fence
 *  before the selector flip keeps the compiler (and CPU) from making
 *  the slot write visible after the flip. `ksid_generate` writes
 *  character-by-character, so without this the on-disk snapshot could
 *  end up with the first N chars of the new UUID and the last (37-N)
 *  chars of the previous one. See @c kslifecycle_currentSessionIDSnapshot. */
static void beginSessionLocked(KSCrash_LifecycleData *sc)
{
    _Static_assert(sizeof(sc->currentSessionIDs[0]) == KSRUNCONTEXT_RUN_ID_LENGTH,
                   "session id slot must match ksid_generate output size");
    uint8_t currentSlot = sc->currentSessionIDSlot;
    // Any value other than 0 or 1 is "no session yet" — start with slot 1
    // so the reader keying off slot 0's zero bytes still sees "no session"
    // if this write itself gets partially clobbered before it lands.
    uint8_t nextSlot = currentSlot <= 1 ? (uint8_t)(currentSlot ^ 1) : (uint8_t)1;
    ksid_generate(sc->currentSessionIDs[nextSlot]);
    atomic_thread_fence(memory_order_release);
    sc->currentSessionIDSlot = nextSlot;
}

static void onTransitionState(KSCrashAppTransitionState transitionState)
{
    atomic_store_explicit(&g_transitionState, transitionState, memory_order_relaxed);

    // Serialize the transition's session-log event with observeUser. The
    // sidecar spinlock is still released before disk I/O; g_userLock only
    // establishes a single order for current-user snapshots and log writes.
    os_unfair_lock_lock(&g_userLock);
    ks_spinlock_lock(&g_sidecarLock);
    KSCrash_LifecycleData *sc = g_sidecar;
    if (sc == NULL) {
        ks_spinlock_unlock(&g_sidecarLock);
        os_unfair_lock_unlock(&g_userLock);
        return;
    }

    bool imperceptibleBegan = false;

    switch (transitionState) {
        case KSCrashAppTransitionStateActive:
            updateSidecarDurations(sc);
            sc->applicationIsActive = true;
            break;

        case KSCrashAppTransitionStateDeactivating:
            updateSidecarDurations(sc);
            sc->applicationIsActive = false;
            break;

        case KSCrashAppTransitionStateBackground:
            // Background starts an imperceptible session and owes the next
            // foreground a perceptible one. The public sessionsSinceLaunch /
            // sessionsSinceLastCrash keep their historical "launch + foreground
            // resume" meaning and are not touched here.
            updateSidecarDurations(sc);
            sc->applicationIsInForeground = false;
            sc->imperceptibleSessionsSinceLaunch++;
            sc->perceptibleSessionPending = 1;
            imperceptibleBegan = true;
            break;

        case KSCrashAppTransitionStateForegrounding:
            updateSidecarDurations(sc);
            sc->applicationIsInForeground = true;
            sc->sessionsSinceLaunch++;
            sc->sessionsSinceLastCrash++;
            break;

        case KSCrashAppTransitionStateTerminating:
        case KSCrashAppTransitionStateExiting:
            updateSidecarDurations(sc);
            sc->cleanShutdown = true;
            break;

        default:
            break;
    }

    // Count the owed perceptible session the first time the app is genuinely
    // perceptible. Maybe (Startup/Launching) waits; No re-arms it on Background.
    bool perceptibleBegan = false;
    if (perceptibilityForState(transitionState) == KSCrashLifecyclePerceptibilityYes) {
        perceptibleBegan = countPerceptibleSessionIfPending(sc);
    }

    // A session begins the instant it is counted. Mint its id into the sidecar
    // under the lock; the SESSION_BEGIN log write happens after the lock is
    // released (log I/O off the sidecar spinlock).
    bool sessionBegan = perceptibleBegan || imperceptibleBegan;
    bool sessionPerceptible = perceptibleBegan;
    char newSessionID[KSRUNCONTEXT_RUN_ID_LENGTH];
    newSessionID[0] = '\0';
    uint64_t wallClockAtStartNs = 0;
    uint64_t monotonicAtStartNs = 0;
    if (sessionBegan) {
        beginSessionLocked(sc);
        const char *sessionIDBytes = kslifecycle_currentSessionIDSnapshot(sc);
        if (sessionIDBytes != NULL) {
            // sessionIDs slot size == sizeof(newSessionID) by construction
            // (both are KSRUNCONTEXT_RUN_ID_LENGTH).
            memcpy(newSessionID, sessionIDBytes, sizeof(newSessionID));
        }
        wallClockAtStartNs = sc->wallClockAtStartNs;
        monotonicAtStartNs = sc->monotonicAtStartNs;
    }

    bool previousPerceptible = sc->userPerceptible != 0;
    bool newPerceptible = ksapp_transitionStateIsUserPerceptible(transitionState);
    sc->transitionState = (uint8_t)transitionState;
    sc->userPerceptible = newPerceptible;
    updateSidecarTaskRole(sc);
    KSCrashSessionLog *sessionLog = g_sessionLog;
    ks_spinlock_unlock(&g_sidecarLock);

    if (sessionBegan && sessionLog != nil) {
        int64_t atMs =
            kslifecycle_epochMsFromMonotonicNs(ksdate_continuousNanoseconds(), wallClockAtStartNs, monotonicAtStartNs);
        NSString *currentUser = g_currentUserID;
        [sessionLog recordSessionBeginWithID:@(newSessionID)
                                 perceptible:sessionPerceptible
                                        atMs:atMs
                                      userID:currentUser];
    }

    NSUInteger count = 0;
    if (newPerceptible != previousPerceptible) {
        count = recordUserInBucketLocked(g_currentUserID, newPerceptible);
    }
    os_unfair_lock_unlock(&g_userLock);

    if (count > 0) {
        writeDistinctUserCountToSidecar(newPerceptible, count);
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

/** Create and initialize the mmap'd sidecar for the current run. On success
 *  also opens the run's growable session log and returns it via @c outLog (the
 *  caller publishes it under g_sidecarLock alongside g_sidecar). Returns NULL
 *  on sidecar-mmap failure; the session log is best-effort and may be nil even
 *  when the sidecar is returned. */
static KSCrash_LifecycleData *createSidecar(KSCrashSessionLog **outLog)
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

    // The launch owes a perceptible session, counted only when the app
    // actually reaches the foreground (perceptibilityForState == Yes). The
    // public sessionsSinceLaunch keeps its historical meaning (launch == 1,
    // plus each foreground resume), independent of the perceptibility buckets.
    sc->sessionsSinceLaunch = 1;
    sc->perceptibleSessionPending = 1;

    sc->taskRole = (int32_t)kstaskrole_current();
    sc->hostKind = (uint8_t)hostKindForCurrentBundle();
    sc->magic = KSLIFECYCLE_MAGIC;
    sc->version = KSCrash_Lifecycle_CurrentVersion;

    // Open the growable session log for this run (best-effort). SESSION_BEGIN /
    // USER events append here as they happen; the next launch reads it back into
    // the previous run summary's per-session list. Independent of the mmap'd
    // sidecar above — that holds counts, this holds one record per event. The
    // caller publishes the log under g_sidecarLock together with g_sidecar so
    // observers never see one without the other.
    char sessionLogPath[KSFU_MAX_PATH_LENGTH];
    if (outLog && g_callbacks.getRunSidecarPath &&
        g_callbacks.getRunSidecarPath("Sessions", sessionLogPath, sizeof(sessionLogPath))) {
        *outLog = [[KSCrashSessionLog alloc] initForWritingAtPath:@(sessionLogPath)];
    }

    return sc;
}

static void releaseSidecar(void)
{
    ks_spinlock_lock(&g_sidecarLock);
    KSCrash_LifecycleData *old = g_sidecar;
    g_sidecar = NULL;
    KSCrashSessionLog *log = g_sessionLog;
    g_sessionLog = nil;
    ks_spinlock_unlock(&g_sidecarLock);

    if (old) {
        ksfu_munmap(old, sizeof(KSCrash_LifecycleData));
    }
    [log close];
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
        KSCrashSessionLog *newLog = nil;
        KSCrash_LifecycleData *sc = createSidecar(&newLog);
        if (!sc) {
            atomic_store(&g_isEnabled, false);
            return;
        }

        ks_spinlock_lock(&g_sidecarLock);
        g_sidecar = sc;
        g_sessionLog = newLog;
        ks_spinlock_unlock(&g_sidecarLock);

        // Enable-race fixup: a concurrent observeUser could have passed the
        // atomic gate before the sidecar was published and bailed at the
        // !haveSidecar check without counting. Replay the stashed user into
        // its bucket now. The first SESSION_BEGIN will attach it to the log's
        // first session via recordSessionBeginWithID:...:userID:.
        os_unfair_lock_lock(&g_userLock);
        NSString *pendingUser = g_currentUserID;
        os_unfair_lock_unlock(&g_userLock);
        if (pendingUser.length > 0) {
            bool perceptible = sc->userPerceptible != 0;
            NSUInteger count = recordUserInBucket(pendingUser, perceptible);
            if (count > 0) {
                ks_spinlock_lock(&g_sidecarLock);
                if (perceptible) {
                    sc->distinctPerceptibleUserCount = (uint32_t)count;
                } else {
                    sc->distinctImperceptibleUserCount = (uint32_t)count;
                }
                ks_spinlock_unlock(&g_sidecarLock);
            }
        }

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
