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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "KSCrashAppState.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorHelper.h"
#include "KSCrashMonitor_Lifecycle.h"
#include "KSCrashMonitor_WatchdogSidecar.h"
#include "KSCrashNamespace.h"
#include "KSCrashReportFields.h"
#include "KSCrashReportStoreC+Private.h"
#include "KSCrashRunContext.h"
#include "KSDate.h"
#include "KSDebug.h"
#include "KSFileUtils.h"
#include "KSHang.h"
#include "KSHangEvent.h"
#include "KSID.h"
#include "KSLogger.h"
#include "KSMachineContext.h"
#include "KSStackCursor_MachineContext.h"
#include "KSThread.h"
#include "Unwind/KSStackCursor_Unwind.h"

// ============================================================================
#pragma mark - Constants -
// ============================================================================

// Apple's definition of a "hang" (see KSCrashMonitor_Watchdog.h).
#define KSHANG_THRESHOLD_SECONDS 0.250

// ============================================================================
#pragma mark - Hang Monitor -
// ============================================================================
//
// Architecture overview
// ---------------------
// The watchdog monitor uses two threads and two run loops:
//
//   1. **Main thread / main run loop**: A CFRunLoopObserver watches for
//      kCFRunLoopAfterWaiting (the run loop woke up and is about to process
//      work) and kCFRunLoopBeforeWaiting (finished processing, going idle).
//
//   2. **Watchdog thread / watchdog run loop**: A dedicated high-priority
//      pthread that runs its own CFRunLoop.  A repeating CFRunLoopTimer on
//      this run loop fires every `threshold` seconds to check whether the
//      main thread is still blocked.
//
// The two threads communicate through:
//   - `enterTime` (_Atomic uint64_t): written by the main thread when the
//     run loop wakes, read by the watchdog timer to measure elapsed time.
//   - `mainIsIdle` (_Atomic bool): set by the main thread when the run loop
//     goes idle and cleared when it wakes, after the new enterTime is stored
//     (release), so a timer that sees it cleared (acquire) also sees that
//     enterTime.  Before starting or updating a hang, the timer checks under
//     the lock that the main thread is not idle and that enterTime is still
//     the value it measured; either one failing means its measurement is stale.
//   - `lock` (os_unfair_lock): protects the mutable `hang` state and the
//     flags beside it.  Held only briefly for reads/writes of these fields;
//     never held during I/O or hang event dispatch.
//
// Everything a hang does after it is detected (its sidecar's file work, its
// report, and every hang event) happens on the watchdog thread. The main thread
// only marks a hang's record ended, the moment it goes idle, and hands the hang
// over, so listeners see the events in order from one thread, and the hang's
// file work never runs on the host's main thread.
//
// Hang lifecycle
// --------------
//   1. Main run loop wakes → mainRunLoopActivity(AfterWaiting) stores
//      enterTime and installs a repeating timer on the watchdog thread.
//   2. Timer fires → watchdogTimerFired() reads enterTime, computes elapsed
//      time.  If >= threshold and no hang is active, it transitions to a new
//      hang: records it (the mmap'd run sidecar and the lifecycle's hang
//      flag), writes a crash report, then dispatches Started.  On
//      subsequent fires it updates the sidecar's end-timestamp and
//      dispatches an update event.  A hang that cannot be recorded is
//      dropped with a Failed event (failHang).
//   3. Main run loop goes idle → mainRunLoopActivity(BeforeWaiting) cancels
//      the timer.  If a hang was active, it marks the hang's record ended
//      (the sidecar and the lifecycle's flag: memory writes, no I/O) and hands
//      the hang to the watchdog thread, where finishHang() either deletes the
//      report (hang reporting off) or finalizes it as recovered, then sends
//      Ended.
//   4. If the process ends while a hang is active (a crash, SIGTERM, a normal
//      exit, a watchdog kill), the sidecar stays, and so does the report unless
//      hang reporting is off and a fatal event or a normal exit ended the
//      process (addContextualInfoToEvent, removeUnreportedHangAtExit).  The stitch decides at delivery whether the
//      hang was the cause of death.
//
// A hang follows the settings it started with. The hang-reporting setting is
// read when the hang starts, and disabling the monitor during a hang lets that
// hang finish as though it had not been: the monitor stops once it has.
//
// Sidecar files
// -------------
// A sidecar is a small mmap'd binary file (KSHangSidecar, 40 bytes), one per
// run, re-created for each hang by building it aside and renaming it into
// place.  It stores the latest end-timestamp and task
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

    // Set by watchdog_destroy on timeout.  Tells the watchdog thread to free
    // the monitor itself when it finally exits, avoiding a use-after-free if
    // destroy returns before the thread stops. That is all the thread frees:
    // no hang is in progress by then, and the run's sidecar path may belong to
    // a monitor enabled since.
    _Atomic bool selfFreeOnExit;

    // Tells a stop posted to the main thread (stopAfterHang) whether this is
    // still the monitor it was posted for, or a later one at the same address.
    uint64_t generation;

    // Protects: hang and the flags below it.
    // IMPORTANT: never hold this during I/O, report writing, or hang event
    // dispatch, because the watchdog timer fires every 250ms and must not stall.
    os_unfair_lock lock;
    KSHangState hang;

    // The hang-reporting setting when `hang` started. A hang follows the
    // settings it started with, whatever changes while it is in progress.
    bool hangReportsHangs;

    // The main thread went idle, ending `hang`, and handed it to the watchdog
    // thread, which has not finished it yet. No tick updates it or starts
    // another meanwhile.
    bool hangEnding;

    // The main thread has written `hang`'s end into it and marked its record
    // ended (the sidecar, if attached, and the lifecycle's flag). A sidecar
    // attached after this is marked ended as it is attached.
    bool hangEndPublished;

    // `hang` could not be recorded (its sidecar or its report could not be
    // written) and is followed no further: no Updated and no Ended. Ticks keep
    // seeing it active, so they do not start it again every threshold.
    bool hangFailed;

    // Disabled. No new hang starts, and the one in progress finishes as though
    // the monitor were still enabled; the monitor then stops (stopAfterHang).
    bool stopping;

    // True from the main run loop's BeforeWaiting until its next AfterWaiting.
    // A timer callback can pass its threshold check just before the main thread
    // goes idle and take the lock just after; it must not then start a hang from
    // that stale enterTime, since the previous hang may still be finishing
    // against the same run sidecar. Set inside the lock section
    // BeforeWaiting already takes; cleared without the lock, so a run loop wake
    // on the host's main thread takes no lock for it.
    _Atomic bool mainIsIdle;

    // Written by main thread (mainRunLoopActivity), read by watchdog thread
    // (watchdogTimerFired).  Relaxed ordering is fine, as this is a standalone
    // timing value with no publish/consume relationship to other fields.
    _Atomic uint64_t enterTime;

    // The app's state when the main thread woke at enterTime: what a hang starting
    // then started in. Read it later and a hang that began before the app was
    // first active, then made it active, reads as one that began after. Taken by
    // the main thread and published by mainIsIdle's release store. A tick reads
    // them only under `lock`, after checking that the main thread has neither gone
    // idle nor woken again: going idle takes `lock`, so the main thread cannot
    // reach another wake while the tick holds it.
    _Atomic uint8_t enterTransitionState;
    _Atomic bool enterDuringStartup;

    // mmap'd, or NULL. Attached and detached under `lock`, and written under it:
    // the main thread marks an ended hang in it (mainRunLoopActivity), while only
    // the watchdog thread maps, unmaps and removes it.
    KSHangSidecar *sidecar;
    // Only the watchdog thread touches this, and watchdog_destroy once that
    // thread has stopped, so it takes no lock.
    char sidecarPath[PATH_MAX];

} KSHangMonitor;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

