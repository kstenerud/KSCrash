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
#include "KSCrashNamespace.h"
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
 * KSCrashCConfiguration config = KSCrashCConfiguration_Default();
 * config.monitors = KSCrashMonitorTypeAll;
 * KSCrashInstallErrorCode result = kscrash_install("MyApp", "/path/to/install", &config);
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
                                        KSCrashCConfiguration *configuration);

/** Set the user-supplied data in JSON format.
 *
 * @deprecated Use the per-key API (kscrash_setUserInfoString, etc.) instead.
 * The per-key API is backed by an mmap'd run sidecar with zero crash-time cost.
 *
 * This function is thread-safe. Under extreme contention, the update
 * may be skipped (very unlikely in practice).
 *
 * @param userInfoJSON Pre-baked JSON containing user-supplied information.
 *                     NULL = delete.
 */
void kscrash_setUserInfoJSON(const char *const userInfoJSON)
    KSCRASH_DEPRECATED("Use the per-key API (kscrash_setUserInfoString, etc.) instead");

/** Get a copy of the user-supplied data in JSON format.
 *
 * @deprecated Use the per-key API instead.
 *
 * This function is thread-safe. Under extreme contention, may return
 * NULL even if information is set (very unlikely in practice).
 *
 * @return A string containing the JSON user-supplied information,
 *         or NULL if no information is set.
 *         The caller is responsible for freeing the returned string.
 */
const char *kscrash_getUserInfoJSON(void) KSCRASH_DEPRECATED("Use the per-key API instead");

#pragma mark-- Per-Key User Info --

/** Set a string value for the given key.
 *  Passing NULL for value removes the key.
 *  Strings longer than 1024 bytes are truncated.
 *  Requires kscrash_install() to have completed successfully before use.
 *  To set initial user info before install, use KSCrashInstallConfiguration.userInfoJSON.
 */
void kscrash_setUserInfoString(const char *key, const char *value);

/** Set a signed 64-bit integer value for the given key. */
void kscrash_setUserInfoInt(const char *key, int64_t value);

/** Set an unsigned 64-bit integer value for the given key. */
void kscrash_setUserInfoUInt(const char *key, uint64_t value);

/** Set a double-precision floating-point value for the given key. */
void kscrash_setUserInfoDouble(const char *key, double value);

/** Set a boolean value for the given key. */
void kscrash_setUserInfoBool(const char *key, bool value);

/** Set a date value for the given key (nanoseconds since 1970-01-01 00:00:00 UTC). */
void kscrash_setUserInfoDate(const char *key, uint64_t nanosecondsSince1970);

/** Remove the value for the given key. */
void kscrash_removeUserInfoValue(const char *key);

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

#pragma mark-- Reporting --

/** Add a custom report to the store.
 *
 * @param report The report's contents (must be JSON encoded).
 * @param reportLength The length of the report in bytes.
 *
 * @return the new report's ID.
 */
int64_t kscrash_addUserReport(const char *report, int reportLength);

/** Get the run ID for the current process.
 *
 * Returns a UUID string generated once during kscrash_install().
 * The returned buffer is read-only after install, so this is
 * async-signal-safe and can be called from crash handlers.
 *
 * @return A null-terminated UUID string (lowercase, 36 characters).
 *         The returned pointer is valid for the lifetime of the process.
 */
const char *kscrash_getRunID(void);

/** Get the resolved run summaries directory.
 *
 * @return The directory holding per-run `.run` and `.sessions` files, or NULL
 *         before kscrash_install(). Read-only after install; the returned
 *         pointer is valid for the lifetime of the process.
 */
const char *kscrash_getRunSummariesPath(void);

/** Get the resolved run sidecars directory.
 *
 * @return The directory holding per-run monitor sidecars, or NULL before
 *         kscrash_install(). Read-only after install; the returned pointer is
 *         valid for the lifetime of the process.
 */
const char *kscrash_getRunSidecarsPath(void);

/** Get the installed run summary retention cap.
 *
 * @return The maximum number of run summaries kept on disk; 0 or negative
 *         means run summaries are disabled.
 */
int kscrash_getMaxRunSummaryCount(void);

/** Load the run ID of a crashed process from its corpse.
 *
 * For a crash extension (iOS 27 CrashReporterExtension): scans the corpse's images
 * for the section that holds its run ID and copies it into this process's run ID, so a report
 * written here for that corpse is stamped with the crashed run's ID rather than this process's own.
 * Pass the corpse task port and the corpse's image load addresses (from the extension's binary image
 * list); the run ID lives in a known section the scan locates by name.
 *
 * @param corpse The corpse task port.
 * @param imageLoadAddresses The corpse's image load addresses.
 * @param imageCount The number of entries in @c imageLoadAddresses.
 * @return true if the run ID was found and loaded, false otherwise.
 */
bool kscrash_loadRunIDFromCorpse(task_t corpse, const uint64_t *imageLoadAddresses, uint32_t imageCount);

