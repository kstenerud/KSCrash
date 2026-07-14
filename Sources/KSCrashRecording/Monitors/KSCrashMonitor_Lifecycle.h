//
//  KSCrashMonitor_Lifecycle.h
//
//  Created by Alexander Cohen on 2026-02-26.
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

/* Lifecycle monitor — tracks app lifecycle data in an mmap'd run sidecar.
 *
 * Replaces the old CrashState.json approach with a fixed-layout struct
 * that is flushed to disk by the kernel. The "cleanShutdown" flag defaults
 * to false; clean exit paths set it true. On next launch, cleanShutdown==false
 * means the previous run ended abnormally.
 *
 * All durations are stored as uint64_t nanoseconds from
 * clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW). Converted to seconds only
 * at stitch time and in kscrashstate_currentState().
 */

#ifndef HDR_KSCrashMonitor_Lifecycle_h
#define HDR_KSCrashMonitor_Lifecycle_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "KSCrashAppTransitionState.h"
#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"
#include "KSSystemCapabilities.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
#pragma mark - Sidecar Struct -
// ============================================================================

#define KSLIFECYCLE_MAGIC ((int32_t)'kslc')

static const uint8_t KSCrash_Lifecycle_CurrentVersion = 4;

static inline double kslifecycle_nsToSeconds(uint64_t ns) { return (double)ns / 1000000000.0; }

/** Convert a CLOCK_MONOTONIC_RAW nanosecond timestamp to unix epoch
 *  milliseconds using the run's anchor pair (@c wallClockAtStartNs and
 *  @c monotonicAtStartNs, captured together at sidecar creation). Monotonic
 *  time is drift-free, so this stays correct across wall-clock jumps. Any
 *  event stamped before the anchor clamps to the anchor time.
 */
static inline int64_t kslifecycle_epochMsFromMonotonicNs(uint64_t eventMonoNs, uint64_t wallClockAtStartNs,
                                                         uint64_t monotonicAtStartNs)
{
    uint64_t elapsedNs = eventMonoNs > monotonicAtStartNs ? eventMonoNs - monotonicAtStartNs : 0;
    return (int64_t)((wallClockAtStartNs + elapsedNs) / 1000000ULL);
}

/** mmap'd struct written to a run sidecar per process.
 *  No pointers — all data is inline so it survives across launches.
 *  Fixed-width types only so the on-disk layout is stable.
 *
 *  Fields are ordered by alignment (8-byte, 4-byte, 1-byte) so there
 *  is no implicit compiler padding anywhere in the struct.
 */