static atomic_bool g_isEnabled = false;
static atomic_bool g_reportsHangs = false;
static atomic_bool g_exitHandlerRegistered = false;
static _Atomic uint64_t g_generation = 0;

// The monitor in use, including one disabled during a hang it is still
// finishing. Changed only under g_watchdogLock, which also orders a stop
// against a re-enable that cancels it. Atomic because it is also read without
// that lock, from any thread (isFollowingHangs) and from the crash handler,
// where a C11 atomic load is lock-free and async-signal-safe.
// Lock order: g_watchdogLock, then a monitor's lock.
static _Atomic(KSHangMonitor *) g_watchdog = NULL;
static os_unfair_lock g_watchdogLock = OS_UNFAIR_LOCK_INIT;
static KSCrash_ExceptionHandlerCallbacks g_callbacks = { 0 };

// ============================================================================
#pragma mark - Sidecar lifecycle -
// ============================================================================

static const char *monitorId(__unused void *context);

// Creates the run sidecar for `hang` at `path` and returns its mapping, or NULL.
// The file is built at "<path>.tmp" and renamed into place once every field is
// written, so a reader opening `path` finds no file or the complete sidecar,
// never one ksfu_mmap has just truncated or whose fields are not written yet.
// The mapping follows the file to its new name. This is file I/O, so it never
// runs with monitor->lock held.
static KSHangSidecar *sidecar_create(const char *path, const KSHangState *hang)
{
    char tempPath[PATH_MAX];
    if (strlcpy(tempPath, path, sizeof(tempPath)) >= sizeof(tempPath) ||
        strlcat(tempPath, ".tmp", sizeof(tempPath)) >= sizeof(tempPath)) {
        KSLOG_ERROR("Sidecar path too long: %s", path);
        return NULL;
    }

    KSHangSidecar *sc = (KSHangSidecar *)ksfu_mmap(tempPath, sizeof(KSHangSidecar));
    if (!sc) {
        KSLOG_ERROR("Failed to mmap sidecar at %s", tempPath);
        return NULL;
    }

    sc->magic = KSHANG_SIDECAR_MAGIC;
    sc->version = KSHANG_SIDECAR_CURRENT_VERSION;
    sc->recovered = false;
    sc->startTimestamp = hang->timestamp;
    sc->startRole = hang->role;
    sc->startTransitionState = hang->transitionState;
    sc->duringStartup = hang->duringStartup;
    sc->endTimestamp = hang->endTimestamp;
    sc->endRole = hang->endRole;
    sc->endTransitionState = hang->endTransitionState;

    if (rename(tempPath, path) != 0) {
        KSLOG_ERROR("Failed to publish sidecar at %s: %s", path, strerror(errno));
        ksfu_munmap(sc, sizeof(KSHangSidecar));
        unlink(tempPath);
        return NULL;
    }
    return sc;
}

