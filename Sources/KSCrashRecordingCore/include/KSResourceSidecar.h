//
//  KSResourceSidecar.h
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

/* The Resource monitor's run sidecar: memory, CPU, battery, thermal and thread
 * state as last sampled, at RunSidecars/<runID>/Resource.ksscr.
 *
 * Natural alignment, no packed attribute beyond the header, no explicit
 * padding. All Apple targets (including legacy 32-bit) naturally align up to
 * 64-bit values, so the layout is stable across architectures.
 *
 * Version history:
 *   1: original layout (through cpuWallTimeInWindowNs)
 *   2: adds system-wide memory (systemMemoryRemaining, systemMemoryLimit,
 *      memoryHeadroom)
 *
 * See KSSidecarFormat.h for the format every sidecar shares.
 */

#ifndef HDR_KSResourceSidecar_h
#define HDR_KSResourceSidecar_h

#include <stddef.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"
#include "KSSidecarFormat.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Battery charging state, with the values of UIDeviceBatteryState. */
typedef enum {
    KSCrashBatteryStateUnknown = 0,
    KSCrashBatteryStateUnplugged = 1,
    KSCrashBatteryStateCharging = 2,
    KSCrashBatteryStateFull = 3,
} KSCrashBatteryState;

#define KSRESOURCE_MAGIC ((int32_t)'ksrs')

#define KSCrash_Resource_V1Size ((size_t)112)
#define KSCrash_Resource_V2Size ((size_t)136)
#define KSCrash_Resource_CurrentVersion ((uint8_t)2)

typedef struct {
    KSSidecarHeader header;

    uint8_t memoryPressure;  // KSCrashAppMemoryState
    uint8_t memoryLevel;     // KSCrashAppMemoryState

    // Memory (from KSCrashAppMemoryTracker)
    uint64_t memoryFootprint;  // bytes used by app
    uint64_t memoryRemaining;  // bytes until limit
    uint64_t memoryLimit;      // footprint + remaining

    // CPU (from KSCrashCPUTracker)
    uint16_t cpuUsageUser;           // user-space permil of one core: 0 to N*1000
    uint16_t cpuUsageSystem;         // kernel-space permil of one core: 0 to N*1000
    uint16_t cpuAverageUsagePermil;  // sliding-window average permil of total capacity
    uint8_t cpuCoreCount;            // active CPU cores (refreshed each tracker poll)
    uint8_t cpuState;                // KSCrashCPUState: 0=normal, 1=warning, 2=critical

    // Threads
    uint16_t threadCount;  // process thread count

    // Battery
    uint8_t batteryLevel;  // 0 to 100, or 255 if unavailable
    uint8_t batteryState;  // KSCrashBatteryState
    uint8_t lowPowerMode;  // 0 or 1

    // Thermal
    uint8_t thermalState;  // 0=nominal, 1=fair, 2=serious, 3=critical

    // Data Protection
    uint8_t dataProtectionActive;  // 1 = protected data available (device unlocked)

    // Last-update timestamps (monotonic uptime in nanoseconds).
    // Used to determine which resource area changed most recently before a crash.
    uint64_t memoryUpdatedAtNs;
    uint64_t cpuUpdatedAtNs;
    uint64_t batteryUpdatedAtNs;
    uint64_t lowPowerUpdatedAtNs;
    uint64_t thermalUpdatedAtNs;
    uint64_t dataProtectionUpdatedAtNs;

    // CPU time accumulated in the active threshold window (nanoseconds).
    // Populated only when cpuState > Normal.
    uint64_t cpuTimeInWindowNs;
    uint64_t cpuWallTimeInWindowNs;

    // --- v2 ---

    // System-wide memory (from KSCrashAppMemoryTracker)
    uint64_t systemMemoryRemaining;  // available bytes device-wide (free + cached files)
    uint64_t systemMemoryLimit;      // physical memory
    uint8_t memoryHeadroom;          // KSCrashAppMemoryState
} KSCrash_ResourceData;

KSSIDECAR_ASSERT_LAYOUT(KSCrash_ResourceData, KSCrash_Resource_V2Size);
KSSIDECAR_ASSERT_VERSION_START(KSCrash_ResourceData, systemMemoryRemaining, KSCrash_Resource_V1Size);

/** Reads a resource sidecar file. See kssidecar_read for the verdicts.
 *
 * @param path The file to read.
 * @param out The struct to fill; fields newer than the file's version read as
 *            zero, and the whole struct is zeroed on anything but OK.
 *
 * @return OK, Unrecoverable (no later read gets further), or Failure (the I/O
 *         failed, and a later read may get past it).
 */
KSCrashSidecarReadResult kssidecar_readResource(const char *path, KSCrash_ResourceData *out);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSResourceSidecar_h
