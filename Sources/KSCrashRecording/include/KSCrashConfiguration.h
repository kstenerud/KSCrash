//
//  KSCrashConfiguration.h
//
//  Created by Gleb Linnik on 11.06.2024.
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

#import <Foundation/Foundation.h>
#import "KSCrashCConfiguration.h"
#import "KSCrashExceptionHandlingPlan.h"
#import "KSCrashMonitorPlugin.h"
#import "KSCrashMonitorType.h"
#include "KSCrashNamespace.h"
#import "KSCrashReportStore.h"
#import "KSCrashReportWriter.h"
#import "KSCrashReportWriterCallbacks.h"
#import "KSSystemCapabilities.h"

NS_ASSUME_NONNULL_BEGIN

@class KSCrashReportStoreConfiguration;

@interface KSCrashConfiguration : NSObject <NSCopying>

/** Specifies a custom base path for KSCrash installation.
 * If `nil` the default directory is used:.
 * The default directory is "KSCrash" inside the default cache directory.
 *
 * **Default**: `nil`
 */
@property(nonatomic, copy, nullable) NSString *installPath;

/** The configuration for report store.
 * @note See `KSCrashStoreConfiguration` for more details.
 */
@property(nonatomic, strong) KSCrashReportStoreConfiguration *reportStoreConfiguration;

/** The crash types that will be handled.
 * Some crash types may not be enabled depending on circumstances (e.g., running in a debugger).
 *
 * **Default**: `KSCrashMonitorTypeProductionSafeMinimal`
 */
@property(nonatomic, assign) KSCrashMonitorType monitors;

/** User-supplied data in JSON format. NULL to delete.
 *
 * This JSON string contains user-specific data that will be included in
 * the crash report. If NULL is passed, any existing user data will be deleted.
 */
@property(nonatomic, copy, nullable) NSDictionary<NSString *, id> *userInfoJSON;

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
 *
 * @note Deprecated. Use `KSCrashMonitorTypeWatchdog` in the `monitors` property instead.
 * The watchdog monitor provides better hang detection with a fixed 250ms threshold.
 */
@property(nonatomic, assign)
    double deadlockWatchdogInterval KSCRASH_DEPRECATED("Use KSCrashMonitorTypeWatchdog in monitors instead.");

/** If true, attempt to fetch dispatch queue names for each running thread.
 *
 * This option enables the retrieval of dispatch queue names for each thread at the
 * time of a crash. This can provide useful context, but there is a risk of crashing
 * during the `ksthread_getQueueName()` call.
 *
 * **Default**: false
 */
@property(nonatomic, assign) BOOL enableQueueNameSearch;

/** If true, introspect memory contents during a crash.
 *
 * Enables the inspection of memory contents during a crash. Any Objective-C objects
 * or C strings near the stack pointer or referenced by CPU registers or exceptions
 * will be included in the crash report, along with their contents.
 *
 * **Default**: false
 */
@property(nonatomic, assign) BOOL enableMemoryIntrospection;

/** List of Objective-C classes that should never be introspected.
 *
 * A list of class names that should not be inspected during a crash. Only the class
 * names will be recorded in the crash report when instances of these classes are
 * encountered. This is useful for information security.
 *
 * **Default**: NULL
 */
@property(nonatomic, strong, nullable) NSArray<NSString *> *doNotIntrospectClasses;

/** Callback to invoke before beginning to write a crash report.
 *
 * In this callback, the user can control certain aspects of event handling (such as preventing a report from being
 * written) by modifying the `plan` argument.
 *
 * The `plan` parameter determines what can be safely done within the callback.
 *
 * **Default**: NULL
 */
@property(nonatomic, nullable) KSCrashWillWriteReportCallback willWriteReportCallback;

/** Callback to invoke while writing a crash report.
 *
 * In this callback, the user has an opportunity to add data to the `user` section of the crash report.
 *
 * The `plan` parameter determines what can be safely done within the callback.
 *
 * @see KSCrash_ExceptionHandlingPlan
 *
 * **Default**: NULL
 */
@property(nonatomic, nullable) KSCrashIsWritingReportCallback isWritingReportCallback;

/** Callback to invoke upon finishing writing a crash report.
 *
 * This function is called after a crash report has been written. It allows the caller
 * to react to the completion of the report.
 *
 * The `plan` parameter determines what can be safely done within the callback.
 *
 * @see KSCrash_ExceptionHandlingPlan
 *
 * **Default**: NULL
 */
@property(nonatomic, nullable) KSCrashDidWriteReportCallback didWriteReportCallback;

/** If true, append KSLOG console messages to the crash report.
 *
 * When enabled, KSLOG console messages will be included in the crash report.
 *
 * **Default**: false
 */
