//
//  KSCrashMonitor_Watchdog.c
//
//  Created by Alexander Cohen on 2025-11-04.
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

#include "KSCrashMonitor_Watchdog.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach/task_policy.h>
#include <os/lock.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#include "KSCrashMonitor_WatchdogSidecar.h"
#include "KSCrashNamespace.h"
#include "KSCrashReportFields.h"
#include "KSDebug.h"
#include "KSFileUtils.h"
#include "KSHang.h"
#include "KSID.h"
#include "KSLogger.h"
#include "KSMachineContext.h"
#include "KSStackCursor_MachineContext.h"
#include "KSThread.h"
#include "Unwind/KSStackCursor_Unwind.h"

// ============================================================================
#pragma mark - Constants -
// ============================================================================

// Apple's definition of a "hang" — see KSCrashMonitor_Watchdog.h.
#define KSHANG_THRESHOLD_SECONDS 0.250

#define KSHANG_MAX_OBSERVERS 8

// ============================================================================
#pragma mark - Types -
// ============================================================================

typedef struct {
    KSHangObserverCallback func;
    void *context;
    bool active;
} HangObserver;

// ============================================================================
#pragma mark - Hang Monitor -
// ============================================================================
//
// Architecture overview
// ---------------------
// The watchdog monitor uses two threads and two run loops:
//
//   1. **Main thread / main run loop** — A CFRunLoopObserver watches for
//      kCFRunLoopAfterWaiting (the run loop woke up and is about to process
//      work) and kCFRunLoopBeforeWaiting (finished processing, going idle).
//
//   2. **Watchdog thread / watchdog run loop** — A dedicated high-priority
//      pthread that runs its own CFRunLoop.  A repeating CFRunLoopTimer on
//      this run loop fires every `threshold` seconds to check whether the
//      main thread is still blocked.
//
// The two threads communicate through:
//   - `enterTime` (_Atomic uint64_t) — written by the main thread when the
//     run loop wakes, read by the watchdog timer to measure elapsed time.
//     Uses relaxed ordering because it is a standalone timing value with no
//     dependencies on other memory operations.
//   - `lock` (os_unfair_lock) — protects the mutable `hang` state, sidecar
//     pointer, and observer array.  Held only briefly for reads/writes of
//     these fields; never held during I/O or observer callbacks.
//
// Hang lifecycle
// --------------
//   1. Main run loop wakes → mainRunLoopActivity(AfterWaiting) stores
//      enterTime and installs a repeating timer on the watchdog thread.
//   2. Timer fires → watchdogTimerFired() reads enterTime, computes elapsed
//      time.  If >= threshold and no hang is active, it transitions to a new
//      hang: writes a crash report, opens an mmap'd sidecar file, and
//      notifies observers.  On subsequent fires it updates the sidecar's
//      end-timestamp and notifies observers of the update.
//   3. Main run loop goes idle → mainRunLoopActivity(BeforeWaiting) cancels
//      the timer.  If a hang was active, it takes ownership of the hang
//      state and calls finalizeResolvedHang(), which either deletes the
//      report (reportsHangs == false) or marks the sidecar as recovered.
//   4. If a fatal crash occurs while a hang is active,
//      addContextualInfoToEvent() deletes the hang report and sidecar so
//      they don't appear as orphaned reports on the next launch.
//
// Sidecar files
// -------------
// A sidecar is a small mmap'd binary file (KSHangSidecar, 24 bytes) written
// alongside the crash report.  It stores the latest end-timestamp and task
// role, and is updated in-place on each timer fire via direct memory writes
// (the kernel flushes dirty pages to disk).  This avoids re-writing the
// full JSON report on every update.  At next launch, the stitch logic
// (KSCrashMonitor_WatchdogStitch.m) reads the sidecar and merges its data
// into the JSON report before delivery.
//

