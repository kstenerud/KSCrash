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
#import "KSSessionStore.h"
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

// The session writer is the single source of truth for the current session and
// user; the monitor keeps no parallel user state. Guarded by g_sessionLock,
// which is never taken on the crash path, so the writer's file I/O is safe under
// it. Created lazily (ensureSessionWriterLocked) and closed on disable.
static os_unfair_lock g_sessionLock = OS_UNFAIR_LOCK_INIT;
static KSSessionWriter *g_sessionWriter = NULL;

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
#pragma mark - Session writer -
// ============================================================================

/** Return the session writer, creating it on first use. Call under g_sessionLock.
 *  Returns NULL only when no summary-sidecar path is available (e.g. before
 *  install). kssw_open does no file I/O; the file opens on the first cut. */
static KSSessionWriter *ensureSessionWriterLocked(void)
{
    // Recheck enabled under g_sessionLock. observeUser and the transition can
    // pass the atomic gate and then block here while setEnabled(false) closes the
    // writer; without this recheck they would resurrect it and append after
    // teardown. Disable clears g_isEnabled before taking g_sessionLock, so this
    // (which holds it) always sees the cleared value.
    if (!atomic_load(&g_isEnabled)) {
        return NULL;
    }
    if (g_sessionWriter == NULL) {
        char path[KSFU_MAX_PATH_LENGTH];
        if (g_callbacks.getSummarySidecarPath != NULL &&
            g_callbacks.getSummarySidecarPath(kscrash_getRunID(), "sessions", path, sizeof(path))) {
            g_sessionWriter = kssw_open(path);
        }
    }
    return g_sessionWriter;
}

void kscm_lifecycle_observeUser(const char *userID)
{
    // Gate on the monitor being enabled so a userID set before install or after
    // disable doesn't create a writer.
    if (!atomic_load(&g_isEnabled)) {
        return;
    }
    os_unfair_lock_lock(&g_sessionLock);
    KSSessionWriter *writer = ensureSessionWriterLocked();
    if (writer != NULL) {
        // Only the user changed; keep the open session's perceptibility. A change
        // to anonymous (logout) is still a cut.
        kssw_updateUser(writer, userID);
    }
    os_unfair_lock_unlock(&g_sessionLock);
}

const char *kslifecycle_currentSessionID(void)
{
    // kssw_current's buffer is overwritten by the next cut; copy it out.
    static _Thread_local char buf[37];
    os_unfair_lock_lock(&g_sessionLock);
    const char *id = (g_sessionWriter != NULL) ? kssw_current(g_sessionWriter) : NULL;
    if (id != NULL) {
        strlcpy(buf, id, sizeof(buf));
    } else {
        buf[0] = '\0';
    }
    os_unfair_lock_unlock(&g_sessionLock);
    return buf[0] != '\0' ? buf : NULL;
}

bool kslifecycle_copyLastSessionIDForRunID(const char *runID, char *buf, size_t bufLen)
{
    if (buf == NULL || bufLen == 0) {
        return false;
    }
    buf[0] = '\0';
    if (runID == NULL || runID[0] == '\0' || g_callbacks.getSummarySidecarPath == NULL) {
        return false;
    }
    char path[KSFU_MAX_PATH_LENGTH];
    if (!g_callbacks.getSummarySidecarPath(runID, "sessions", path, sizeof(path))) {
        return false;
    }
    KSSessionReader *reader = kssr_open(path);
    bool found = false;
    int count = kssr_count(reader);
    if (count > 0) {
        KSSessionRecord rec;
        if (kssr_sessionAt(reader, count - 1, &rec)) {
            strlcpy(buf, rec.guid, bufLen);
            found = buf[0] != '\0';
        }
    }
    kssr_close(reader);
    return found;
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
            updateSidecarDurations(sc);
            sc->applicationIsActive = true;
            break;

        case KSCrashAppTransitionStateDeactivating:
            updateSidecarDurations(sc);
            sc->applicationIsActive = false;
            break;

        case KSCrashAppTransitionStateBackground:
            // The public sessionsSinceLaunch / sessionsSinceLastCrash keep their
            // historical "launch + foreground resume" meaning and are not touched
            // here.
            updateSidecarDurations(sc);
            sc->applicationIsInForeground = false;
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
            sc->cleanExit = true;
            break;

        default:
            break;
    }

    bool previousPerceptible = sc->userPerceptible != 0;
    bool newPerceptible = ksapp_transitionStateIsUserPerceptible(transitionState);
    sc->transitionState = (uint8_t)transitionState;
    sc->userPerceptible = newPerceptible;
    updateSidecarTaskRole(sc);
    ks_spinlock_unlock(&g_sidecarLock);

    // Perceptibility flipped: cut a new session, keeping the open session's user.
    if (newPerceptible != previousPerceptible) {
        os_unfair_lock_lock(&g_sessionLock);
        KSSessionWriter *writer = ensureSessionWriterLocked();
        if (writer != NULL) {
            kssw_updatePerceptible(writer, newPerceptible);
        }
        os_unfair_lock_unlock(&g_sessionLock);
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

    // The public sessionsSinceLaunch keeps its historical meaning (launch == 1,
    // plus each foreground resume).
    sc->sessionsSinceLaunch = 1;

    sc->taskRole = (int32_t)kstaskrole_current();
    sc->hostKind = (uint8_t)hostKindForCurrentBundle();
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
        sc->hangActive = (change == KSHangChangeTypeStarted);
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
            // g_isEnabled was already true, so a concurrent setUserID could have
            // opened g_sessionWriter. Clear the flag first (new callers bail at
            // ensureSessionWriterLocked's recheck), then close any writer that
            // slipped in — disable can't, its CAS no-ops on the already-false flag.
            atomic_store(&g_isEnabled, false);
            os_unfair_lock_lock(&g_sessionLock);
            kssw_close(g_sessionWriter);
            g_sessionWriter = NULL;
            os_unfair_lock_unlock(&g_sessionLock);
            return;
        }

        ks_spinlock_lock(&g_sidecarLock);
        g_sidecar = sc;
        ks_spinlock_unlock(&g_sidecarLock);

        // Record the launch session. kssw_updatePerceptible establishes the
        // launch perceptibility while keeping whatever user a setUserID racing
        // this enable may already have set on the writer (else anonymous).
        ks_spinlock_lock(&g_sidecarLock);
        bool perceptible = g_sidecar->userPerceptible != 0;
        ks_spinlock_unlock(&g_sidecarLock);

        os_unfair_lock_lock(&g_sessionLock);
        KSSessionWriter *writer = ensureSessionWriterLocked();
        if (writer != NULL) {
            kssw_updatePerceptible(writer, perceptible);
        }
        os_unfair_lock_unlock(&g_sessionLock);

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

        os_unfair_lock_lock(&g_sessionLock);
        kssw_close(g_sessionWriter);
        g_sessionWriter = NULL;
        os_unfair_lock_unlock(&g_sessionLock);

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
    // For fatal events, write cleanExit and monitorHandlerRan before acquiring the
    // lock. These are small stores to mmap'd memory that must succeed unconditionally
    // — if the bounded lock times out we still need the next launch to see the correct
    // state. In practice, fatal events run with other threads suspended so lock
    // contention is unlikely, but this is defense-in-depth.
    if (isFatal && g_sidecar != NULL) {
        g_sidecar->cleanExit = eventContext->requirements.isCleanExit;
        g_sidecar->monitorHandlerRan = true;
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