static void sidecar_update(KSHangSidecar *sc, uint64_t endTimestamp, task_role_t endRole, uint8_t endTransitionState)
{
    if (!sc) {
        return;
    }
    sc->endTimestamp = endTimestamp;
    sc->endRole = endRole;
    sc->endTransitionState = endTransitionState;
}

// Detached under the lock before it is unmapped, since the main thread writes
// into it under that lock. Never called with the lock held.
static void sidecar_release(KSHangMonitor *monitor)
{
    os_unfair_lock_lock(&monitor->lock);
    KSHangSidecar *sidecar = monitor->sidecar;
    monitor->sidecar = NULL;
    os_unfair_lock_unlock(&monitor->lock);
    if (sidecar) {
        ksfu_munmap(sidecar, sizeof(KSHangSidecar));
    }
}

static void sidecar_delete(KSHangMonitor *monitor)
{
    sidecar_release(monitor);
    if (monitor->sidecarPath[0] != '\0') {
        unlink(monitor->sidecarPath);
        monitor->sidecarPath[0] = '\0';
    }
}

// ============================================================================
#pragma mark - Hang event dispatch -
// ============================================================================

// Runs on the watchdog thread, outside the monitor lock: the consumers run
// arbitrary code and the lock must never wait on them. The lifecycle's hang flag
// follows the record, not the events: it goes up when the hang is recorded
// (populateReportForCurrentHang) and comes down when the record is marked ended
// (mainRunLoopActivity, as the main thread goes idle) or removed (failHang).
static void notifyHangChange(KSHangChangeType change, uint64_t start, uint64_t now)
{
    kshang_fireHangEvent(change, start, now);
}

// The hang could not be recorded. Whatever part of it was recorded goes, since
// a reader would take half a record for the whole of one, and listeners hear it
// failed. The hang stays active, marked failed, until the main thread ends it, so
// the ticks in between neither update it nor start it again. Runs on the
// watchdog thread.
static void failHang(KSHangMonitor *monitor, const KSHangState *hang)
{
    sidecar_delete(monitor);
    kslifecycle_noteHangChange(false);
    os_unfair_lock_lock(&monitor->lock);
    monitor->hangFailed = true;
    os_unfair_lock_unlock(&monitor->lock);
    notifyHangChange(KSHangChangeTypeFailed, hang->timestamp, hang->endTimestamp);
}

// ============================================================================
#pragma mark - Report writing -
// ============================================================================