typedef struct KSHangMonitor {
    CFRunLoopRef runLoop;
    double threshold;
    uint64_t thresholdNs;  // precomputed: threshold * 1e9
    CFRunLoopObserverRef observer;
    CFRunLoopRef watchdogRunLoop;
    CFRunLoopTimerRef watchdogTimer;
    dispatch_semaphore_t threadExitSemaphore;

    // Set by watchdog_destroy on timeout.  Tells the watchdog thread to
    // call sidecar_delete + free(monitor) itself when it finally exits,
    // avoiding a use-after-free if destroy returns before the thread stops.
    _Atomic bool selfFreeOnExit;

    // When false (current default), recovered hang reports are deleted.
    // When true, they're preserved with the sidecar marking them as recovered.
    // TODO: expose through KSCrashCConfiguration.
    bool reportsHangs;

    // Protects: hang, sidecar, sidecarPath, observers, observerCount.
    // IMPORTANT: never hold this during I/O, report writing, or observer
    // callbacks — the watchdog timer fires every 250ms and must not stall.
    os_unfair_lock lock;
    KSHangState hang;

    // Written by main thread (mainRunLoopActivity), read by watchdog thread
    // (watchdogTimerFired).  Relaxed ordering is fine — this is a standalone
    // timing value with no publish/consume relationship to other fields.
    _Atomic uint64_t enterTime;

    KSHangSidecar *sidecar;  // mmap'd, or NULL
    char sidecarPath[PATH_MAX];

    HangObserver observers[KSHANG_MAX_OBSERVERS];
    int observerCount;
} KSHangMonitor;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static atomic_bool g_isEnabled = false;
static KSHangMonitor *g_watchdog = NULL;
static KSCrash_ExceptionHandlerCallbacks g_callbacks = { 0 };

// ============================================================================
#pragma mark - Utilities -
// ============================================================================

