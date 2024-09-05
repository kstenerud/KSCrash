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
#import "KSCrashMonitorType.h"
#import "KSCrashReportWriter.h"

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
 */
@property(nonatomic, assign) double deadlockWatchdogInterval;

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

/** Callback to invoke upon a crash.
 *
 * This function is called during the crash reporting process, providing an opportunity
 * to add additional information to the crash report. Only async-safe functions should
 * be called from this function. Avoid calling Objective-C/Swift methods.
 *
 * **Default**: NULL
 */
@property(nonatomic, copy, nullable) void (^crashNotifyCallback)(const struct KSCrashReportWriter *writer);

/** Callback to invoke upon finishing writing a crash report.
 *
 * This function is called after a crash report has been written. It allows the caller
 * to react to the completion of the report. Only async-safe functions should be called
 * from this function. Avoid calling Objective-C methods.
 *
 * **Default**: NULL
 */
@property(nonatomic, copy, nullable) void (^reportWrittenCallback)(int64_t reportID);

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
 * **Default**: true
 */
@property(nonatomic, assign) BOOL enableSwapCxaThrow;

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

@end

NS_ASSUME_NONNULL_END
