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
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
#pragma mark - Sidecar Struct -
// ============================================================================

#define KSLIFECYCLE_MAGIC ((int32_t)0x6B736C63)  // 'kslc'

static const uint8_t KSCrash_Lifecycle_CurrentVersion = 1;

/** mmap'd struct written to a run sidecar per process.
 *  No pointers — all data is inline so it survives across launches.
 *  Fixed-width types only so the on-disk layout is stable.
 */
typedef struct {
    int32_t magic;
    uint8_t version;

    uint8_t cleanShutdown;
    uint8_t applicationIsActive;
    uint8_t applicationIsInForeground;

    // Per-launch durations in nanoseconds (monotonic)
    uint64_t activeDurationSinceLaunchNs;
    uint64_t backgroundDurationSinceLaunchNs;
    int32_t sessionsSinceLaunch;

    // Transition timestamp in nanoseconds (monotonic)
    uint64_t appStateTransitionTimeNs;

    // Cumulative durations in nanoseconds (carried forward from previous runs)
    uint64_t activeDurationSinceLastCrashNs;
    uint64_t backgroundDurationSinceLastCrashNs;
    int32_t launchesSinceLastCrash;
    int32_t sessionsSinceLastCrash;

    uint8_t crashedLastLaunch;
    uint8_t transitionState;  // KSCrashAppTransitionState at last update
    uint8_t _pad[2];
} KSCrash_LifecycleData;

_Static_assert(sizeof(KSCrash_LifecycleData) == 72, "KSCrash_LifecycleData size changed — bump version");

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

    /** If true, the application crashed on the previous launch. */
    bool crashedLastLaunch;

    /** Timestamp for when the app state was last changed (active<->inactive,
     * background<->foreground). In seconds (derived from monotonic nanoseconds). */
    double appStateTransitionTime;

    /** If true, the application is currently active. */
    bool applicationIsActive;

    /** If true, the application is currently in the foreground. */
    bool applicationIsInForeground;

} KSCrash_AppState;

/** Read-only access into the current state.
 *  Computes values on the fly from the mmap'd sidecar.
 *  Returns zeroed defaults if the monitor is not enabled.
 */
const KSCrash_AppState *kscrashstate_currentState(void);

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

/** Access the Lifecycle Monitor API.
 */
KSCrashMonitorAPI *kscm_lifecycle_getAPI(void);

/** Stitch lifecycle sidecar data into a report at delivery time.
 *  Reads the binary struct, converts nanosecond durations to seconds,
 *  and produces the application_stats JSON section.
 */
char *kscm_lifecycle_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope,
                                  void *context);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashMonitor_Lifecycle_h