static uint64_t monotonicUptime(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

static int currentTaskRole(void)
{
#if TARGET_OS_TV || TARGET_OS_WATCH
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

// ============================================================================
#pragma mark - Sidecar lifecycle -
// ============================================================================

static const char *monitorId(void);

static KSHangSidecar *sidecar_open(KSHangMonitor *monitor, int64_t reportID)
{
    if (!g_callbacks.getSidecarReportPath) {
        return NULL;
    }

    if (!g_callbacks.getSidecarReportPath(monitorId(), reportID, monitor->sidecarPath, sizeof(monitor->sidecarPath))) {
        monitor->sidecarPath[0] = '\0';
        return NULL;
    }

    KSHangSidecar *sc = (KSHangSidecar *)ksfu_mmap(monitor->sidecarPath, sizeof(KSHangSidecar));
    if (!sc) {
        KSLOG_ERROR("Failed to mmap sidecar at %s", monitor->sidecarPath);
        monitor->sidecarPath[0] = '\0';
        return NULL;
    }

    sc->magic = KSHANG_SIDECAR_MAGIC;
    sc->version = KSHANG_SIDECAR_CURRENT_VERSION;
    sc->recovered = false;
    return sc;
}

static void sidecar_update(KSHangSidecar *sc, uint64_t endTimestamp, task_role_t endRole)
{
    if (!sc) {
        return;
    }
    sc->endTimestamp = endTimestamp;
    sc->endRole = endRole;
}

static void sidecar_finalize(KSHangMonitor *monitor, bool recovered)
{
    if (monitor->sidecar) {
        monitor->sidecar->recovered = recovered;
        ksfu_munmap(monitor->sidecar, sizeof(KSHangSidecar));
        monitor->sidecar = NULL;
    }
}

static void sidecar_delete(KSHangMonitor *monitor)
{
    sidecar_finalize(monitor, false);
    if (monitor->sidecarPath[0] != '\0') {
        unlink(monitor->sidecarPath);
        monitor->sidecarPath[0] = '\0';
    }
}

// ============================================================================
#pragma mark - Observer notification -
// ============================================================================

// Snapshot the observer array under the lock, then notify outside it.
// This lets callbacks safely call kshang_add/removeHangObserver without deadlocking.
static void notifyObservers(KSHangMonitor *monitor, KSHangChangeType type, uint64_t start, uint64_t now)
{
    HangObserver snapshot[KSHANG_MAX_OBSERVERS];
    int count = 0;

    os_unfair_lock_lock(&monitor->lock);
    count = monitor->observerCount;
    memcpy(snapshot, monitor->observers, sizeof(snapshot));
    os_unfair_lock_unlock(&monitor->lock);

    for (int i = 0; i < count; i++) {
        if (snapshot[i].active && snapshot[i].func) {
            snapshot[i].func(type, start, now, snapshot[i].context);
        }
    }
}

// ============================================================================
#pragma mark - Report writing -
// ============================================================================

// Called on the watchdog thread when a new hang is first detected.
// Runs OUTSIDE the lock because report writing involves I/O.
static void populateReportForCurrentHang(KSHangMonitor *monitor)
{
    if (!g_callbacks.handleWithResult || !g_callbacks.notify) {
        return;
    }

    // Snapshot the hang state and freeze all threads while holding the lock.
    // Taking the lock first guarantees the main thread is not holding it when
    // suspended — if it's in mainRunLoopActivity, we block until it releases.
    // notify() will call ksmc_suspendEnvironment again (incrementing each
    // thread's suspend count to 2) and its matching ksmc_resumeEnvironment
    // drops it back to 1.  Our resume below drops it to 0.
    thread_act_array_t suspendedThreads = NULL;
    mach_msg_type_number_t suspendedThreadsCount = 0;

    os_unfair_lock_lock(&monitor->lock);
    KSHangState hang = monitor->hang;
    ksmc_suspendEnvironment(&suspendedThreads, &suspendedThreadsCount);
    os_unfair_lock_unlock(&monitor->lock);

    if (!hang.active) {
        ksmc_resumeEnvironment(&suspendedThreads, &suspendedThreadsCount);
        KSLOG_DEBUG("hang ended before report could be populated");
        return;
    }

    KSCrash_MonitorContext *crashContext = g_callbacks.notify(
        (thread_t)ksthread_main(),
        (KSCrash_ExceptionHandlingRequirements) {
            .asyncSafety = false, .isFatal = false, .shouldRecordAllThreads = true, .shouldWriteReport = true });

    KSMachineContext machineContext = { 0 };
    ksmc_getContextForThreadCheckingStackOverflow(ksthread_main(), &machineContext, true, false);
    KSStackCursor stackCursor;
    kssc_initWithUnwind(&stackCursor, KSSC_MAX_STACK_DEPTH, &machineContext);

    kscm_fillMonitorContext(crashContext, kscm_watchdog_getAPI());
    crashContext->registersAreValid = true;
    crashContext->offendingMachineContext = &machineContext;
    crashContext->stackCursor = &stackCursor;

    // Simulate what the OS produces for a watchdog kill: SIGKILL + EXC_CRASH
    // + 0x8badf00d.  If the hang resolves, the stitch logic strips these
    // fields and marks the report as a recovered hang instead.
    crashContext->signal.signum = SIGKILL;
    crashContext->signal.sigcode = 0;

    crashContext->mach.type = EXC_CRASH;
    crashContext->mach.code = SIGKILL;
    crashContext->mach.subcode = KERN_TERMINATED;

    crashContext->exitReason.code = 0x8badf00d;

    crashContext->Hang.inProgress = true;
    crashContext->Hang.timestamp = hang.timestamp;
    crashContext->Hang.role = hang.role;
    crashContext->Hang.endTimestamp = hang.endTimestamp;
    crashContext->Hang.endRole = hang.endRole;

    KSCrash_ReportResult result = { 0 };
    g_callbacks.handleWithResult(crashContext, &result);

    ksmc_resumeEnvironment(&suspendedThreads, &suspendedThreadsCount);

    // Re-check: the main thread may have resolved the hang while we were
    // writing the report.  Compare timestamps to make sure it's still the
    // same hang before attaching the report path and sidecar.
    os_unfair_lock_lock(&monitor->lock);
    if (monitor->hang.active && monitor->hang.timestamp == hang.timestamp) {
        monitor->hang.reportId = result.reportId;
        if (strlcpy(monitor->hang.path, result.path, PATH_MAX) >= PATH_MAX) {
            KSLOG_ERROR("Report path too long, discarding hang report");
        } else {
            monitor->sidecar = sidecar_open(monitor, result.reportId);
            sidecar_update(monitor->sidecar, monitor->hang.endTimestamp, monitor->hang.endRole);
        }
    } else {
        KSLOG_DEBUG("hang changed during report population - discarding");
    }
    os_unfair_lock_unlock(&monitor->lock);

    KSLOG_INFO("Hang started (reportID: %" PRIx64 ")", result.reportId);

    notifyObservers(monitor, KSHangChangeTypeStarted, hang.timestamp, hang.endTimestamp);
}

static void writeUpdatedReport(KSHangMonitor *monitor)
{
    uint64_t timestampStart = 0;
    uint64_t timestampEnd = 0;

    os_unfair_lock_lock(&monitor->lock);
    if (!monitor->hang.active) {
        os_unfair_lock_unlock(&monitor->lock);
        return;
    }
    timestampStart = monitor->hang.timestamp;
    timestampEnd = monitor->hang.endTimestamp;
    sidecar_update(monitor->sidecar, timestampEnd, monitor->hang.endRole);
    os_unfair_lock_unlock(&monitor->lock);

    notifyObservers(monitor, KSHangChangeTypeUpdated, timestampStart, timestampEnd);
}

static void finalizeResolvedHang(KSHangMonitor *monitor, KSHangState hang)
{
    if (hang.path[0] != '\0') {
        if (monitor->reportsHangs) {
            sidecar_finalize(monitor, true);
        } else {
            sidecar_delete(monitor);
            if (unlink(hang.path) != 0) {
                KSLOG_ERROR("Failed to delete hang report at %s: %s", hang.path, strerror(errno));
            }
        }
    } else {
        sidecar_delete(monitor);
    }

    KSLOG_INFO("Hang ended (reportID: %" PRIx64 ", duration: %.3f s)", hang.reportId,
               (double)(hang.endTimestamp - hang.timestamp) / 1e9);

    notifyObservers(monitor, KSHangChangeTypeEnded, hang.timestamp, hang.endTimestamp);
}

// ============================================================================
#pragma mark - Ping / Activity handlers -
// ============================================================================
//
// Detection state machine:
//
//   Main run loop wakes (kCFRunLoopAfterWaiting)
//     → mainRunLoopActivity() records enterTime and starts a repeating timer
//       on the watchdog thread.
//
//   Timer fires every `threshold` seconds on the watchdog thread
//     → watchdogTimerFired() compares now vs enterTime.
//       If hangTime >= threshold:
//         - First detection: creates a hang report + sidecar.
//         - Subsequent fires: updates sidecar with latest timestamp/role.
//
//   Main run loop goes idle (kCFRunLoopBeforeWaiting)
//     → mainRunLoopActivity() cancels the timer.
//       If a hang was active, finalizeResolvedHang() either deletes the
//       report (reportsHangs == false) or marks the sidecar as recovered.
//

// Runs on the watchdog thread.
static void watchdogTimerFired(CFRunLoopTimerRef timer, void *info)
{
    (void)timer;
    KSHangMonitor *monitor = (KSHangMonitor *)info;

    // Load enterTime exactly once — a second load could see a newer value
    // if the main thread briefly woke between the two reads, causing us to
    // initialize the hang with the wrong start timestamp.
    uint64_t enter = atomic_load_explicit(&monitor->enterTime, memory_order_relaxed);
    uint64_t now = monotonicUptime();
    uint64_t hangTime = now - enter;

    if (hangTime < monitor->thresholdNs) {
        return;
    }

    task_role_t currentRole = currentTaskRole();

    bool shouldStartNewHang = false;
    bool shouldUpdateHang = false;

    os_unfair_lock_lock(&monitor->lock);
    if (!monitor->hang.active) {
        kshangstate_init(&monitor->hang, enter, currentRole);
        monitor->hang.endTimestamp = now;
        monitor->hang.endRole = currentRole;
        shouldStartNewHang = true;
    } else {
        monitor->hang.endTimestamp = now;
        monitor->hang.endRole = currentRole;
        shouldUpdateHang = true;
    }
    os_unfair_lock_unlock(&monitor->lock);

    if (shouldStartNewHang) {
        populateReportForCurrentHang(monitor);
    } else if (shouldUpdateHang) {
        writeUpdatedReport(monitor);
    }
}

static void schedulePings(KSHangMonitor *monitor)
{
    atomic_store_explicit(&monitor->enterTime, monotonicUptime(), memory_order_relaxed);

    CFRunLoopTimerContext timerCtx = {
        .version = 0, .info = monitor, .retain = NULL, .release = NULL, .copyDescription = NULL
    };
    monitor->watchdogTimer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + monitor->threshold,
                                                  monitor->threshold, 0, 0, watchdogTimerFired, &timerCtx);
    CFRunLoopAddTimer(monitor->watchdogRunLoop, monitor->watchdogTimer, kCFRunLoopCommonModes);
}

// Runs on the main thread.  Called for both BeforeWaiting (going idle) and
// AfterWaiting (woke up).  We always cancel the previous timer first — the
// timer lives on the watchdog run loop but CFRunLoopTimerInvalidate is
// thread-safe and removes it from all run loops it was added to.
static void mainRunLoopActivity(CFRunLoopObserverRef obs, CFRunLoopActivity activity, void *info)
{
    (void)obs;
    KSHangMonitor *monitor = (KSHangMonitor *)info;

    if (monitor->watchdogTimer) {
        CFRunLoopTimerInvalidate(monitor->watchdogTimer);
        CFRelease(monitor->watchdogTimer);
        monitor->watchdogTimer = NULL;
    }

    if (activity == kCFRunLoopBeforeWaiting) {
        KSHangState hang = { 0 };
        bool hadHang = false;

        os_unfair_lock_lock(&monitor->lock);
        if (monitor->hang.active) {
            hang = monitor->hang;
            kshangstate_clear(&monitor->hang);
            hadHang = true;
        }
        os_unfair_lock_unlock(&monitor->lock);

        if (!hadHang) {
            return;
        }

        hang.endTimestamp = monotonicUptime();
        hang.endRole = currentTaskRole();
        finalizeResolvedHang(monitor, hang);

    } else if (activity == kCFRunLoopAfterWaiting) {
        schedulePings(monitor);
    }
}

// ============================================================================
#pragma mark - Thread lifecycle -
// ============================================================================

typedef struct {
    KSHangMonitor *monitor;
    dispatch_semaphore_t setupSemaphore;
} WatchdogThreadArg;

static void *watchdog_thread_main(void *arg)
{
    WatchdogThreadArg *threadArg = (WatchdogThreadArg *)arg;
    KSHangMonitor *monitor = threadArg->monitor;
    dispatch_semaphore_t setupSemaphore = threadArg->setupSemaphore;
    free(threadArg);

    // Can't use KSCRASH_NS_STRING here because it concatenates without a
    // separator, producing "com.kscrashMyApp..." instead of "com.kscrash.MyApp...".
#ifdef KSCRASH_NAMESPACE
    pthread_setname_np("com.kscrash." KSCRASH_NAMESPACE_STRING ".hang.watchdog.thread");
#else
    pthread_setname_np("com.kscrash.hang.watchdog.thread");
#endif

    CFRunLoopRef currentRunLoop = CFRunLoopGetCurrent();

    os_unfair_lock_lock(&monitor->lock);
    monitor->watchdogRunLoop = currentRunLoop;
    os_unfair_lock_unlock(&monitor->lock);

    // A CFRunLoop with no sources exits immediately.  Add a dummy source
    // so it stays alive until we call CFRunLoopStop in watchdog_destroy.
    CFRunLoopSourceContext srcCtx = { .version = 0, .info = NULL };
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &srcCtx);
    CFRunLoopAddSource(currentRunLoop, source, kCFRunLoopCommonModes);
    CFRelease(source);

    // Signal setup complete *from within* the run loop, so the creator knows
    // watchdogRunLoop is set and CFRunLoopRun has started accepting timers.
    CFRunLoopPerformBlock(currentRunLoop, kCFRunLoopCommonModes, ^{
        dispatch_semaphore_signal(setupSemaphore);
    });

    CFRunLoopRun();

    dispatch_semaphore_signal(monitor->threadExitSemaphore);

    // If watchdog_destroy timed out waiting for us, it set selfFreeOnExit
    // and returned without freeing.  We own the cleanup in that case.
    if (atomic_load_explicit(&monitor->selfFreeOnExit, memory_order_acquire)) {
        sidecar_delete(monitor);
        free(monitor);
    }
    return NULL;
}