typedef struct {
    int32_t magic;
    uint8_t version;

    uint8_t cleanShutdown;
    uint8_t applicationIsActive;
    uint8_t applicationIsInForeground;

    // Durations in nanoseconds (monotonic). 8-byte aligned fields grouped together.
    uint64_t activeDurationSinceLaunchNs;
    uint64_t backgroundDurationSinceLaunchNs;
    uint64_t appStateTransitionTimeNs;
    uint64_t activeDurationSinceLastCrashNs;
    uint64_t backgroundDurationSinceLastCrashNs;

    // Reference pair captured once at sidecar creation, used to convert any
    // CLOCK_MONOTONIC_RAW timestamp to a unix epoch value:
    //   wallNs = wallClockAtStartNs + (monotonicNs - monotonicAtStartNs)
    uint64_t wallClockAtStartNs;  // unix epoch nanoseconds at sidecar creation
    uint64_t monotonicAtStartNs;  // CLOCK_MONOTONIC_RAW nanoseconds at sidecar creation

    // 4-byte fields grouped together — no padding between them or before/after.
    int32_t sessionsSinceLaunch;
    int32_t launchesSinceLastCrash;
    int32_t sessionsSinceLastCrash;
    int32_t taskRole;  // task_role_t — updated by heartbeat and on lifecycle events

    uint8_t crashedLastLaunch KSCRASH_DEPRECATED("Use ksruncontext_previousRunContext()->terminationReason");
    uint8_t transitionState;  // KSCrashAppTransitionState at last update
    uint8_t fatalReported;    // true if a crash handler ran (distinguishes crash from OS kill)
    uint8_t userPerceptible;  // true if the user could perceive the app as part of their
                              // experience (e.g. active, launching, or even tapping the icon
                              // while still technically backgrounded)
    uint8_t hangInProgress;   // true while the watchdog is tracking an active hang;
                              // if still true on next launch, the app was killed during a hang

    // --- v2 additions ---
    //
    // Added in KSCrash_Lifecycle_CurrentVersion=2. New fields must only be
    // APPENDED (never reordered or inserted above) so that v1 sidecar files
    // (shorter) can be read into this struct with the trailing fields left
    // zero-filled. kslifecycle_readData tolerates short reads to enable this.
    //
    // Per-run session counts split by user perceptibility, consumed by the
    // RunSummary pipeline. These are independent of `sessionsSinceLaunch`
    // above, which keeps its historical "launch + foreground resume" meaning
    // (backgrounding bumps imperceptible here but never the public counter),
    // so the two are NOT related by a sum invariant.
    uint32_t perceptibleSessionsSinceLaunch;
    uint32_t imperceptibleSessionsSinceLaunch;

    // Counts of distinct user IDs observed in each perceptibility bucket
    // during this run. Distinctness is tracked in-memory (lost on crash);
    // only the counts are persisted. See kscm_lifecycle_observeUser.
    uint32_t distinctPerceptibleUserCount;
    uint32_t distinctImperceptibleUserCount;

    // --- v3 additions ---
    //
    // Kind of host (app / extension / xctest / other) captured at sidecar
    // creation. Recorded per-run so the previous run's summary carries the
    // *producer's* host kind when a different process type flushes it —
    // important when app and extension share one KSCrash install dir.
    // Values match `KSCrashRunSummaryHostKind` (0=app, 1=extension,
    // 2=xctest, 3=other). v2 sidecars short-read to 0 = app.
    uint8_t hostKind;

    // Per-run: a perceptible session is owed but not yet counted. Set at
    // launch and on entering background; cleared when the app first becomes
    // perceptible. See countPerceptibleSessionIfPending.
    uint8_t perceptibleSessionPending;

    // --- v4 additions ---
    //
    // The session_id (UUID string) of the session currently open, restamped
    // on each session begin (a perceptible foreground reach or an
    // imperceptible background entry). Empty until the first session begins.
    // Read at report stitch time and emitted as `session_id`, so a crash
    // report references its session in the growable session log with no
    // crash-time work.
    //
    // Stored double-buffered so a crash mid-`ksid_generate` cannot leave a
    // hybrid old/new UUID on disk. `currentSessionIDSlot` selects which of
    // `currentSessionIDs[0]` or `currentSessionIDs[1]` holds the live UUID
    // string; writers fill the *inactive* slot fully and then flip the
    // one-byte selector in a single write, so the reader always keys off a
    // slot that isn't being touched. See `beginSessionLocked` /
    // `kslifecycle_currentSessionIDSnapshot`.
    //
    // A selector value of 0 or 1 addresses a slot; any other value means
    // "no session written yet" (a fresh sidecar zero-fills to slot 0 whose
    // bytes are also all zero, so first-byte-nul is the only real signal).
    uint8_t currentSessionIDSlot;
    char currentSessionIDs[2][37];  // slot 0, slot 1 — see comment above
} KSCrash_LifecycleData;

_Static_assert(sizeof(KSCrash_LifecycleData) == 184, "KSCrash_LifecycleData size changed — bump version");

/** Return a pointer to the null-terminated session_id string in @c sc, or
 *  NULL if no session has been recorded yet. The caller must ensure @c sc
 *  is a stable snapshot — either loaded from a disk sidecar file (frozen)
 *  or accessed under @c g_sidecarLock — so the slot selector cannot
 *  advance while the string is being read. The double-buffered layout
 *  guarantees that whichever slot the selector points at is not the one a
 *  writer would be currently touching, so the string is not torn even if
 *  a crash mid-`ksid_generate` was the cause of the snapshot.
 */