// Called on the watchdog thread when a new hang is first detected.
// Runs OUTSIDE the lock because report writing involves I/O.
static void populateReportForCurrentHang(KSHangMonitor *monitor)
{
    // Only this thread ends a hang (finishHang), so `hang` is still the monitor's
    // hang when this function returns. The main thread can only mark it ending,
    // and the hand-over waits on this thread until this function is done.
    os_unfair_lock_lock(&monitor->lock);
    KSHangState hang = monitor->hang;
    os_unfair_lock_unlock(&monitor->lock);

    if (!g_callbacks.handleWithResult || !g_callbacks.notify) {
        KSLOG_ERROR("No report pipeline; the hang is not followed");
        failHang(monitor, &hang);
        return;
    }

    // Record the hang before writing its report, which takes long enough for the
    // process to end part way through: the sidecar, then the lifecycle's flag.
    // Outside the lock: file I/O, and a call into another monitor. monitor->sidecar
    // is NULL here: every way a hang ends releases it.
    char sidecarPath[PATH_MAX] = { 0 };
    KSHangSidecar *sidecar = NULL;
    if (g_callbacks.getRunSidecarPath &&
        g_callbacks.getRunSidecarPath(monitorId(NULL), sidecarPath, sizeof(sidecarPath))) {
        sidecar = sidecar_create(sidecarPath, &hang);
    }
    if (!sidecar) {
        // Every report of the run, and the next launch, learns of the hang from its
        // sidecar. Without one the hang is not followed at all.
        KSLOG_ERROR("The hang's sidecar could not be created; the hang is not followed");
        failHang(monitor, &hang);
        return;
    }
    strlcpy(monitor->sidecarPath, sidecarPath, sizeof(monitor->sidecarPath));
    kslifecycle_noteHangChange(true);

    // The main thread may have gone idle while the sidecar was built. It marks the
    // record ended only once it can see the sidecar, so one attached after that is
    // marked here, and the flag just raised comes down again.
    os_unfair_lock_lock(&monitor->lock);
    monitor->sidecar = sidecar;
    bool endedMeanwhile = monitor->hangEndPublished;
    if (endedMeanwhile) {
        sidecar_update(sidecar, monitor->hang.endTimestamp, monitor->hang.endRole, monitor->hang.endTransitionState);
        sidecar->recovered = true;
    }
    os_unfair_lock_unlock(&monitor->lock);
    if (endedMeanwhile) {
        kslifecycle_noteHangChange(false);
    }

    // Started goes out once the hang is recorded, report and all, never before
    // the main thread is captured: a listener runs arbitrary code, and the main
    // thread can recover while it does, leaving the report a stack from after
    // the hang.

    // notify() suspends the threads, after allocating this event's context. Suspending them
    // here first would make that allocation wait forever on a malloc lock the main thread
    // holds, and keep them frozen after the writer tells its callbacks they run again.
    // Nothing the report write calls takes this monitor's lock, so the main thread may be
    // suspended holding it.

    // No offending thread: the main thread is this report's subject, but it did not
    // fault, it was observed. Naming it here makes the recrash check read it as
    // evidence that the faulting thread is already inside a handler, and a hung main
    // thread is very often hung precisely because it is writing another report. The
    // event would then be classed a recrash and rewrite that report's file in place,
    // destroying it. The recrash test is about the handler thread, and the handler
    // here is this watchdog thread, which notify() reads for itself.
    KSCrash_MonitorContext *crashContext =
        g_callbacks.notify(MACH_PORT_NULL, (KSCrash_ExceptionHandlingRequirements) { .asyncSafety = false,
                                                                                     .isFatal = false,
                                                                                     .shouldRecordAllThreads = true,
                                                                                     .shouldWriteReport = true,
                                                                                     .yieldsToReportInFlight = true });
    if (crashContext->requirements.refusedReportInFlight) {
        // A report is already being written, so this hang goes without one: the hang is
        // already active, so later ticks take the update path and never come back here.
        // The hang itself is recorded, so it is announced exactly as with a report.
        KSLOG_DEBUG("A report is already being written; this hang is reported without one");
        notifyHangChange(KSHangChangeTypeStarted, hang.timestamp, hang.endTimestamp);
        return;
    }

    // The threads are suspended now, so the main thread cannot move on while this looks.
    // A hang that ended since the tick (the sidecar's file work sits in between) would
    // leave the report a stack from after it: an idle main thread, or its next piece of
    // work. Such a hang is followed without a report, as when the app skips one.
    if (atomic_load_explicit(&monitor->mainIsIdle, memory_order_acquire) ||
        atomic_load_explicit(&monitor->enterTime, memory_order_relaxed) != hang.timestamp) {
        crashContext->requirements.shouldWriteReport = false;
    }

    KSMachineContext machineContext = { 0 };
    ksmc_getContextForThread(ksthread_main(), &machineContext, true);
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
    crashContext->mach.code = 0;
    crashContext->mach.subcode = 0;

    crashContext->exitReason.code = 0x8badf00d;

    KSCrash_ReportResult result = { 0 };
    g_callbacks.handleWithResult(crashContext, &result, false);

    if (result.skipped) {
        // The app chose no report for this event (willWriteReport). That is not a
        // failure: the hang is recorded, and is followed without a report, as when it
        // yields to a report in flight.
        KSLOG_DEBUG("The hang's report was skipped; this hang is reported without one");
        notifyHangChange(KSHangChangeTypeStarted, hang.timestamp, hang.endTimestamp);
        return;
    }
    if (result.path[0] == '\0') {
        KSLOG_ERROR("The hang's report could not be written; the hang is not followed");
        failHang(monitor, &hang);
        return;
    }

    // Attached even when the main thread has ended the hang meanwhile: finishHang
    // runs after this, on this thread, and finalizes or deletes the report by it.
    os_unfair_lock_lock(&monitor->lock);
    strlcpy(monitor->hang.reportId, result.reportId, sizeof(monitor->hang.reportId));
    strlcpy(monitor->hang.path, result.path, sizeof(monitor->hang.path));
    os_unfair_lock_unlock(&monitor->lock);

    KSLOG_INFO("Hang started (reportID: %s)", result.reportId);
    notifyHangChange(KSHangChangeTypeStarted, hang.timestamp, hang.endTimestamp);
}

static void writeUpdatedReport(KSHangMonitor *monitor)
{
    uint64_t timestampStart = 0;
    uint64_t timestampEnd = 0;

    os_unfair_lock_lock(&monitor->lock);
    if (!monitor->hang.active || monitor->hangEnding || monitor->hangFailed) {
        os_unfair_lock_unlock(&monitor->lock);
        return;
    }
    timestampStart = monitor->hang.timestamp;
    timestampEnd = monitor->hang.endTimestamp;
    sidecar_update(monitor->sidecar, timestampEnd, monitor->hang.endRole, monitor->hang.endTransitionState);
    os_unfair_lock_unlock(&monitor->lock);

    notifyHangChange(KSHangChangeTypeUpdated, timestampStart, timestampEnd);
}