// ============================================================================
#pragma mark - Monitor create / destroy -
// ============================================================================

static KSHangMonitor *watchdog_create(CFRunLoopRef runLoop, double threshold)
{
    KSHangMonitor *monitor = (KSHangMonitor *)calloc(1, sizeof(KSHangMonitor));
    if (!monitor) {
        return NULL;
    }

    monitor->reportsHangs = false;
    monitor->lock = OS_UNFAIR_LOCK_INIT;
    monitor->runLoop = runLoop;
    monitor->threshold = threshold;
    monitor->thresholdNs = (uint64_t)(threshold * 1000000000);
    monitor->threadExitSemaphore = dispatch_semaphore_create(0);

    dispatch_semaphore_t setupSemaphore = dispatch_semaphore_create(0);

    WatchdogThreadArg *threadArg = (WatchdogThreadArg *)calloc(1, sizeof(WatchdogThreadArg));
    if (!threadArg) {
        free(monitor);
        return NULL;
    }
    threadArg->monitor = monitor;
    threadArg->setupSemaphore = setupSemaphore;

    pthread_attr_t attr;
    if (pthread_attr_init(&attr) != 0) {
        free(threadArg);
        free(monitor);
        return NULL;
    }
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

    pthread_t thread;
    int err = pthread_create(&thread, &attr, watchdog_thread_main, threadArg);
    pthread_attr_destroy(&attr);

    if (err != 0) {
        KSLOG_ERROR("Failed to create watchdog thread: %s", strerror(err));
        free(threadArg);
        free(monitor);
        return NULL;
    }

    dispatch_semaphore_wait(setupSemaphore, DISPATCH_TIME_FOREVER);

    schedulePings(monitor);

    CFRunLoopObserverContext obsCtx = { .version = 0, .info = monitor };
    monitor->observer = CFRunLoopObserverCreate(NULL, kCFRunLoopBeforeWaiting | kCFRunLoopAfterWaiting, true, 0,
                                                mainRunLoopActivity, &obsCtx);
    CFRunLoopAddObserver(runLoop, monitor->observer, kCFRunLoopCommonModes);

    return monitor;
}

