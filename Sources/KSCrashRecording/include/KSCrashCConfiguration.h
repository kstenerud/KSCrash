//
//  KSCrashCConfiguration.h
//
//  Created by Gleb Linnik on 10.06.2024.
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

#ifndef KSCrashCConfiguration_h
#define KSCrashCConfiguration_h

#include <stdlib.h>
#include <string.h>

#include "KSCrashExceptionHandlingPlan.h"
#include "KSCrashMonitorAPI.h"
#include "KSCrashMonitorContext.h"
#include "KSCrashMonitorType.h"
#include "KSCrashNamespace.h"
#include "KSCrashReportWriter.h"
#include "KSCrashReportWriterCallbacks.h"
#include "KSSystemCapabilities.h"

#ifdef __cplusplus
extern "C" {
#endif

/** The most plugin monitors an install accepts (more fail the install). */
#define KSC_MAX_PLUGINS 64

/** Configuration for managing crash reports through the report store API.
 */
typedef struct {
    /** The directory path for storing crash reports.
     * The specified directory must have write permissions. If it doesn't exist,
     * the system will attempt to create it automatically.
     *
     * @note This field must be set prior to using this configuration with any `kscrs_` functions.
     */
    const char *reportsPath;

    /** The directory path for storing per-report sidecar files.
     * Layout: <reportSidecarsPath>/<monitorId>/<reportID>.ksscr
     * If NULL, defaults to a "Sidecars" sibling directory alongside reportsPath.
     */
    const char *reportSidecarsPath;

    /** The directory path for storing per-run sidecar files.
     * Layout: <runSidecarsPath>/<runID>/<monitorId>.ksscr
     * If NULL, defaults to a "RunSidecars" sibling directory alongside reportsPath.
     */
    const char *runSidecarsPath;

    /** The directory path for storing per-run summary files.
     * Files are written with a `.run` extension.
     * If NULL, defaults to a "Runs" sibling directory alongside reportsPath.
     */
    const char *runSummariesPath;

    /** The maximum number of crash reports to retain on disk.
     *
     * Defines the upper limit of crash reports to keep in storage. When this threshold
     * is reached, the system will remove the oldest reports to accommodate new ones.
     *
     * **Default**: 50
     */
    int maxReportCount;

    /** Upper bound on retained run summaries; oldest are pruned when exceeded.
     * Set to 0 to keep no run summaries. Sessions are still tracked so crash
     * reports keep their session id.
     *
     * **Default**: 50
     */
    int maxRunSummaryCount;
} KSCrashReportStoreCConfiguration;

static inline KSCrashReportStoreCConfiguration KSCrashReportStoreCConfiguration_Default(void)
{
    return (KSCrashReportStoreCConfiguration) {
        .reportsPath = NULL,
        .reportSidecarsPath = NULL,
        .runSidecarsPath = NULL,
        .runSummariesPath = NULL,
        .maxReportCount = 50,
        .maxRunSummaryCount = 50,
    };
}

static inline KSCrashReportStoreCConfiguration KSCrashReportStoreCConfiguration_Copy(
    const KSCrashReportStoreCConfiguration *configuration)
{
    return (KSCrashReportStoreCConfiguration) {
        .reportsPath = configuration->reportsPath ? strdup(configuration->reportsPath) : NULL,
        .reportSidecarsPath = configuration->reportSidecarsPath ? strdup(configuration->reportSidecarsPath) : NULL,
        .runSidecarsPath = configuration->runSidecarsPath ? strdup(configuration->runSidecarsPath) : NULL,
        .runSummariesPath = configuration->runSummariesPath ? strdup(configuration->runSummariesPath) : NULL,
        .maxReportCount = configuration->maxReportCount,
        .maxRunSummaryCount = configuration->maxRunSummaryCount,
    };
}

static inline void KSCrashReportStoreCConfiguration_Release(KSCrashReportStoreCConfiguration *configuration)
{
    free((void *)configuration->reportsPath);
    free((void *)configuration->reportSidecarsPath);
    free((void *)configuration->runSidecarsPath);
    free((void *)configuration->runSummariesPath);
}

/** Configuration for KSCrash settings.
 */
typedef struct {
    /** How many unsent reports the store keeps; the oldest are dropped past it. */
    int maxReportCount;

    /** How many run summaries the store keeps; 0 or less disables them. */
    int maxRunSummaryCount;

    /** The crash types that will be handled.
     * Some crash types may not be enabled depending on circumstances (e.g., running in a debugger).
     */
    KSCrashMonitorType monitors;

    /** If true, attempt to fetch dispatch queue names for each running thread.
     *
     * This option enables the retrieval of dispatch queue names for each thread at the
     * time of a crash. This can provide useful context, but there is a risk of crashing
     * during the `ksthread_getQueueName()` call.
     *
     * **Default**: false
     */
    bool enableQueueNameSearch;

    /** If true, introspect memory contents during a crash.
     *
     * Enables the inspection of memory contents during a crash. Any Objective-C objects
     * or C strings near the stack pointer or referenced by CPU registers or exceptions
     * will be included in the crash report, along with their contents.
     *
     * **Default**: false
     */
    bool enableMemoryIntrospection;

    /** List of Objective-C classes that should never be introspected.
     *
     * A list of class names that should not be inspected during a crash. Only the class
     * names will be recorded in the crash report when instances of these classes are
     * encountered. This is useful for information security.
     *
     * **Default**: NULL
     */
    struct {
        const char **strings; /**< Array of strings. */
        int length;           /**< Length of the array. */
    } doNotIntrospectClasses;

    /** Callback to invoke before beginning to write a crash report.
     *
     * This is the first in the series of callbacks, called after the event information has been gathered but before a
     * report is written.
     *
     * The `plan` parameter determines what can be safely done within the callback, and can be modified to alter how
     * this event is handled.
     *
     * **Default**: NULL
     */
    KSCrashWillWriteReportCallback willWriteReportCallback;

    /** Callback to invoke while writing a crash report.
     *
     * This is the second in the series of callbacks, called while writing the `user` section of the crash report.
     * From this callback, you may add additional fields to this section using the provided writer.
     *
     * The `plan` parameter determines what can be safely done within the callback.
     *
     * @see KSCrash_ExceptionHandlingPlan
     *
     * **Default**: NULL
     */
    KSCrashIsWritingReportCallback isWritingReportCallback;

    /** Callback to invoke upon finishing writing a crash report.
     *
     * This is the third in the series of callbacks, called after the report has been written.
     *
     * The `plan` parameter determines what can be safely done within the callback.
     *
     * @see KSCrash_ExceptionHandlingPlan
     *
     * **Default**: NULL
     */
    KSCrashDidWriteReportCallback didWriteReportCallback;

    /** If true, append KSLOG console messages to the crash report.
     *
     * When enabled, KSLOG console messages will be included in the crash report.
     *
     * **Default**: false
     */
    bool addConsoleLogToReport;

    /** If true, print the previous log to the console on startup.
     *
     * This option is for debugging purposes and will print the previous log to the
     * console when the application starts.
     *
     * **Default**: false
     */
    bool printPreviousLogOnStartup;

    /** If true, enable C++ exceptions catching with `__cxa_throw` swap.
     *
     * This experimental feature works similarly to `LD_PRELOAD` and supports catching
     * C++ exceptions by swapping the `__cxa_throw` function. It helps in obtaining
     * accurate stack traces even in dynamically linked libraries and allows overriding
     * the original `__cxa_throw` with a custom implementation.
     *
     * @note This feature is automatically disabled when the binary is compiled with
     * sanitizers (ASan, TSan, etc.) as they also intercept `__cxa_throw` and conflict
     * with this swapping mechanism.
     *
     * **Default**: true
     */
    bool enableSwapCxaThrow;

    /** If true, resolved hangs are kept as non-fatal reports.
     *
     * When enabled, hangs that resolve on their own are preserved as reports
     * with duration and stack trace information. When disabled (default),
     * resolved hangs are discarded.
     *
     * Only applies when `KSCrashMonitorTypeHang` is included in `monitors`.
     *
     * **Default**: false
     */
    bool enableHangReporting;

    /** If true, generate non-fatal reports when sustained CPU usage reaches
     *  warning or critical thresholds.
     *
     * Each upward state transition (normal to warning, warning to critical,
     * or normal to critical) produces one report with all thread stacks.
     *
     * Only applies when `KSCrashMonitorTypeResource` is included in `monitors`.
     *
     * **Default**: false
     */
    bool enableCPUExceptionReporting;

    /** If true, use compact binary image reporting.
     *
     * When enabled, the `binary_images` array is filtered to only include
     * images referenced by backtrace frames. Images that only have
     * crash_info but no backtrace reference are omitted — in practice
     * the crashing image is almost always referenced by the backtrace.
     *
     * **Default**: false
     */
    bool enableCompactBinaryImages;

    /** Plugin monitors to register at install time.
     *
     * An array of `KSCrashMonitorAPI` structs that will be copied into static
     * storage and registered via `kscm_addMonitor()` during installation.
     * More than `KSC_MAX_PLUGINS` entries fail the install.
     *
     * If `release` is non-NULL, it will be called with `apis` during
     * `KSCrashCConfiguration_Release()`. Set it to `free` for heap-allocated
     * arrays, or leave it NULL for static/stack arrays.
     *
     * **Default**: `{ .apis = NULL, .length = 0, .release = NULL }`
     */
    struct {
        KSCrashMonitorAPI *apis;
        int length;
        void (*release)(void *apis);
    } plugins;

    /** If true, use `backtrace_async()` for KSCrash's current-thread stack capture paths.
     *
     * This can stitch Swift async continuation frames into self-thread backtraces such as
     * C++ exception throw-site and handler cursors, user-reported fallbacks, and current-thread
     * `ksbt_captureBacktrace` calls. When `backtrace_async()` is not available at build time or
     * runtime, KSCrash falls back to `backtrace()`.
     *
     * **Default**: false
     */
    bool enableSwiftAsyncStackTraces;
} KSCrashCConfiguration;

static inline KSCrashCConfiguration KSCrashCConfiguration_Default(void)
{
    return (KSCrashCConfiguration) {
        .maxReportCount = 50,
        .maxRunSummaryCount = 50,
        .monitors = KSCrashMonitorTypeDefault,
        .enableQueueNameSearch = false,
        .enableMemoryIntrospection = false,
        .doNotIntrospectClasses = { .strings = NULL, .length = 0 },
        .willWriteReportCallback = NULL,
        .isWritingReportCallback = NULL,
        .didWriteReportCallback = NULL,
        .addConsoleLogToReport = false,
        .printPreviousLogOnStartup = false,
        .enableSwapCxaThrow = true,
        .enableHangReporting = false,
        .enableCPUExceptionReporting = false,
        .enableCompactBinaryImages = false,
        .plugins = { .apis = NULL, .length = 0, .release = NULL },
        .enableSwiftAsyncStackTraces = false,
    };
}

static inline void KSCrashCConfiguration_Release(KSCrashCConfiguration *configuration)
{
    for (int idx = 0; idx < configuration->doNotIntrospectClasses.length; ++idx) {
        free((void *)(configuration->doNotIntrospectClasses.strings[idx]));
    }
    free(configuration->doNotIntrospectClasses.strings);
    if (configuration->plugins.release) {
        configuration->plugins.release(configuration->plugins.apis);
    }
}

#ifdef __cplusplus
}
#endif

#endif /* KSCrashCConfiguration_h */
