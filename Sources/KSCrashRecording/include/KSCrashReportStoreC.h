//
//  KSCrashReportStoreC.h
//
//  Created by Karl Stenerud on 2012-02-05.
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

#ifndef HDR_KSCrashReportStoreC_h
#define HDR_KSCrashReportStoreC_h

#include <stdint.h>

#include "KSCrashCConfiguration.h"
#include "KSCrashError.h"
#include "KSCrashNamespace.h"
#include "KSID.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KSCRS_MAX_PATH_LENGTH 1024

/** The default name of a folder (inside the KSCrash install path) that is used for report store.
 */
#define KSCRS_DEFAULT_REPORTS_FOLDER "Reports"

/** The other store directories an install creates next to Reports. Shared with
 *  the Swift install's Locations; change them together. */
#define KSCRS_DEFAULT_REPORT_SIDECARS_FOLDER "Sidecars"
#define KSCRS_DEFAULT_RUN_SIDECARS_FOLDER "RunSidecars"
#define KSCRS_DEFAULT_RUNS_FOLDER "Runs"
#define KSCRS_DEFAULT_DATA_FOLDER "Data"

/** Report files are "<KSCRS_REPORT_NAME_DIGITS decimal digits of wall-clock
 *  nanoseconds>-<report id>.<KSCRS_REPORT_FILENAME_EXTENSION>". The digits
 *  carry the write order; the id (the report's UUID text, KSID_LENGTH
 *  characters) is the identity. */
#define KSCRS_REPORT_ID_LENGTH KSID_LENGTH
#define KSCRS_REPORT_NAME_DIGITS 20
#define KSCRS_REPORT_FILENAME_EXTENSION "json"

/** The report id in a store filename, into a KSID_SIZE buffer.
 *  False for any name that is not a report's: the single authority on the
 *  filename grammar, for the C and Swift stores alike. */
bool kscrs_parseReportFilename(const char *filename, char *reportIDBuffer);

/** The UserInfo monitor's id, and its per-run sidecar filename inside a run's
 *  RunSidecars/<runID>/ directory. The filename is the id plus the sidecar
 *  extension; a unit test enforces the composition, so keep all three in sync.
 *  Written by the UserInfo monitor; read by the report userInfo stitch and the
 *  run-summary metadata stitch. */
#define KSCRS_MONITOR_ID_USERINFO "UserInfo"
#define KSCRS_RUN_SIDECAR_EXTENSION "ksscr"
#define KSCRS_USERINFO_RUN_SIDECAR_FILENAME "UserInfo.ksscr"

/** Writer-named run summary files are "<digits>.run": the run's wall-clock
 *  start in nanoseconds, zero-padded to at most this many digits. Shared by
 *  the C writer and the Swift store's parser; change them together. */
#define KSCRS_RUN_SUMMARY_FILENAME_DIGITS 19
#define KSCRS_RUN_SUMMARY_FILENAME_EXTENSION "run"

/** A run's session log is "<runID>.sessions". Shared by the Lifecycle
 *  monitor's writer and reader, the reclaim, and the Swift store's grouping;
 *  change them together. */
#define KSCRS_SESSIONS_FILENAME_EXTENSION "sessions"

/** Initialize the report store.
 *
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 */
KSCrashInstallErrorCode kscrs_initialize(const KSCrashReportStoreCConfiguration *const configuration);

/** Get the number of reports on disk.
 *
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 *
 * @return The number of reports on disk (an absent reports directory is 0),
 *         or -1 when the reports directory cannot be enumerated.
 */
int kscrs_getReportCount(const KSCrashReportStoreCConfiguration *const configuration);

/** Why kscrs_readReport returned NULL. */
typedef enum {
    KSCrashReportReadStatusOK = 0,

    /** The report file is missing or could not be read. */
    KSCrashReportReadStatusUnreadable,

    /** The report file was read but does not hold a JSON report object, so it
     * cannot be stitched or delivered. Reading it again gives the same answer. */
    KSCrashReportReadStatusUndecodable,
} KSCrashReportReadStatus;