// Removes the record of a hang that has ended: the report is finalized as a
// recovered hang, or deleted when the hang is not reported on its own, and the
// sidecar goes either way.
static void closeHangRecord(KSHangMonitor *monitor, const KSHangState *hang, bool reportsHangs)
{
    // Mark the hang ended before anything removes its record, and before the
    // finalize below: the hang is over, and whatever reads the record meanwhile
    // (the next launch after a SIGTERM now, a report written now) should see a
    // hang that ended, which is what it is.
    // The main thread has normally done this already, as it went idle.
    os_unfair_lock_lock(&monitor->lock);
    if (monitor->sidecar) {
        sidecar_update(monitor->sidecar, hang->endTimestamp, hang->endRole, hang->endTransitionState);
        monitor->sidecar->recovered = true;
    }
    os_unfair_lock_unlock(&monitor->lock);
    kslifecycle_noteHangChange(false);

    if (hang->path[0] == '\0') {
        sidecar_delete(monitor);
        return;
    }

    if (!reportsHangs) {
        // The report goes first: a process ending in between leaves a sidecar no
        // report points at, which the next send reclaims, rather than a report
        // with no sidecar to say its hang recovered.
        if (unlink(hang->path) != 0) {
            KSLOG_ERROR("Failed to delete hang report at %s: %s", hang->path, strerror(errno));
        }
        sidecar_delete(monitor);
        return;
    }

    sidecar_release(monitor);

    // Finalize the report now, so the stitched metadata (lifecycle stats,
    // memory pressure, device state) reflects the moment of recovery: the main
    // thread handed the hang over as it went idle, so this runs within moments
    // of it. Everything that writes or deletes this report runs on this thread,
    // so nothing else can be removing it meanwhile.
    //
    // Cost: one JSON round-trip plus a file write, and each stitch callback
    // reads its own sidecar file from disk. Typical total is ~5-10 ms for a
    // normal-sized report, on this thread rather than the host's main thread.
    if (!kscrs_finalizeReport(hang->path, hang->reportId)) {
        KSLOG_ERROR("Failed to finalize hang report %s, deleting to prevent stale stitching", hang->reportId);
        unlink(hang->path);
    }

    // Delete the run sidecar now that the hang has recovered.
    // kscrs_finalizeReport already read it, so it's no longer needed.
    // Leaving it would contaminate later crash reports from this run
    // with stale hang data.
    if (monitor->sidecarPath[0] != '\0') {
        unlink(monitor->sidecarPath);
        monitor->sidecarPath[0] = '\0';
    }
}

static void postStopAfterHang(KSHangMonitor *monitor);

