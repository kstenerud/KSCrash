//
//  KSCrashCConfiguration.h
//
//
//  Created by Gleb Linnik on 10.06.2024.
//

#ifndef KSCrashCConfiguration_h
#define KSCrashCConfiguration_h

#ifdef __cplusplus
extern "C" {
#endif

/** Structure to hold an array of strings with their length.
 */
typedef struct {
    const char** strings; /**< Array of strings. */
    int length; /**< Length of the array. */
} KSCrashStringArray;

/** Callback type for when a crash report is written.
 *
 * @param reportID The ID of the report that was written.
 */
typedef void (*KSReportWrittenCallback)(int64_t reportID);

typedef enum KSCrashMonitorType;

/** Configuration for KSCrash settings.
 */
typedef struct {
    /** The crash types that will be handled.
     * Some crash types may not be enabled depending on circumstances (e.g., running in a debugger).
     */
    KSCrashMonitorType monitors;

    /** User-supplied data in JSON format. NULL to delete.
     *
     * This JSON string contains user-specific data that will be included in
     * the crash report. If NULL is passed, any existing user data will be deleted.
     */
    const char* userInfoJSON;

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
    KSCrashStringArray doNotIntrospectClasses;

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

    /** The maximum number of crash reports allowed on disk before old ones get deleted.
     *
     * Specifies the maximum number of crash reports to keep on disk. When this limit
     * is reached, the oldest reports will be deleted to make room for new ones.
     *
     * **Default**: 5
     */
    int maxReportCount;

    /** If true, enable C++ exceptions catching with `__cxa_throw` swap.
     *
     * This experimental feature works similarly to `LD_PRELOAD` and supports catching
     * C++ exceptions by swapping the `__cxa_throw` function. It helps in obtaining
     * accurate stack traces even in dynamically linked libraries and allows overriding
     * the original `__cxa_throw` with a custom implementation.
     *
     * **Default**: false
     */
    bool enableSwapCxaThrow;
} KSCrashConfiguration;

#define KSCrashConfiguration_Default \
KSCrashConfiguration { \
.monitors = 0, \
.userInfoJSON = NULL, \
.deadlockWatchdogInterval = 0.0, \
.enableQueueNameSearch = false, \
.enableMemoryIntrospection = false, \
.doNotIntrospectClasses = { NULL, 0 }, \
.crashNotifyCallback = NULL, \
.reportWrittenCallback = NULL, \
.addConsoleLogToReport = false, \
.printPreviousLogOnStartup = false, \
.maxReportCount = 5, \
.enableSwapCxaThrow = false \
}

#ifdef __cplusplus
}
#endif

#endif /* KSCrashCConfiguration_h */