/** Clear the run ID.
 *
 * For a crash extension only, where the run ID is per-corpse state: a capture
 * clears it before calling kscrash_loadRunIDFromCorpse, so a corpse whose run ID cannot be
 * read produces a report with no run ID rather than one stamped with a previous corpse's.
 * Must not be called in a normal install, where the run ID is generated once and stays
 * read-only for async-signal-safety.
 */
void kscrash_clearRunID(void);

/** Install in extension (reporter-only) mode: this process writes reports about other
 * processes and detects no crashes of its own.
 *
 * For a crash extension (iOS 27 CrashReportExtension). The install
 * directory is the extension's OWN report area, typically inside an App Group container so
 * the app can read the reports from it later; it is not the app's install directory. This
 * initializes the report store and the report-writing pipeline and registers the given
 * plugin monitors, and nothing else: no crash handlers, no last-run-id chain, no run
 * summaries, no previous-run analysis, no console log, and no report pruning.
 *
 * @param appName The APP's name, exactly as the app passes to kscrash_install. Report
 *        filenames embed it and the app's store scans by it when reading this area;
 *        a mismatched name writes reports the app never finds.
 * @param installPath The extension's report directory (e.g. <app group container>/KSCrash).
 * @param pluginAPIs Plugin monitors to register (e.g. the crash-report-extension monitor).
 *        May be NULL.
 * @param pluginCount The number of entries in @c pluginAPIs.
 * @return KSCrashInstallErrorNone on success.
 */
KSCrashInstallErrorCode kscrash_installForExtensionReporting(const char *appName, const char *const installPath,
                                                             KSCrashMonitorAPI *pluginAPIs, int pluginCount);

/** Get the run ID from the previous process run.
 *
 * Returns the UUID string that was saved during the previous call to
 * kscrash_install(). Used by the Lifecycle monitor to locate the previous
 * run's sidecar and determine crashedLastLaunch.
 *
 * @return A null-terminated UUID string, or an empty string if this is
 *         the first run or the previous ID could not be read.
 *         The returned pointer is valid for the lifetime of the process.
 */
const char *kscrash_getLastRunID(void);

/** Get the namespaced KSCrash name.
 *
 * Returns "KSCrash" by default, or "KSCrash<namespace>" when
 * KSCRASH_NAMESPACE is defined.
 *
 * @return A null-terminated string. The pointer is to static storage.
 */
const char *kscrash_namespaceIdentifier(void);

/** Get the namespaced KSCrash path under the Documents directory.
 *
 * Returns "<Documents>/KSCrash" (or "<Documents>/KSCrash<namespace>").
 * The path is computed once and cached for the lifetime of the process.
 *
 * @return A null-terminated path string, or NULL if the directory
 *         could not be resolved. The pointer is valid for the
 *         lifetime of the process.
 */
const char *kscrash_documentsPath(void);

/** Get the namespaced KSCrash path under the Application Support directory.
 *
 * Returns "<AppSupport>/KSCrash" (or "<AppSupport>/KSCrash<namespace>").
 * The path is computed once and cached for the lifetime of the process.
 *
 * @return A null-terminated path string, or NULL if the directory
 *         could not be resolved. The pointer is valid for the
 *         lifetime of the process.
 */
const char *kscrash_applicationSupportPath(void);

/** Get the namespaced KSCrash path under the Caches directory.
 *
 * Returns "<Caches>/KSCrash" (or "<Caches>/KSCrash<namespace>").
 * The path is computed once and cached for the lifetime of the process.
 *
 * @return A null-terminated path string, or NULL if the directory
 *         could not be resolved. The pointer is valid for the
 *         lifetime of the process.
 */
const char *kscrash_cachesPath(void);

#pragma mark-- Deprecated --

/** @deprecated The Lifecycle monitor observes state transitions directly. */
void kscrash_notifyObjCLoad(void)
    KSCRASH_DEPRECATED("No longer needed. The Lifecycle monitor observes state directly.");

/** @deprecated The Lifecycle monitor observes state transitions directly. */
void kscrash_notifyAppActive(bool isActive)
    KSCRASH_DEPRECATED("No longer needed. The Lifecycle monitor observes state directly.");

/** @deprecated The Lifecycle monitor observes state transitions directly. */
void kscrash_notifyAppInForeground(bool isInForeground)
    KSCRASH_DEPRECATED("No longer needed. The Lifecycle monitor observes state directly.");

/** @deprecated The Lifecycle monitor observes state transitions directly. */
void kscrash_notifyAppTerminate(void)
    KSCRASH_DEPRECATED("No longer needed. The Lifecycle monitor observes state directly.");

/** @deprecated The Lifecycle monitor observes state transitions directly. */
void kscrash_notifyAppCrash(void)
    KSCRASH_DEPRECATED("No longer needed. The Lifecycle monitor observes state directly.");

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashC_h