static void watchdog_destroy(KSHangMonitor *monitor)
{
    if (!monitor) {
        return;
    }

    if (monitor->observer) {
        CFRunLoopObserverInvalidate(monitor->observer);
        CFRelease(monitor->observer);
    }

    if (monitor->watchdogTimer) {
        CFRunLoopTimerInvalidate(monitor->watchdogTimer);
        CFRelease(monitor->watchdogTimer);
    }

    CFRunLoopRef rl = NULL;
    os_unfair_lock_lock(&monitor->lock);
    rl = monitor->watchdogRunLoop;
    monitor->watchdogRunLoop = NULL;
    os_unfair_lock_unlock(&monitor->lock);

    if (rl) {
        CFRunLoopStop(rl);
    }

    if (monitor->threadExitSemaphore) {
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
        if (dispatch_semaphore_wait(monitor->threadExitSemaphore, timeout) != 0) {
            // Thread is still running.  Hand ownership to it so it can
            // clean up after itself; freeing here would be a UAF.
            KSLOG_ERROR("Watchdog thread did not exit within 5 seconds; thread will self-free");
            atomic_store_explicit(&monitor->selfFreeOnExit, true, memory_order_release);
            return;
        }
    }

    sidecar_delete(monitor);

    free(monitor);
}

// ============================================================================
#pragma mark - Observer API -
// ============================================================================