/** Read a report.
 *
 * @warning MEMORY MANAGEMENT WARNING: User is responsible for calling free() on the returned value.
 *
 * @param reportID The report's ID.
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 * @param status Why a NULL was returned (may be NULL).
 *
 * @return The NULL terminated report, or NULL if it could not be read or is not a report.
 */
char *kscrs_readReport(const char *reportID, const KSCrashReportStoreCConfiguration *const configuration,
                       KSCrashReportReadStatus *status);

/** Read a report at a given path.
 * This is a convenience method for reading reports that are not in the standard reports directory.
 *
 * @warning MEMORY MANAGEMENT WARNING: User is responsible for calling free() on the returned value.
 *
 * @param path The full path to the report.
 *
 * @return The NULL terminated report, or NULL if not found.
 */
char *kscrs_readReportAtPath(const char *path);

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

/** Get a run-summary "summary sidecar" file path.
 *
 * Builds: <runSummariesPath>/<runID>.<extension>. Path building only: read
 * paths (the delivery stitches) must not mutate disk, so the writer's call
 * site creates the directory. Rejects non-UUID run IDs. Does not check
 * whether the feature is enabled; the caller decides that.
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

/** The run a report belongs to, from the report file alone: nothing is
 * stitched and no run artifacts are touched.
 *
 * @warning MEMORY MANAGEMENT WARNING: User is responsible for calling free() on the returned value.
 *
 * @param reportID The report's ID.
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 *
 * @return The NULL terminated run id (a UUID string), or NULL when the
 *         report cannot be read or records no valid run.
 */
char *kscrs_copyReportRunID(const char *reportID, const KSCrashReportStoreCConfiguration *const configuration);

/** Add a custom report to the store.
 *
 * @param report The report's contents: JSON in the standard KSCrash report
 *               shape. A report of any other shape is never delivered by the
 *               send.
 * @param reportLength The length of the report in bytes.
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 * @param reportIDOut Receives the report's id, NUL terminated, in a buffer of at
 *                    least KSID_SIZE bytes: the payload's own report.id when that
 *                    is a UUID, else one minted here and written into the payload.
 *
 * @return true when the report was stored.
 */
bool kscrs_addUserReport(const char *report, int reportLength,
                         const KSCrashReportStoreCConfiguration *const configuration, char *reportIDOut);

/** Delete all reports on disk.
 *
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 */
void kscrs_deleteAllReports(const KSCrashReportStoreCConfiguration *const configuration);

/** Delete report.
 *
 * @param reportID An ID of report to delete.
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 *
 * @return true if the report file was removed.
 */
bool kscrs_deleteReportWithID(const char *reportID, const KSCrashReportStoreCConfiguration *const configuration);

/** Get a sidecar file path.
 *
 * Creates the sidecar subdirectory if it doesn't exist.
 *
 * @param monitorId The unique identifier of the monitor.
 * @param name The filename (without extension).
 * @param extension The file extension (without dot).
 * @param pathBuffer Buffer to receive the file path.
 * @param pathBufferLength The size of the path buffer.
 * @param configuration The store configuration containing the sidecars base path.
 *
 * @return true if the path was successfully written, false on failure.
 */
bool kscrs_getReportSidecarFilePath(const char *monitorId, const char *name, const char *extension, char *pathBuffer,
                                    size_t pathBufferLength,
                                    const KSCrashReportStoreCConfiguration *const configuration);

/** Remove on-disk run data (run sidecar directories and session sidecars) for
 * runs no longer referenced by any report or run summary.
 *
 * Called automatically within the send flows. If you handle delivery yourself,
 * call this periodically or after sending. May block, so prefer a background
 * thread.
 *
 * @param configuration The store configuration.
 */
void kscrs_reclaimOrphanedRunData(const KSCrashReportStoreCConfiguration *const configuration);

/** Move every report in sourceReportsPath into this store.
 *
 * Files that cannot be moved are left in place and retried on the next call; an existing
 * destination is never replaced. No-op when sourceReportsPath is NULL.
 *
 * @param sourceReportsPath The directory to drain (a crash extension's Reports directory).
 * @param configuration The store configuration.
 */
void kscrs_ingestExtensionReports(const char *sourceReportsPath,
                                  const KSCrashReportStoreCConfiguration *const configuration);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashReportStoreC_h
