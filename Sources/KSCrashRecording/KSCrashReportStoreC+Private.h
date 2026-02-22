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

/** Remove run sidecar directories that no longer have matching reports.
 *
 * Called automatically within sendAllReports. If you handle report delivery
 * yourself, call this periodically or after sending reports.
 * May block, so prefer calling from a background thread.
 *
 * @param configuration The store configuration.
 */
void kscrs_cleanupOrphanedRunSidecars(const KSCrashReportStoreCConfiguration *const configuration);

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

#ifdef __cplusplus
}
#endif

#endif  // KSCrashReportStoreC_Private_h