const KSHangObserverToken KSHangObserverTokenNotFound = -1;

KSHangObserverToken kshang_addHangObserver(KSHangObserverCallback callback, void *context)
{
    KSHangMonitor *monitor = g_watchdog;
    if (!monitor || !callback) {
        return KSHangObserverTokenNotFound;
    }

    KSHangObserverToken token = KSHangObserverTokenNotFound;
    os_unfair_lock_lock(&monitor->lock);

    // First, try to reuse an inactive slot
    for (int i = 0; i < monitor->observerCount; i++) {
        if (!monitor->observers[i].active) {
            token = i;
            break;
        }
    }

    // If no inactive slot found, append if there's room
    if (token == KSHangObserverTokenNotFound && monitor->observerCount < KSHANG_MAX_OBSERVERS) {
        token = monitor->observerCount;
        monitor->observerCount++;
    }

    if (token != KSHangObserverTokenNotFound) {
        monitor->observers[token].func = callback;
        monitor->observers[token].context = context;
        monitor->observers[token].active = true;
    }

    os_unfair_lock_unlock(&monitor->lock);
    return token;
}

void kshang_removeHangObserver(KSHangObserverToken token)
{
    KSHangMonitor *monitor = g_watchdog;
    if (!monitor || token < 0 || token >= KSHANG_MAX_OBSERVERS) {
        return;
    }

    os_unfair_lock_lock(&monitor->lock);
    if (token < monitor->observerCount) {
        monitor->observers[token].active = false;
        monitor->observers[token].func = NULL;
        monitor->observers[token].context = NULL;
    }
    os_unfair_lock_unlock(&monitor->lock);
}

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

