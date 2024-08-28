//
//  KSCrashC.h
//
//  Created by Karl Stenerud on 2012-01-28.
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

/* Primary C entry point into the crash reporting system.
 */

#ifndef HDR_KSCrashC_h
#define HDR_KSCrashC_h

#include <stdbool.h>

#include "KSCrashCConfiguration.h"
#include "KSCrashError.h"
#include "KSCrashMonitorType.h"
#include "KSCrashReportWriter.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Install the crash reporter. This function initializes and configures the crash
 * reporter for the specified application, allowing it to monitor and record crashes.
 * Upon detecting a crash, the reporter will log detailed information and terminate
 * the application to prevent further damage or inconsistent state.
 *
 * @param appName The name of the application.
 *                This name will be used to identify the application in the crash reports.
 *                It is essential for associating crash data with the specific application.
 *
 * @param installPath The directory where the crash reports and related data will be stored.
 *                    The specified directory must be writable, as it will contain log files,
 *                    crash data, and other diagnostic information.
 *
 * @param configuration A `KSCrashCConfiguration` struct containing various settings and options
 *                      for the crash reporter. This struct allows you to specify which types of crashes
 *                      to monitor, user-supplied metadata, memory introspection options,
 *                      and other advanced settings.
 *                      Each field in the configuration struct has default values, which can be overridden
 *                      to tailor the behavior of the crash reporter to your specific requirements.
 *
 * @return KSCrashInstallErrorCode indicating the result of the installation.
 *         0 if installation was successful, other values indicate specific errors.
 *
 * Example usage:
 * ```
 * KSCrashCConfiguration config = KSCrashCConfiguration_Default;
 * config.monitors = KSCrashMonitorTypeAll;
 * config.userInfoJSON = "{ \"user\": \"example\" }";
 * KSCrashInstallErrorCode result = kscrash_install("MyApp", "/path/to/install", config);
 * if (result != 0) {
 *     // Handle installation error
 * }
 * ```
 *
 * @note This function must be called before any crashes occur to ensure that
 * the crash reporter is properly set up and able to capture the relevant information.
 *
 * @note Once installed, the crash reporter cannot be re-installed or modified
 * without restarting the application.
 */
KSCrashInstallErrorCode kscrash_install(const char *appName, const char *const installPath,
                                        KSCrashCConfiguration configuration);

/** Sets up the crash repors store.
 * This function is used to initialize the storage for crash reports.
 * The `kscrash_install` function sets up the reports store internally.
 * You only need to call this function if you are not using the `kscrash_install` function
 * or want to read crash reports from a custom location.
 *
 * @note this function can be called multiple times, but only before `kscrash_install` is called.
 *
 * @param appName The name of the application. Usually it's bundle name.
 * @param installPath The directory where the crash reports and related data will be stored.
 * @return KSCrashInstallErrorCode indicating the result of the setup.
 */
KSCrashInstallErrorCode kscrash_setupReportsStore(const char *appName, const char *const installPath);

/** Set the user-supplied data in JSON format.
 *
 * @param userInfoJSON Pre-baked JSON containing user-supplied information.
 *                     NULL = delete.
 */
void kscrash_setUserInfoJSON(const char *const userInfoJSON);

/** Get a copy of the user-supplied data in JSON format.
 *
 * @return A string containing the JSON user-supplied information,
 *         or NULL if no information is set.
 *         The caller is responsible for freeing the returned string.
 */
const char *kscrash_getUserInfoJSON(void);

/** Report a custom, user defined exception.
 * This can be useful when dealing with scripting languages.
 *
 * If terminateProgram is true, all sentries will be uninstalled and the application will
 * terminate with an abort().
 *
 * @param name The exception name (for namespacing exception types).
 *
 * @param reason A description of why the exception occurred.
 *
 * @param language A unique language identifier.
 *
 * @param lineOfCode A copy of the offending line of code (NULL = ignore).
 *
 * @param stackTrace JSON encoded array containing stack trace information (one frame per array entry).
 *                   The frame structure can be anything you want, including bare strings.
 *
 * @param logAllThreads If true, suspend all threads and log their state. Note that this incurs a
 *                      performance penalty, so it's best to use only on fatal errors.
 *
 * @param terminateProgram If true, do not return from this function call. Terminate the program instead.
 */
void kscrash_reportUserException(const char *name, const char *reason, const char *language, const char *lineOfCode,
                                 const char *stackTrace, bool logAllThreads, bool terminateProgram);

#pragma mark-- Notifications --

/** Notify the crash reporter of KSCrash being added to Objective-C runtime system.
 */
void kscrash_notifyObjCLoad(void);

/** Notify the crash reporter of the application active state.
 *
 * @param isActive true if the application is active, otherwise false.
 */
void kscrash_notifyAppActive(bool isActive);

/** Notify the crash reporter of the application foreground/background state.
 *
 * @param isInForeground true if the application is in the foreground, false if
 *                 it is in the background.
 */
void kscrash_notifyAppInForeground(bool isInForeground);

/** Notify the crash reporter that the application is terminating.
 */
void kscrash_notifyAppTerminate(void);

/** Notify the crash reporter that the application has crashed.
 */
void kscrash_notifyAppCrash(void);

#pragma mark-- Reporting --

/** Get the number of reports on disk.
 */
int kscrash_getReportCount(void);

/** Get a list of IDs for all reports on disk.
 *
 * @param reportIDs An array big enough to hold all report IDs.
 * @param count How many reports the array can hold.
 *
 * @return The number of report IDs that were placed in the array.
 */
int kscrash_getReportIDs(int64_t *reportIDs, int count);

/** Read a report.
 *
 * @param reportID The report's ID.
 *
 * @return The NULL terminated report, or NULL if not found.
 *         MEMORY MANAGEMENT WARNING: User is responsible for calling free() on the returned value.
 */
char *kscrash_readReport(int64_t reportID);

/** Read a report at a specified path.
 *
 * @param path The full path to the report.
 *
 * @return The NULL terminated report, or NULL if not found.
 *         MEMORY MANAGEMENT WARNING: User is responsible for calling free() on the returned value.
 */
char *kscrash_readReportAtPath(const char *path);

/** Add a custom report to the store.
 *
 * @param report The report's contents (must be JSON encoded).
 * @param reportLength The length of the report in bytes.
 *
 * @return the new report's ID.
 */
int64_t kscrash_addUserReport(const char *report, int reportLength);

/** Delete all reports on disk.
 */
void kscrash_deleteAllReports(void);

/** Delete report.
 *
 * @param reportID An ID of report to delete.
 */
void kscrash_deleteReportWithID(int64_t reportID);

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashC_h
