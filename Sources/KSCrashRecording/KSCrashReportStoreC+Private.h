//
//  KSCrashReportStoreC+Private.h
//
//  Created by Nikolay Volosatov on 2024-08-30.
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

#ifndef KSCrashReportStoreC_Private_h
#define KSCrashReportStoreC_Private_h

#include "KSCrashReportStoreC.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Get the next crash report to be generated.
 * Max length for paths is KSCRS_MAX_PATH_LENGTH
 *
 * @param crashReportPathBuffer Buffer to store the crash report path.
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 *
 * @return The report ID of the next report.
 */
int64_t kscrs_getNextCrashReport(char *crashReportPathBuffer,
                                 const KSCrashReportStoreCConfiguration *const configuration);

/** Get the sidecar file path for a report.
 *
 * Creates the sidecar subdirectory if it doesn't exist.
 *
 * @param monitorId The unique identifier of the monitor.
 * @param reportID The report ID the sidecar is associated with.
 * @param pathBuffer Buffer to receive the sidecar file path.
 * @param pathBufferLength The size of the path buffer.
 * @param configuration The store configuration containing the sidecars base path.
 *
 * @return true if the path was successfully written, false on failure.
 */
bool kscrs_getReportSidecarFilePathForReport(const char *monitorId, int64_t reportID, char *pathBuffer,
                                             size_t pathBufferLength,
                                             const KSCrashReportStoreCConfiguration *const configuration);

/** Get a run-scoped sidecar file path.
 *
 * Builds: <runSidecarsPath>/<runID>/<monitorId>.ksscr
 * Creates the run subdirectory if it doesn't exist.
 *
 * @param monitorId The unique identifier of the monitor.
 * @param pathBuffer Buffer to receive the sidecar file path.
 * @param pathBufferLength The size of the path buffer.
 * @param configuration The store configuration containing the runSidecarsPath.
 *
 * @return true if the path was successfully written, false on failure.
 */
bool kscrs_getRunSidecarFilePath(const char *monitorId, char *pathBuffer, size_t pathBufferLength,
                                 const KSCrashReportStoreCConfiguration *const configuration);

/** Get a run-scoped sidecar file path for a specific run ID.
 *
 * Like kscrs_getRunSidecarFilePath, but uses the given runID instead of
 * the current process run ID. Does NOT create the directory (read-only use).
 *
 * @param monitorId The unique identifier of the monitor.
 * @param runID The run ID to look up.
 * @param pathBuffer Buffer to receive the sidecar file path.
 * @param pathBufferLength The size of the path buffer.
 *
 * @return true if the path was successfully written, false on failure.
 */
bool kscrs_getRunSidecarFilePathForRunID(const char *monitorId, const char *runID, char *pathBuffer,
                                         size_t pathBufferLength,
                                         const KSCrashReportStoreCConfiguration *const configuration);

/** Extract the run_id from a JSON crash report.
 *
 * Parses report["report"]["run_id"] from the JSON string.
 * Uses ObjC JSON parsing — safe at normal startup, not from crash handlers.
 *
 * @param report The NULL-terminated JSON report string.
 * @param runIdBuffer Buffer to receive the run_id string.
 * @param bufferLength The size of runIdBuffer in bytes.
 *
 * @return true if the run_id was successfully extracted, false otherwise.
 */
bool kscrs_extractRunIdFromReport(const char *report, char *runIdBuffer, size_t bufferLength);

/** Read a report by path and ID, applying fixup and all stitch callbacks.
 *
 * Like kscrs_readReportAtPath but also stitches per-report sidecars
 * (which require the report ID). Uses the stored configuration.
 *
 * @param path Full path to the report JSON file.
 * @param reportID The report's ID.
 *
 * @return A heap-allocated stitched JSON string, or NULL on failure. Caller must free().
 */
char *kscrs_readReportByPathAndID(const char *path, int64_t reportID);

/** Finalize a report in-place by stitching all sidecars and writing back.
 *
 * Reads the report from disk, applies fixup and all stitch callbacks
 * (both run sidecars and per-report sidecars), adds a "finalized" flag
 * to the report.report section, and atomically writes the result back.
 * Sidecars are left on disk (reads skip stitching for finalized reports)
 * and cleaned up when the report is deleted after consumption.
 *
 * This allows mid-run finalization (e.g., when a hang recovers) so the
 * stitched metadata reflects current-run state instead of next-launch state.
 *
 * Safe to call from any thread.
 *
 * @param reportPath Full path to the report JSON file on disk.
 * @param reportID The report's ID.
 * @return true if the report was successfully finalized, false otherwise.
 */
bool kscrs_finalizeReport(const char *reportPath, int64_t reportID);

/** Check whether a JSON report has already been finalized.
 *
 * Parses the JSON and checks report.report.finalized.
 * Uses ObjC JSON parsing, not async-signal-safe.
 *
 * @param report The NULL-terminated JSON report string.
 * @return true if the report is marked as finalized.
 */
bool kscrs_isReportFinalized(const char *report);

/** Inject a "finalized" flag into a stitched JSON report.
 *
 * Decodes the JSON, sets report.report.finalized = true, and re-encodes
 * with pretty printing. Uses ObjC JSON parsing, not async-signal-safe.
 *
 * @param stitchedReport The NULL-terminated stitched JSON report string.
 * @return A heap-allocated JSON string with the flag injected, or NULL on failure. Caller must free().
 */
char *kscrs_injectFinalizedFlag(const char *stitchedReport);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashReportStoreC_Private_h
