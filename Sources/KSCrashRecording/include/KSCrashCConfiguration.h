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

#include "KSCrashMonitorType.h"
#include "KSCrashReportWriter.h"
#include "string.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Callback type for when a crash report is written.
 *
 * @param reportID The ID of the report that was written.
 */
typedef void (*KSReportWrittenCallback)(int64_t reportID);

/** Configuration for managing crash reports through the report store API.
 */
typedef struct {
    /** The name of the application.
     * This identifier is used to distinguish the application in crash reports.
     * It is crucial for correlating crash data with the specific application version.
     *
     * @note This field must be set prior to using this configuration with any `kscrs_` functions.
     */
    const char *appName;

    /** The directory path for storing crash reports.
     * The specified directory must have write permissions. If it doesn't exist,
     * the system will attempt to create it automatically.
     *
     * @note This field must be set prior to using this configuration with any `kscrs_` functions.
     */
    const char *reportsPath;

    /** The maximum number of crash reports to retain on disk.
     *
     * Defines the upper limit of crash reports to keep in storage. When this threshold
     * is reached, the system will remove the oldest reports to accommodate new ones.
     *
     * **Default**: 5
     */
    int maxReportCount;
} KSCrashReportStoreCConfiguration;

static inline KSCrashReportStoreCConfiguration KSCrashReportStoreCConfiguration_Default(void)
{
    return (KSCrashReportStoreCConfiguration) {
        .appName = NULL,
        .reportsPath = NULL,
        .maxReportCount = 5,
    };
}

static inline KSCrashReportStoreCConfiguration KSCrashReportStoreCConfiguration_Copy(
    KSCrashReportStoreCConfiguration *configuration)
{
    return (KSCrashReportStoreCConfiguration) {
        .appName = configuration->appName ? strdup(configuration->appName) : NULL,
        .reportsPath = configuration->reportsPath ? strdup(configuration->reportsPath) : NULL,
        .maxReportCount = configuration->maxReportCount,
    };
}

static inline void KSCrashReportStoreCConfiguration_Release(KSCrashReportStoreCConfiguration *configuration)
{
    free((void *)configuration->appName);
    free((void *)configuration->reportsPath);
}

/** Configuration for KSCrash settings.
 */
typedef struct {
    /** The report store configuration to be used for the corresponding installation.
     */
    KSCrashReportStoreCConfiguration reportStoreConfiguration;

    /** The crash types that will be handled.
     * Some crash types may not be enabled depending on circumstances (e.g., running in a debugger).
     */
    KSCrashMonitorType monitors;

    /** User-supplied data in JSON format. NULL to delete.
     *
     * This JSON string contains user-specific data that will be included in
     * the crash report. If NULL is passed, any existing user data will be deleted.
     */
    const char *userInfoJSON;

    /** The maximum time to allow the main thread to run without returning.
     *
     * If the main thread is occupied by a task for longer than this interval, the
     * watchdog will consider the queue deadlocked and shut down the app, writing a
     * crash report. Set to 0 to disable this feature.
     *
     * **Warning**: Ensure that no tasks on the main thread take longer to complete than
     * this value, including application startup. You may need to initialize your
     * application on a different thread or set this to a higher value until initialization
     * is complete.
     */
    double deadlockWatchdogInterval;

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

    /** Callback to invoke upon a crash.
     *
     * This function is called during the crash reporting process, providing an opportunity
     * to add additional information to the crash report. Only async-safe functions should
     * be called from this function. Avoid calling Objective-C methods.
     *
     * **Default**: NULL
     */
    KSReportWriteCallback crashNotifyCallback;

    /** Callback to invoke upon finishing writing a crash report.
     *
     * This function is called after a crash report has been written. It allows the caller
     * to react to the completion of the report. Only async-safe functions should be called
     * from this function. Avoid calling Objective-C methods.
     *
     * **Default**: NULL
     */
    KSReportWrittenCallback reportWrittenCallback;

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
     * **Default**: true
     */
    bool enableSwapCxaThrow;
} KSCrashCConfiguration;

static inline KSCrashCConfiguration KSCrashCConfiguration_Default(void)
{
    return (KSCrashCConfiguration) {
        .reportStoreConfiguration = KSCrashReportStoreCConfiguration_Default(),
        .monitors = KSCrashMonitorTypeProductionSafeMinimal,
        .userInfoJSON = NULL,
        .deadlockWatchdogInterval = 0.0,
        .enableQueueNameSearch = false,
        .enableMemoryIntrospection = false,
        .doNotIntrospectClasses = { .strings = NULL, .length = 0 },
        .crashNotifyCallback = NULL,
        .reportWrittenCallback = NULL,
        .addConsoleLogToReport = false,
        .printPreviousLogOnStartup = false,
        .enableSwapCxaThrow = true,
    };
}

static inline void KSCrashCConfiguration_Release(KSCrashCConfiguration *configuration)
{
    KSCrashReportStoreCConfiguration_Release(&configuration->reportStoreConfiguration);
    free((void *)configuration->userInfoJSON);
    for (int idx = 0; idx < configuration->doNotIntrospectClasses.length; ++idx) {
        free((void *)(configuration->doNotIntrospectClasses.strings[idx]));
    }
    free(configuration->doNotIntrospectClasses.strings);
}

#ifdef __cplusplus
}
#endif

#endif /* KSCrashCConfiguration_h */