// Runs on the watchdog thread, handed the hang's end by the main thread
// (mainRunLoopActivity). The hang stays active until its record is closed, so a
// fatal event meanwhile still finds its report (addContextualInfoToEvent).
static void finishHang(KSHangMonitor *monitor, uint64_t endTimestamp, task_role_t endRole, uint8_t endTransitionState)
{
    os_unfair_lock_lock(&monitor->lock);
    monitor->hang.endTimestamp = endTimestamp;
    monitor->hang.endRole = endRole;
    monitor->hang.endTransitionState = endTransitionState;
    KSHangState hang = monitor->hang;
    bool failed = monitor->hangFailed;
    bool reportsHangs = monitor->hangReportsHangs;
    os_unfair_lock_unlock(&monitor->lock);

    // A failed hang has no record left, and its events ended with Failed.
    if (!failed) {
        closeHangRecord(monitor, &hang, reportsHangs);
    }

    os_unfair_lock_lock(&monitor->lock);
    kshangstate_clear(&monitor->hang);
    monitor->hangEnding = false;
    monitor->hangEndPublished = false;
    monitor->hangFailed = false;
    bool stopping = monitor->stopping;
    os_unfair_lock_unlock(&monitor->lock);

    if (!failed) {
        KSLOG_INFO("Hang ended (reportID: %s, duration: %.3f s)", hang.reportId,
                   (double)(hang.endTimestamp - hang.timestamp) / 1e9);
        notifyHangChange(KSHangChangeTypeEnded, hang.timestamp, hang.endTimestamp);
    }

    // Disabled during this hang, which has now finished as though it had not been.
    if (stopping) {
        postStopAfterHang(monitor);
    }
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
//       If a hang was active, it marks it ending and hands it to the
//       watchdog thread, where finishHang() closes its record and sends Ended.
//

// Runs on the watchdog thread.
static void watchdogTick(KSHangMonitor *monitor, uint64_t enter);

static void watchdogTimerFired(CFRunLoopTimerRef timer, void *info)
{
    (void)timer;
    KSHangMonitor *monitor = (KSHangMonitor *)info;

    // Load enterTime exactly once, since a second load could see a newer
    // value if the main thread briefly woke between the two reads, causing
    // us to initialize the hang with the wrong start timestamp.
    watchdogTick(monitor, atomic_load_explicit(&monitor->enterTime, memory_order_relaxed));
}

// `enter` is the enterTime the tick measured against.
static void watchdogTick(KSHangMonitor *monitor, uint64_t enter)
{
    uint64_t now = ksdate_uptimeNanoseconds();
    uint64_t hangTime = now - enter;

    if (hangTime < monitor->thresholdNs) {
        return;
    }

    task_role_t currentRole = kstaskrole_current();
    uint8_t currentTransition = (uint8_t)ksapp_currentTransitionState();

    bool shouldStartNewHang = false;
    bool shouldUpdateHang = false;

    os_unfair_lock_lock(&monitor->lock);
    // The main thread went idle since `enter` was measured, or went idle and
    // woke again: either way this tick's view of it is stale.
    if (atomic_load_explicit(&monitor->mainIsIdle, memory_order_acquire) ||
        atomic_load_explicit(&monitor->enterTime, memory_order_relaxed) != enter) {
        os_unfair_lock_unlock(&monitor->lock);
        return;
    }
    // A hang being finished is over, and a disabled monitor starts no new one.
    if (monitor->hangEnding || (!monitor->hang.active && monitor->stopping)) {
        os_unfair_lock_unlock(&monitor->lock);
        return;
    }
    if (!monitor->hang.active) {
        kshangstate_init(&monitor->hang, enter, currentRole,
                         atomic_load_explicit(&monitor->enterTransitionState, memory_order_relaxed));
        monitor->hangReportsHangs = atomic_load(&g_reportsHangs);
        monitor->hangFailed = false;
        monitor->hangEndPublished = false;
        monitor->hang.duringStartup = atomic_load_explicit(&monitor->enterDuringStartup, memory_order_relaxed);
        monitor->hang.endTimestamp = now;
        monitor->hang.endRole = currentRole;
        monitor->hang.endTransitionState = currentTransition;
        shouldStartNewHang = true;
    } else {
        monitor->hang.endTimestamp = now;
        monitor->hang.endRole = currentRole;
        monitor->hang.endTransitionState = currentTransition;
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
    atomic_store_explicit(&monitor->enterTransitionState, (uint8_t)ksapp_currentTransitionState(),
                          memory_order_relaxed);
    atomic_store_explicit(&monitor->enterDuringStartup, !ksapp_hasBeenActive(), memory_order_relaxed);
    atomic_store_explicit(&monitor->enterTime, ksdate_uptimeNanoseconds(), memory_order_relaxed);
    atomic_store_explicit(&monitor->mainIsIdle, false, memory_order_release);

    CFRunLoopTimerContext timerCtx = {
        .version = 0, .info = monitor, .retain = NULL, .release = NULL, .copyDescription = NULL
    };
    monitor->watchdogTimer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + monitor->threshold,
                                                  monitor->threshold, 0, 0, watchdogTimerFired, &timerCtx);
    CFRunLoopAddTimer(monitor->watchdogRunLoop, monitor->watchdogTimer, kCFRunLoopCommonModes);
}

// Runs on the main thread.  Called for both BeforeWaiting (going idle) and
// AfterWaiting (woke up).  We always cancel the previous timer first. The
// timer lives on the watchdog run loop, but CFRunLoopTimerInvalidate is
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
        bool endsHang = false;
        CFRunLoopRef watchdogRunLoop = NULL;

        os_unfair_lock_lock(&monitor->lock);
        atomic_store_explicit(&monitor->mainIsIdle, true, memory_order_relaxed);
        if (monitor->hang.active && !monitor->hangEnding) {
            monitor->hangEnding = true;
            watchdogRunLoop = monitor->watchdogRunLoop;
            endsHang = true;
        }
        os_unfair_lock_unlock(&monitor->lock);

        if (!endsHang) {
            return;
        }

        uint64_t endTimestamp = ksdate_uptimeNanoseconds();
        task_role_t endRole = kstaskrole_current();
        uint8_t endTransitionState = (uint8_t)ksapp_currentTransitionState();

        // Mark the record ended now, not when the watchdog thread gets to it: that
        // thread can still be writing the hang's report, or in a listener, and a
        // process ending meanwhile would otherwise leave a recovered hang on disk
        // as one still in progress, which the next launch reads as a watchdog kill.
        // Memory writes into the mapped sidecar, no file I/O.
        os_unfair_lock_lock(&monitor->lock);
        monitor->hang.endTimestamp = endTimestamp;
        monitor->hang.endRole = endRole;
        monitor->hang.endTransitionState = endTransitionState;
        monitor->hangEndPublished = true;
        if (monitor->sidecar) {
            sidecar_update(monitor->sidecar, endTimestamp, endRole, endTransitionState);
            monitor->sidecar->recovered = true;
        }
        os_unfair_lock_unlock(&monitor->lock);
        kslifecycle_noteHangChange(false);

        // The watchdog thread does the rest. It is still running: the monitor is
        // destroyed only once no hang is active, and this one is until finishHang
        // clears it.
        if (watchdogRunLoop) {
            CFRunLoopPerformBlock(watchdogRunLoop, kCFRunLoopCommonModes, ^{
                finishHang(monitor, endTimestamp, endRole, endTransitionState);
            });
            CFRunLoopWakeUp(watchdogRunLoop);
        }

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

    // Read selfFreeOnExit before signaling. Once we signal, watchdog_destroy
    // may free the monitor immediately, so we must not touch it after.
    bool shouldSelfFree = atomic_load_explicit(&monitor->selfFreeOnExit, memory_order_acquire);
    dispatch_semaphore_signal(monitor->threadExitSemaphore);

    if (shouldSelfFree) {
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

    monitor->generation = atomic_fetch_add(&g_generation, 1) + 1;
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

// Call only once the monitor is stopping with no hang active (setEnabled,
// stopAfterHang): no hang is then in progress or can start, so the monitor has
// no report, sidecar or lifecycle flag of its own left to clean up.
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

    free(monitor);
}

// Runs on the main thread, posted by finishHang once the hang the monitor was
// disabled during has finished. A re-enable since then cancels it, and a monitor
// destroyed since then is not this one: `generation` tells them apart even when a
// later monitor got the same address.
static void stopAfterHang(KSHangMonitor *monitor, uint64_t generation)
{
    bool stop = false;
    os_unfair_lock_lock(&g_watchdogLock);
    if (atomic_load(&g_watchdog) == monitor && monitor->generation == generation) {
        os_unfair_lock_lock(&monitor->lock);
        stop = monitor->stopping && !monitor->hang.active;
        os_unfair_lock_unlock(&monitor->lock);
        if (stop) {
            atomic_store(&g_watchdog, NULL);
        }
    }
    os_unfair_lock_unlock(&g_watchdogLock);

    if (stop) {
        watchdog_destroy(monitor);
    }
}

// The main thread is where the observer runs, so tearing the monitor down there
// cannot race one of its callbacks. Runs on the watchdog thread.
static void postStopAfterHang(KSHangMonitor *monitor)
{
    uint64_t generation = monitor->generation;
    CFRunLoopPerformBlock(monitor->runLoop, kCFRunLoopCommonModes, ^{
        stopAfterHang(monitor, generation);
    });
    CFRunLoopWakeUp(monitor->runLoop);
}

// ============================================================================
#pragma mark - Hang event API -
// ============================================================================

// Enabled, or disabled during a hang it is still finishing: that hang is
// followed as though the monitor were enabled, which includes the crash
// pipeline's contextual-info call, made only to monitors that say they are.
static bool isFollowingHangs(void) { return atomic_load(&g_isEnabled) || atomic_load(&g_watchdog) != NULL; }

bool kshang_isEnabled(void) { return isFollowingHangs(); }

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

static const char *monitorId(__unused void *context) { return "Watchdog"; }

static KSCrashMonitorFlag monitorFlags(__unused void *context) { return KSCrashMonitorFlagNone; }

static void removeUnreportedHangAtExit(void);

static void setEnabled(bool isEnabled, __unused void *context)
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
        // A monitor disabled during a hang is still finishing it. It carries on as
        // the enabled monitor, and only stops no more.
        os_unfair_lock_lock(&g_watchdogLock);
        KSHangMonitor *finishing = atomic_load(&g_watchdog);
        if (finishing) {
            os_unfair_lock_lock(&finishing->lock);
            finishing->stopping = false;
            os_unfair_lock_unlock(&finishing->lock);
        }
        os_unfair_lock_unlock(&g_watchdogLock);
        if (finishing) {
            return;
        }

        bool expectUnregistered = false;
        if (atomic_compare_exchange_strong(&g_exitHandlerRegistered, &expectUnregistered, true)) {
            atexit(removeUnreportedHangAtExit);
        }

        KSHangMonitor *monitor = watchdog_create(CFRunLoopGetMain(), KSHANG_THRESHOLD_SECONDS);
        if (!monitor) {
            atomic_store(&g_isEnabled, false);
            return;
        }
        os_unfair_lock_lock(&g_watchdogLock);
        atomic_store(&g_watchdog, monitor);
        os_unfair_lock_unlock(&g_watchdogLock);
    } else {
        // A hang in progress finishes as though the monitor were still enabled, and
        // the monitor stops after it (finishHang). Otherwise it stops now. Either way
        // `stopping` is set first, under the lock the tick starts a hang under, so no
        // new hang starts in between.
        os_unfair_lock_lock(&g_watchdogLock);
        KSHangMonitor *monitor = atomic_load(&g_watchdog);
        bool finishesHangFirst = false;
        if (monitor) {
            os_unfair_lock_lock(&monitor->lock);
            monitor->stopping = true;
            finishesHangFirst = monitor->hang.active;
            os_unfair_lock_unlock(&monitor->lock);
            if (!finishesHangFirst) {
                atomic_store(&g_watchdog, NULL);
            }
        }
        os_unfair_lock_unlock(&g_watchdogLock);

        if (monitor && !finishesHangFirst) {
            watchdog_destroy(monitor);
        }
    }
}

