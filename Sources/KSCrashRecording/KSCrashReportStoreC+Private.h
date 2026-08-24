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

/** Maximum report file size we'll attempt to read (20 MB).
 *
 *  Reports exceeding this are silently skipped to prevent unbounded
 *  malloc on corrupt or pathologically large files.  The cap is shared
 *  by readReportAtPath, finalizeReport, and run-id extraction so they
 *  all agree on what constitutes "too large."
 */
#define KSCRS_MAX_REPORT_SIZE ((size_t)20000000)

/** The path a new crash report with this id is written to. Async-signal-safe.
 * Max length for paths is KSCRS_MAX_PATH_LENGTH
 *
 * @param reportID The report's id (its UUID text, the report's identity).
 * @param crashReportPathBuffer Buffer to store the crash report path.
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 */
void kscrs_getNextCrashReport(const char *reportID, char *crashReportPathBuffer,
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
bool kscrs_getReportSidecarFilePathForReport(const char *monitorId, const char *reportID, char *pathBuffer,
                                             size_t pathBufferLength,
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

/** Get a run-summary "summary sidecar" file path.
 *
 * Builds: <runSummariesPath>/<runID>.<extension> and creates runSummariesPath
 * if it doesn't exist. Rejects non-UUID run IDs. Does not check whether the
 * feature is enabled; the caller decides that.
 *
 * @param runID The run the file belongs to.
 * @param extension The file extension without a dot, e.g. "sessions".
 * @param pathBuffer Buffer to receive the file path.
 * @param pathBufferLength The size of the path buffer.
 * @param configuration The store configuration containing the runSummariesPath.
 *
 * @return true if the path was successfully written, false on failure.
 */
bool kscrs_getSummarySidecarFilePath(const char *runID, const char *extension, char *pathBuffer,
                                     size_t pathBufferLength,
                                     const KSCrashReportStoreCConfiguration *const configuration);

/** Sets the configuration used by the no-config readers
 *  (kscrs_readReportAtPath, kscrs_readReportByPathAndID, kscrs_finalizeReport)
 *  for sidecar stitching.
 *
 *  Typically called once by kscrash_install. Tests that need stitching to work
 *  without going through kscrash_install can call this directly. Pass NULL to
 *  clear (e.g. in tearDown so cross-test state does not leak).
 *
 *  The configuration is deep-copied; the caller does not need to keep the
 *  passed pointer alive after this call returns.
 */
void kscrs_setStitchConfig(const KSCrashReportStoreCConfiguration *configuration);

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
char *kscrs_readReportByPathAndID(const char *path, const char *reportID);

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
bool kscrs_finalizeReport(const char *reportPath, const char *reportID);

#ifdef __cplusplus
}
#endif

#endif  // KSCrashReportStoreC_Private_h
