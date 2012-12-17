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

#import "KSCrashReportWriter.h"
#import "KSCrashReportFilter.h"


/**
 * Handles any crashes in the application and generates a crash report.
 *
 * The crash reports will be located in $APP_HOME/Library/Caches/KSCrashReports
 */
@interface KSCrash : NSObject

/** Install the crash reporter with default settings:
 *
 * - No user info (userInfo = nil)
 * - Zombie tracking disabled (zombieCacheSize = 0)
 * - Main thread deadlock detection enabled (deadlockWatchdogInterval = 5.0f)
 * - Don't print to stdout (printTraceToStdout = NO)
 * - No crash callback (onCrash = NULL)
 *
 * @param sink The report sink to send outstanding reports to (can be nil).
 *
 * @return YES if successful.
 */
+ (BOOL) installWithCrashReportSink:(id<KSCrashReportFilter>) sink;

/** Install the crash reporter.
 *
 * @param sink The report sink to send outstanding reports to (can be nil).
 *
 * @param userInfo A dictionary containing any info you'd like to appear in
 *                 crash reports. Must contain only JSON-safe data: NSString
 *                 for keys, and NSDictionary, NSArray, NSString, NSDate, and
 *                 NSNumber for values.
 *                 nil = ignore.
 *
 * @param zombieCacheSize The size of the cache to use for zombie tracking.
 *                        Must be a power-of-2. 0 = no zombie tracking.
 *                        You should profile your app to see how many objects
 *                        are being allocated before choosing this value, but
 *                        generally you should use 16384 or higher. Uses 8 bytes
 *                        per cache entry (16 bytes on 64-bit architectures).
 *
 * @param deadlockWatchdogInterval The interval in seconds between checks for
 *                                 deadlocks on the main thread. 0 = ignore.
 *
 * @param printTraceToStdout If YES, print a stack trace to STDOUT when the app
 *                           crashes.
 *
 * @param onCrash C Function to call during a crash report to give the
 *                callee an opportunity to add to the report. NULL = ignore.
 *                WARNING: Only call async-safe functions from this function!
 *                DO NOT call Objective-C methods!!!
 *
 * @return YES if successful.
 */
+ (BOOL) installWithCrashReportSink:(id<KSCrashReportFilter>) sink
                           userInfo:(NSDictionary*) userInfo
                    zombieCacheSize:(unsigned int) zombieCacheSize
           deadlockWatchdogInterval:(float) deadlockWatchdogInterval
                 printTraceToStdout:(BOOL) printTraceToStdout
                            onCrash:(KSReportWriteCallback) onCrash;

/** Set the user-supplied information.
 *
 * @param userInfo A dictionary containing any info you'd like to appear in
 *                 crash reports. Must contain only JSON-safe data: NSString
 *                 for keys, and NSDictionary, NSArray, NSString, NSDate, and
 *                 NSNumber for values.
 *                 nil = delete.
 */
+ (void) setUserInfo:(NSDictionary*) userInfo;

@end
