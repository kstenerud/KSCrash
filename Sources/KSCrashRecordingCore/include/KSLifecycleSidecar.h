//
//  KSLifecycleSidecar.h
//
//  Created by Alexander Cohen on 2026-09-28.
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

/* The Lifecycle monitor's run sidecar: the app's lifecycle over one run.
 *
 * All durations are nanoseconds of clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW).
 * See KSSidecarFormat.h for the format every sidecar shares.
 */

#ifndef HDR_KSLifecycleSidecar_h
#define HDR_KSLifecycleSidecar_h

#include <stddef.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"
#include "KSSidecarFormat.h"
#include "KSSystemCapabilities.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Kind of host process a run belongs to. Stored by value in the lifecycle
 *  sidecar and written to the run summary wire format as a string. */
typedef enum {
    KSCrashRunSummaryHostKindApp = 0,
    KSCrashRunSummaryHostKindExtension,
    KSCrashRunSummaryHostKindXCTest,
    KSCrashRunSummaryHostKindOther,
} KSCrashRunSummaryHostKind;

#define KSLIFECYCLE_MAGIC ((int32_t)'kslc')

#define KSCrash_Lifecycle_V1Size ((size_t)88)
#define KSCrash_Lifecycle_V2Size ((size_t)104)
#define KSCrash_Lifecycle_V3Size ((size_t)112)
#define KSCrash_Lifecycle_CurrentVersion ((uint8_t)3)

/** Fields are grouped by alignment (8-byte, 4-byte, 1-byte) to keep padding
 *  small. There are two holes: bytes 85 to 88 after hangActive (v2's fields
 *  start at 88, right after it), and the tail after v3 (106 to 112).
 */
typedef struct {
    KSSidecarHeader header;

    uint8_t cleanExit;
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

    // 4-byte fields grouped together, no padding between them or before/after.
    int32_t sessionsSinceLaunch;
    int32_t launchesSinceLastCrash;
    int32_t sessionsSinceLastCrash;
    int32_t taskRole;  // task_role_t, updated by heartbeat and on lifecycle events

    uint8_t crashedLastLaunch KSCRASH_DEPRECATED("Use ksruncontext_previousRunContext()->terminationReason");
    uint8_t transitionState;    // KSCrashAppTransitionState at last update
    uint8_t monitorHandlerRan;  // true if a crash handler ran (distinguishes crash from OS kill)
    uint8_t userPerceptible;    // true if the user could perceive the app as part of their
                                // experience (e.g. active, launching, or even tapping the icon
                                // while still technically backgrounded)
    uint8_t hangActive;         // true while the watchdog is tracking an active hang;
                                // if still true on next launch, the app was killed during a hang

    // --- v2 ---
    //
    // v2 adds the four slots below. They are reserved: nothing reads or writes
    // them. They keep the layout from shifting, and a later per-run field can
    // take one.
    uint32_t perceptibleSessionsSinceLaunch_UNUSED;
    uint32_t imperceptibleSessionsSinceLaunch_UNUSED;
    uint32_t distinctPerceptibleUserCount_UNUSED;
    uint32_t distinctImperceptibleUserCount_UNUSED;

    // --- v3 ---
    //
    // Kind of host (app / extension / xctest / other) captured at sidecar
    // creation. Recorded per-run so the previous run's summary carries the
    // *producer's* host kind when a different process type flushes it,
    // which matters when app and extension share one KSCrash install dir.
    // Values match `KSCrashRunSummaryHostKind`. A v1 or v2 file reads 0 here,
    // which is why KSCrashRunSummaryHostKindApp must stay 0.
    uint8_t hostKind;

    // Reserved, like the v2 slots.
    uint8_t perceptibleSessionPending_UNUSED;
} KSCrash_LifecycleData;

KSSIDECAR_ASSERT_LAYOUT(KSCrash_LifecycleData, KSCrash_Lifecycle_V3Size);
KSSIDECAR_ASSERT_VERSION_START(KSCrash_LifecycleData, perceptibleSessionsSinceLaunch_UNUSED, KSCrash_Lifecycle_V1Size);
KSSIDECAR_ASSERT_VERSION_START(KSCrash_LifecycleData, hostKind, KSCrash_Lifecycle_V2Size);

/** Reads a lifecycle sidecar file. See kssidecar_read for the verdicts.
 *
 * @param path The file to read.
 * @param out The struct to fill; fields newer than the file's version read as
 *            zero, and the whole struct is zeroed on anything but OK.
 *
 * @return OK, Unrecoverable (no later read gets further), or Failure (the I/O
 *         failed, and a later read may get past it).
 */
KSCrashSidecarReadResult kssidecar_readLifecycle(const char *path, KSCrash_LifecycleData *out);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSLifecycleSidecar_h
