//
//  KSCrash.h
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

#import <Foundation/Foundation.h>

#import "KSCrashMonitorType.h"
#import "KSCrashReportFilter.h"
#import "KSCrashReportStore.h"
#import "KSCrashReportWriter.h"

NS_ASSUME_NONNULL_BEGIN

@class KSCrashConfiguration;
@class KSCrashReportDictionary;

/**
 * Reports any crashes that occur in the application.
 *
 * The crash reports will be located in $APP_HOME/Library/Caches/KSCrashReports
 */
@interface KSCrash : NSObject

#pragma mark - Configuration -

/** A dictionary containing any info you'd like to appear in crash reports. Must
 * contain only JSON-safe data: NSString for keys, and NSDictionary, NSArray,
 * NSString, NSDate, and NSNumber for values.
 *
 * Default: nil
 */
@property(atomic, readwrite, strong, nullable) NSDictionary<NSString *, id> *userInfo;

#pragma mark - Information -

/** Exposes the uncaughtExceptionHandler if set from KSCrash. Is nil if debugger is running. */
@property(nonatomic, readonly, assign) NSUncaughtExceptionHandler *uncaughtExceptionHandler;

/** Exposes the currentSnapshotUserReportedExceptionHandler if set from KSCrash.  Is nil if debugger is running. */
@property(nonatomic, readonly, assign) NSUncaughtExceptionHandler *currentSnapshotUserReportedExceptionHandler;

/** Total active time elapsed since the last crash. */
@property(nonatomic, readonly, assign) NSTimeInterval activeDurationSinceLastCrash;

/** Total time backgrounded elapsed since the last crash. */
@property(nonatomic, readonly, assign) NSTimeInterval backgroundDurationSinceLastCrash;

/** Number of app launches since the last crash. */
@property(nonatomic, readonly, assign) NSInteger launchesSinceLastCrash;

/** Number of sessions (launch, resume from suspend) since last crash. */
@property(nonatomic, readonly, assign) NSInteger sessionsSinceLastCrash;

/** Total active time elapsed since launch. */
@property(nonatomic, readonly, assign) NSTimeInterval activeDurationSinceLaunch;

/** Total time backgrounded elapsed since launch. */
@property(nonatomic, readonly, assign) NSTimeInterval backgroundDurationSinceLaunch;

/** Number of sessions (launch, resume from suspend) since app launch. */
@property(nonatomic, readonly, assign) NSInteger sessionsSinceLaunch;

/** If true, the application crashed on the previous launch. */
@property(nonatomic, readonly, assign) BOOL crashedLastLaunch;

/** Information about the operating system and environment.
 *
 * @note `bootTime` and `storageSize` are not populated in this property.
 * To access these values, refer to the optional
 * `KSCrashBootTimeMonitor` and `KSCrashDiscSpaceMonitor` modules.
 */
@property(nonatomic, readonly, strong) NSDictionary<NSString *, id> *systemInfo;

#pragma mark - API -

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Get the singleton instance of the crash reporter.
 */
@property(class, readonly) KSCrash *sharedInstance NS_SWIFT_NAME(shared);

/** Install the crash reporter.
 * The reporter will record crashes, but will not send any crash reports unless a sink is set.
 *
 * @param configuration The configuration to use for installation.
 * @param error A pointer to an NSError object. If an error occurs, this pointer is set to an actual error object
 *              containing the error information. You may specify nil for this parameter if you do not want
 *              the error information.
 * @return YES if the reporter successfully installed, NO otherwise.
 *
 * @note If the installation fails, the error parameter will contain information about the failure reason.
 * @note Once installed, the crash reporter cannot be re-installed or modified without restarting the application.
 */
- (BOOL)installWithConfiguration:(KSCrashConfiguration *)configuration error:(NSError **)error;

/** The installed report store.
 * This is the store that is used to save and load crash reports.
 *
 * @note If the crash reporter is not installed, this will be `nil`.
 */
@property(nonatomic, strong, readonly, nullable) KSCrashReportStore *reportStore;

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
 * @param lineOfCode A copy of the offending line of code (nil = ignore).
 *
 * @param stackTrace An array of frames (dictionaries or strings) representing the call stack leading to the exception
 * (nil = ignore).
 *
 * @param logAllThreads If true, suspend all threads and log their state. Note that this incurs a
 *                      performance penalty, so it's best to use only on fatal errors.
 *
 * @param terminateProgram If true, do not return from this function call. Terminate the program instead.
 */
- (void)reportUserException:(NSString *)name
                     reason:(nullable NSString *)reason
                   language:(nullable NSString *)language
                 lineOfCode:(nullable NSString *)lineOfCode
                 stackTrace:(nullable NSArray *)stackTrace
              logAllThreads:(BOOL)logAllThreads
           terminateProgram:(BOOL)terminateProgram;

@end

//! Project version number for KSCrashFramework.
FOUNDATION_EXPORT const double KSCrashFrameworkVersionNumber;

//! Project version string for KSCrashFramework.
FOUNDATION_EXPORT const unsigned char KSCrashFrameworkVersionString[];

NS_ASSUME_NONNULL_END
