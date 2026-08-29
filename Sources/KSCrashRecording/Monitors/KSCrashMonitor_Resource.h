//
//  KSCrashMonitor_Resource.h
//
//  Created by Alexander Cohen on 2026-03-03.
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

/* Resource monitor — collects memory, battery, CPU, thermal, and thread
 * data into an mmap'd run sidecar.  Optionally generates non-fatal
 * CPU exception reports when sustained usage crosses warning/critical
 * thresholds (see kscm_resource_setReportsCPUExceptions).
 *
 * Data is available at runtime via ksresource_getSnapshot() and from any
 * previous run via ksresource_getSnapshotForRunID().  At report delivery
 * time the sidecar is stitched into report.system automatically.
 */

#ifndef KSCrashMonitor_Resource_h
#define KSCrashMonitor_Resource_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "KSCrashMonitorAPI.h"
#include "KSCrashNamespace.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
#pragma mark - Sidecar Struct -
// ============================================================================

/** Battery charging state — mirrors UIDeviceBatteryState values. */
typedef enum {
    KSCrashBatteryStateUnknown = 0,
    KSCrashBatteryStateUnplugged = 1,
    KSCrashBatteryStateCharging = 2,
    KSCrashBatteryStateFull = 3,
} KSCrashBatteryState;

/** Battery level at or below which an unplugged device is considered
 *  a low-battery termination candidate (percent, 0–100). */
#define KSCRASH_BATTERY_LEVEL_CRITICAL 1

#define KSRESOURCE_MAGIC ((int32_t)'ksrs')

static const uint8_t KSCrash_Resource_CurrentVersion = 2;

/** On-disk size of each KSCrash_ResourceData version. A reader must accept a
 *  file of at least its declared version's size; fields the version predates
 *  read as zero. */
#define KSCrash_Resource_V1Size ((size_t)112)
#define KSCrash_Resource_V2Size ((size_t)136)

/** Resource snapshot persisted via mmap to RunSidecars/<runID>/Resource.ksscr.
 *
 *  Natural alignment — no packed attribute, no explicit padding.
 *  All Apple targets (including legacy 32-bit) naturally align up to
 *  64-bit values, so the layout is stable across architectures.
 *  Fixed-width types only — no pointers.
 *
 *  Versioning: new fields are only ever appended at the end, so every older
 *  version's layout is a strict prefix of the current one. A version boundary
 *  comment below marks where each version's fields start.
 *
 *  Version history:
 *    1: original layout, KSCrash_Resource_V1Size bytes
 *       (through cpuWallTimeInWindowNs)
 *    2: adds system-wide memory (systemMemoryRemaining, systemMemoryLimit,
 *       memoryHeadroom), KSCrash_Resource_V2Size bytes
 */
typedef struct {
    int32_t magic;

    uint8_t version;
    uint8_t memoryPressure;  // KSCrashAppMemoryState
    uint8_t memoryLevel;     // KSCrashAppMemoryState

    // Memory (from KSCrashAppMemoryTracker)
    uint64_t memoryFootprint;  // bytes used by app
    uint64_t memoryRemaining;  // bytes until limit
    uint64_t memoryLimit;      // footprint + remaining

    // CPU (from KSCrashCPUTracker)
    uint16_t cpuUsageUser;           // user-space permil of one core: 0–N*1000
    uint16_t cpuUsageSystem;         // kernel-space permil of one core: 0–N*1000
    uint16_t cpuAverageUsagePermil;  // sliding-window average permil of total capacity
    uint8_t cpuCoreCount;            // active CPU cores (refreshed each tracker poll)
    uint8_t cpuState;                // KSCrashCPUState: 0=normal, 1=warning, 2=critical

    // Threads
    uint16_t threadCount;  // process thread count

    // Battery
    uint8_t batteryLevel;  // 0–100, or 255 if unavailable
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

    // ---- Version 2 fields start here ----

    // System-wide memory (from KSCrashAppMemoryTracker)
    uint64_t systemMemoryRemaining;  // available bytes device-wide (free + cached files)
    uint64_t systemMemoryLimit;      // physical memory
    uint8_t memoryHeadroom;          // KSCrashAppMemoryState
} KSCrash_ResourceData;

_Static_assert(sizeof(KSCrash_ResourceData) == KSCrash_Resource_V2Size,
               "KSCrash_ResourceData size changed; bump version and add a size constant");

// ============================================================================
#pragma mark - Public Snapshot API -
// ============================================================================

/** Copies the latest resource snapshot into *outData.
 *  NOT async-signal-safe — call only from normal (non-signal) context.
 *  Returns false if unavailable.
 */
bool ksresource_getSnapshot(KSCrash_ResourceData *outData);

/** Reads a resource snapshot from a specific run's sidecar file.
 *  Use with kscrash_getRunID() for current run or kscrash_getLastRunID() for previous.
 *  Returns false if the run ID has no valid sidecar or data fails validation.
 */
bool ksresource_getSnapshotForRunID(const char *runID, KSCrash_ResourceData *outData);

/** Reads a resource snapshot from a sidecar file at any supported version.
 *  Fields newer than the file's declared version read as zero.
 *  Returns false if the file is missing, invalid, or short for its version.
 */
bool ksresource_readSnapshotFromPath(const char *path, KSCrash_ResourceData *outData);

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

/** Access the Resource Monitor API. */
KSCrashMonitorAPI *kscm_resource_getAPI(void);

/** Enable or disable non-fatal CPU exception reports.
 *  When enabled, an upward state transition (e.g. normal → warning)
 *  generates a report with all thread stacks.
 */
void kscm_resource_setReportsCPUExceptions(bool enabled);

/** Stitch resource sidecar data into a report at delivery time.
 *
 *  See KSCrashMonitorAPI.h createStitchedReport for the full contract.
 */
CFDictionaryRef kscm_resource_createStitchedReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                                   KSCrashSidecarScope scope, void *context);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashMonitor_Resource_h
