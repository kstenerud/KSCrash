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

#ifdef __cplusplus
extern "C" {
#endif

#define KSCRS_MAX_PATH_LENGTH 1024

/** The default name of a folder (inside the KSCrash install path) that is used for report store.
 */
#define KSCRS_DEFAULT_REPORTS_FOLDER "Reports"

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

/** Get a list of IDs for all reports on disk.
 *
 * @param reportIDs An array big enough to hold all report IDs.
 * @param count How many reports the array can hold.
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 *
 * @return The number of report IDs that were placed in the array (an absent
 *         reports directory is 0), or -1 when the reports directory cannot be
 *         enumerated.
 */
int kscrs_getReportIDs(int64_t *reportIDs, int count, const KSCrashReportStoreCConfiguration *const configuration);

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
char *kscrs_readReport(int64_t reportID, const KSCrashReportStoreCConfiguration *const configuration,
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

/** Add a custom report to the store.
 *
 * @param report The report's contents: JSON in the standard KSCrash report
 *               shape. A report of any other shape is never delivered by the
 *               send.
 * @param reportLength The length of the report in bytes.
 * @param configuration The store configuretion (e.g. reports path, app name etc).
 *
 * @return The new report's ID.
 */
int64_t kscrs_addUserReport(const char *report, int reportLength,
                            const KSCrashReportStoreCConfiguration *const configuration);

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
bool kscrs_deleteReportWithID(int64_t reportID, const KSCrashReportStoreCConfiguration *const configuration);

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

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashReportStoreC_h