static const char *monitorId(void) { return "Watchdog"; }

static KSCrashMonitorFlag monitorFlags(void) { return KSCrashMonitorFlagNone; }

static void setEnabled(bool isEnabled)
{
    const char *forceEnv = getenv("KSCRASH_FORCE_ENABLE_WATCHDOG");
    bool forceEnable = forceEnv && (strcmp(forceEnv, "1") == 0 || strcmp(forceEnv, "YES") == 0);

    if (!forceEnable && ksdebug_isBeingTraced()) {
        KSLOG_DEBUG("Cannot run watchdog monitor while attached to a debugger.");
        return;
    }

    bool expectEnabled = !isEnabled;
    if (!atomic_compare_exchange_strong(&g_isEnabled, &expectEnabled, isEnabled)) {
        return;
    }

    if (isEnabled) {
        g_watchdog = watchdog_create(CFRunLoopGetMain(), KSHANG_THRESHOLD_SECONDS);
        if (!g_watchdog) {
            atomic_store(&g_isEnabled, false);
            return;
        }
    } else {
        KSHangMonitor *old = g_watchdog;
        g_watchdog = NULL;
        watchdog_destroy(old);
    }
}

static bool isEnabled(void) { return g_isEnabled; }

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks) { g_callbacks = *callbacks; }

/** Called by the crash handling pipeline on every enabled monitor.
 *
 * When a fatal crash (signal, Mach exception, etc.) occurs while a hang is
 * in progress, delete the incomplete hang report and its sidecar so they
 * don't appear as orphaned reports on next launch.
 *
 * All other threads have been suspended by the crash handler at this point,
 * so accessing the monitor struct without a lock is safe.  unlink() is
 * async-signal-safe.
 */
static void addContextualInfoToEvent(struct KSCrash_MonitorContext *eventContext)
{
    if (!eventContext->requirements.isFatal) {
        return;
    }

    KSHangMonitor *monitor = g_watchdog;
    if (!monitor || !monitor->hang.active) {
        return;
    }

    if (monitor->sidecarPath[0] != '\0') {
        unlink(monitor->sidecarPath);
    }

    if (monitor->hang.path[0] != '\0') {
        unlink(monitor->hang.path);
    }
}

const char *kscm_stringFromRole(int /*task_role_t*/ role)
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

/** Implemented in KSCrashMonitor_WatchdogStitch.m */
extern char *kscm_watchdog_stitchReport(const char *report, int64_t reportID, const char *sidecarPath);

KSCrashMonitorAPI *kscm_watchdog_getAPI(void)
{
    static KSCrashMonitorAPI api = { 0 };
    if (kscma_initAPI(&api)) {
        api.init = monitorInit;
        api.monitorId = monitorId;
        api.monitorFlags = monitorFlags;
        api.setEnabled = setEnabled;
        api.isEnabled = isEnabled;
        api.addContextualInfoToEvent = addContextualInfoToEvent;
        api.stitchReport = kscm_watchdog_stitchReport;
    }
    return &api;
}