static inline const char *kslifecycle_currentSessionIDSnapshot(const KSCrash_LifecycleData *sc)
{
    uint8_t slot = sc->currentSessionIDSlot;
    if (slot > 1) {
        return NULL;
    }
    const char *bytes = sc->currentSessionIDs[slot];
    return bytes[0] == '\0' ? NULL : bytes;
}

// ============================================================================
#pragma mark - Public State (computed from sidecar) -
// ============================================================================

typedef struct {
    /** Total active time elapsed since the last crash. */
    double activeDurationSinceLastCrash;

    /** Total time backgrounded elapsed since the last crash. */
    double backgroundDurationSinceLastCrash;

    /** Number of app launches since the last crash. */
    int launchesSinceLastCrash;

    /** Number of sessions (launch, resume from suspend) since last crash. */
    int sessionsSinceLastCrash;

    /** Total active time elapsed since launch. */
    double activeDurationSinceLaunch;

    /** Total time backgrounded elapsed since launch. */
    double backgroundDurationSinceLaunch;

    /** Number of sessions (launch, resume from suspend) since app launch. */
    int sessionsSinceLaunch;

    /** If true, the application crashed on the previous launch.
     *  @deprecated Use ksruncontext_previousRunContext()->terminationReason from the Termination monitor instead. */
    bool crashedLastLaunch KSCRASH_DEPRECATED("Use ksruncontext_previousRunContext()->terminationReason");

    /** Timestamp for when the app state was last changed (active<->inactive,
     * background<->foreground). In seconds (derived from monotonic nanoseconds). */
    double appStateTransitionTime;

    /** If true, the application is currently active. */
    bool applicationIsActive;

    /** If true, the application is currently in the foreground. */
    bool applicationIsInForeground;

} KSCrash_AppState;

/** Read-only access into the current state.
 *  @deprecated Use kscrashstate_lifecycleAppState() instead.
 */
const KSCrash_AppState *kscrashstate_currentState(void) KSCRASH_DEPRECATED("Use kscrashstate_lifecycleAppState()");

/** Snapshot the current app state.
 *  Computes values on the fly from the mmap'd sidecar.
 *  Returns zeroed defaults if the monitor is not enabled.
 */
KSCrash_AppState kscrashstate_lifecycleAppState(void);

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

/** Read and validate a KSCrash_LifecycleData struct from a file.
 *  Returns true if the struct was read and passed magic/version checks.
 */
bool kslifecycle_readData(const char *path, KSCrash_LifecycleData *out);

/** Read a lifecycle snapshot from a specific run's sidecar file.
 *  Returns false if the run ID has no valid sidecar or data fails validation.
 */
bool kslifecycle_getSnapshotForRunID(const char *runID, KSCrash_LifecycleData *outData);

/** Returns the most recently observed app transition state.
 *  Lock-free (atomic load). Safe to call from any thread.
 */
KSCrashAppTransitionState kslifecycle_currentTransitionState(void);

/** Observe that the given user ID is active right now.
 *
 *  The monitor maintains distinct-user counts, split by the current
 *  perceptibility state, and persists them into the Lifecycle sidecar as
 *  `distinctPerceptibleUserCount` / `distinctImperceptibleUserCount`.
 *  Distinctness tracking itself is in-memory only; the counts at crash
 *  time are what survive.
 *
 *  Pass NULL or an empty string to record no user. No-op before the
 *  monitor is enabled.
 *
 *  Called from `-[KSCrash setUserID:]` on every user change, and
 *  internally whenever a perceptibility transition reveals the current
 *  user in a new bucket.
 */
void kscm_lifecycle_observeUser(const char *userID);

/** Access the Lifecycle Monitor API.
 */
KSCrashMonitorAPI *kscm_lifecycle_getAPI(void);

/** Stitch lifecycle sidecar data into a report at delivery time.
 *  Reads the binary struct, converts nanosecond durations to seconds,
 *  and produces the application_stats JSON section.
 *
 *  See KSCrashMonitorAPI.h createStitchedReport for the full contract.
 */
CFDictionaryRef kscm_lifecycle_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                    KSCrashSidecarScope scope, void *context);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashMonitor_Lifecycle_h