static bool isEnabled(__unused void *context) { return isFollowingHangs(); }

static void monitorInit(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    g_callbacks = *callbacks;
}

/** Called by the crash handling pipeline on every enabled monitor.
 *
 * With hang reporting off, a hang is reported on its own only when it ends the
 * process, and a fatal event during the hang means it did not: its report is
 * removed. The run sidecar stays, so the fatal event's report still carries the
 * hang, and the lifecycle's flag stays, so the run's summary still says a hang
 * was in progress.
 *
 * This runs in the crash handler, so it takes no lock. unlink() is
 * async-signal-safe. A path not attached yet means no report is removed.
 */
static void addContextualInfoToEvent(struct KSCrash_MonitorContext *eventContext, __unused void *context)
{
    if (!kscexc_isLocallyFatal(eventContext->requirements)) {
        return;
    }
    KSHangMonitor *monitor = atomic_load(&g_watchdog);
    if (!monitor || !monitor->hang.active || monitor->hangReportsHangs) {
        return;
    }
    if (monitor->hang.path[0] != '\0') {
        unlink(monitor->hang.path);
    }
}

// Registered once, the first time the monitor is enabled. A normal exit is not a
// fatal event, so addContextualInfoToEvent never sees it, and the main thread does
// not go idle again to end the hang. With hang reporting off, a hang still in
// progress at exit did not end the process either: its report goes, exactly as for
// a fatal event, and the sidecar and the lifecycle's flag stay. Runs on the exiting
// thread, outside any signal handler, so it takes the monitor's lock. A path not
// attached yet (the report is still being written) means no report is removed.
static void removeUnreportedHangAtExit(void)
{
    // Under g_watchdogLock: a disable on another thread can otherwise free the
    // monitor between loading it and taking its lock.
    char path[PATH_MAX] = { 0 };
    os_unfair_lock_lock(&g_watchdogLock);
    KSHangMonitor *monitor = atomic_load(&g_watchdog);
    if (monitor) {
        os_unfair_lock_lock(&monitor->lock);
        if (monitor->hang.active && !monitor->hangReportsHangs) {
            strlcpy(path, monitor->hang.path, sizeof(path));
        }
        os_unfair_lock_unlock(&monitor->lock);
    }
    os_unfair_lock_unlock(&g_watchdogLock);
    if (path[0] != '\0') {
        unlink(path);
    }
}

