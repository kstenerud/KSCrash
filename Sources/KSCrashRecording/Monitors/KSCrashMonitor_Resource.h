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
#include "KSResourceSidecar.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Battery level at or below which an unplugged device is considered
 *  a low-battery termination candidate (percent, 0–100). */
#define KSCRASH_BATTERY_LEVEL_CRITICAL 1

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