@property(nonatomic, assign) BOOL addConsoleLogToReport;

/** If true, print the previous log to the console on startup.
 *
 * This option is for debugging purposes and will print the previous log to the
 * console when the application starts.
 *
 * **Default**: false
 */
@property(nonatomic, assign) BOOL printPreviousLogOnStartup;

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
@property(nonatomic, assign) BOOL enableSwapCxaThrow;

/** If true, enables monitoring for SIGTERM signals.
 *
 * A SIGTERM is usually sent to the application by the OS during a graceful shutdown,
 * but it can also happen on some Watchdog events.
 * Enabling this can provide more insights into the cause of the SIGTERM, but
 * it can also generate many false-positive crash reports.
 *
 * **Default**: false
 */
@property(nonatomic, assign) BOOL enableSigTermMonitoring;

/** If true, use compact binary image reporting.
 *
 * When enabled, the `binary_images` array is filtered to only include
 * images referenced by backtrace frames and images with crash_info.
 * This reduces report size significantly while preserving all data
 * needed for symbolication.
 *
 * **Default**: false
 */
@property(nonatomic, assign) BOOL enableCompactBinaryImages;

/** Plugin monitors to register at install time.
 *
 * An array of objects conforming to `KSCrashMonitorPlugin` protocol.
 * These monitors are copied into static storage and registered via `kscm_addMonitor()`
 * during installation, alongside the built-in monitors.
 *
 * **Default**: nil
 */
@property(nonatomic, copy, nullable) NSArray<id<KSCrashMonitorPlugin>> *plugins;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
/** Callback to invoke upon a crash (DEPRECATED).
 *
 * @deprecated Use `isWritingReportCallback` for async-safety awareness (since v2.4.0).
 * This callback does not receive plan information and may not handle crash
 * scenarios safely (e.g., calling non-async-safe functions during signal handling).
 *
 * This function is called during the crash reporting process, providing an opportunity
 * to add additional information to the crash report.
 *
 * **Default**: NULL
 */
@property(nonatomic, copy, nullable) void (^crashNotifyCallback)(const struct KSCrashReportWriter *writer)
    __attribute__((deprecated("Use `isWritingReportCallback` for async-safety awareness (since v2.4.0).")));
#pragma clang diagnostic pop

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
/** Callback to invoke upon finishing writing a crash report (DEPRECATED).
 *
 * @deprecated Use `didWriteReportCallback` for async-safety awareness (since v2.4.0).
 * This callback does not receive plan information and may not handle crash
 * scenarios safely.
 *
 * This function is called after a crash report has been written. It allows the caller
 * to react to the completion of the report.
 *
 * **Default**: NULL
 */
@property(nonatomic, copy, nullable) void (^reportWrittenCallback)(int64_t reportID)
    __attribute__((deprecated("Use `didWriteReportCallback` for async-safety awareness (since v2.4.0).")));
#pragma clang diagnostic pop

@end

NS_SWIFT_NAME(CrashReportStoreConfiguration)
@interface KSCrashReportStoreConfiguration : NSObject <NSCopying>

/** Specifies a custom directory path for reports store.
 * If `nil` the default directory is used: `Reports` within the installation directory.
 *
 * **Default**: `nil`
 */
@property(nonatomic, copy, nullable) NSString *reportsPath;

/** Specifies a custom app name to be used in report file name.
 * If `nil` the default value is used: `CFBundleName` from Info.plist.
 *
 * **Default**: `nil`
 */
@property(nonatomic, copy, nullable) NSString *appName;

/** The maximum number of crash reports allowed on disk before old ones get deleted.
 *
 * Specifies the maximum number of crash reports to keep on disk. When this limit
 * is reached, the oldest reports will be deleted to make room for new ones.
 *
 * **Default**: 5
 */
@property(nonatomic, assign) NSInteger maxReportCount;

/** What to do after sending reports via `-[KSCrashReportStore sendAllReportsWithCompletion:]`.
 *
 * - Use `KSCrashReportCleanupPolicyNever` if you manually manage the reports.
 * - Use `KSCrashReportCleanupPolicyAlways` if you are using an alert confirmation
 *   (otherwise it will nag the user incessantly until he selects "yes").
 * - Use `KSCrashReportCleanupPolicyOnSucess` for all other situations.
 *
 * Can be updated after creation of report store / installation of KSCrash.
 *
 * **Default**: `KSCrashReportCleanupPolicyAlways`
 */
@property(nonatomic, assign) KSCrashReportCleanupPolicy reportCleanupPolicy;

@end

NS_ASSUME_NONNULL_END