void kscm_watchdog_setReportsHangs(bool enabled) { atomic_store(&g_reportsHangs, enabled); }

KSCrashSidecarRunPathForRunIDProviderFunc kscm_watchdog_runSidecarPathForRunIDProvider(void)
{
    return g_callbacks.getRunSidecarPathForRunID;
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
// Runs what a normal exit runs, without exiting.
void kscm_watchdog_testcode_runExitHandler(void)
{
    removeUnreportedHangAtExit();
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
// Whether a monitor is still running: enabled, or disabled during a hang it has
// not finished yet.
bool kscm_watchdog_testcode_isRunning(void)
{
    os_unfair_lock_lock(&g_watchdogLock);
    bool running = atomic_load(&g_watchdog) != NULL;
    os_unfair_lock_unlock(&g_watchdogLock);
    return running;
}

__attribute__((unused))  // For tests. Declared as extern in TestCase
// Replays a tick that measured the main thread as busy since long ago, then
// took the lock only after the main thread went idle (and, with
// `mainWokeAgain`, woke again). Returns whether that tick started a hang. Call
// on the main thread while the monitor is enabled.
bool kscm_watchdog_testcode_staleTickStartsHang(bool mainWokeAgain)
{
    KSHangMonitor *monitor = atomic_load(&g_watchdog);
    if (monitor == NULL) {
        return false;
    }
    // Going idle first invalidates the real timer, so no real tick interleaves.
    mainRunLoopActivity(NULL, kCFRunLoopBeforeWaiting, monitor);
    atomic_store_explicit(&monitor->enterTime, 0, memory_order_relaxed);
    uint64_t enter = atomic_load_explicit(&monitor->enterTime, memory_order_relaxed);
    if (mainWokeAgain) {
        mainRunLoopActivity(NULL, kCFRunLoopAfterWaiting, monitor);
    }
    watchdogTick(monitor, enter);

    // Only a hang that starts at `enter` is this tick's: a real hang the test
    // body was already in can still be active here, being finished.
    os_unfair_lock_lock(&monitor->lock);
    bool started = monitor->hang.active && monitor->hang.timestamp == enter;
    os_unfair_lock_unlock(&monitor->lock);

    if (!mainWokeAgain) {
        mainRunLoopActivity(NULL, kCFRunLoopAfterWaiting, monitor);
    }
    return started;
}

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
        api.createStitchedReport = kscm_watchdog_createStitchedReport;
        // Watchdog is last among the sidecar layers so its fatality resolution on its own
        // reports wins; only the corpse final-pass layer sits above, and it never touches
        // watchdog reports.
        api.priority = KSCrashStitchPriorityWatchdog;
    }
    return &api;
}
