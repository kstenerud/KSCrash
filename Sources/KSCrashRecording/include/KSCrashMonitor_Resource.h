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

/* Passive resource monitor — collects memory, battery, CPU, thermal, and
 * thread data into an mmap'd run sidecar.  Never generates crash reports.
 *
 * Data is available at runtime via ksresource_getSnapshot() and from any
 * previous run via ksresource_getSnapshotForRunID().  At report delivery
 * time the sidecar is stitched into report.system automatically.
 */

#ifndef KSCrashMonitor_Resource_h
#define KSCrashMonitor_Resource_h

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

#define KSRESOURCE_MAGIC ((int32_t)'ksrs')

static const uint8_t KSCrash_Resource_CurrentVersion = 1;

/** Resource snapshot persisted via mmap to RunSidecars/<runID>/Resource.ksscr.
 *
 *  Explicit padding ensures natural alignment for all fields without
 *  relying on __attribute__((packed)).
 *  Fixed-width types only — no pointers.
 */
typedef struct {
    int32_t magic;

    uint8_t version;
    uint8_t memoryPressure;  // KSCrashAppMemoryState
    uint8_t memoryLevel;     // KSCrashAppMemoryState
    uint8_t _pad0;           // align to 8-byte boundary

    // Memory (from KSCrashAppMemoryTracker)
    uint64_t memoryFootprint;  // bytes used by app
    uint64_t memoryRemaining;  // bytes until limit
    uint64_t memoryLimit;      // footprint + remaining

    // CPU (from proc_pidinfo PROC_PIDTASKINFO, polled)
    uint16_t cpuUsageUser;    // user-space permil of one core: 0–N*1000
    uint16_t cpuUsageSystem;  // kernel-space permil of one core: 0–N*1000

    // Threads
    uint16_t threadCount;  // process thread count

    // Battery
    uint8_t batteryLevel;  // 0–100, or 255 if unavailable
    uint8_t batteryState;  // 0=unknown, 1=unplugged, 2=charging, 3=full
    uint8_t lowPowerMode;  // 0 or 1

    uint8_t cpuCoreCount;  // active CPU cores (set once at enable time)

    // Thermal
    uint8_t thermalState;  // 0=nominal, 1=fair, 2=serious, 3=critical

    // Data Protection
    uint8_t dataProtectionActive;  // 1 = protected data available (device unlocked)

    uint8_t _pad1[4];  // align to 8-byte boundary for timestamps

    // Last-update timestamps (monotonic uptime in nanoseconds).
    // Used to determine which resource area changed most recently before a crash.
    uint64_t memoryUpdatedAtNs;
    uint64_t cpuUpdatedAtNs;
    uint64_t batteryUpdatedAtNs;
    uint64_t lowPowerUpdatedAtNs;
    uint64_t thermalUpdatedAtNs;
    uint64_t dataProtectionUpdatedAtNs;

    uint8_t _reserved[32];
} KSCrash_ResourceData;

_Static_assert(sizeof(KSCrash_ResourceData) == 128, "KSCrash_ResourceData size changed — bump version");

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

// ============================================================================
#pragma mark - Monitor API -
// ============================================================================

/** Access the Resource Monitor API. */
KSCrashMonitorAPI *kscm_resource_getAPI(void);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashMonitor_Resource_h
