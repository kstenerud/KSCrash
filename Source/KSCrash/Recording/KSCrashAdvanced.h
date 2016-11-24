//
//  KSCrashAdvanced.h
//
//  Created by Karl Stenerud on 2012-05-06.
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


#import "KSCrash.h"
#import "KSCrashReportFilter.h"

typedef enum
{
    KSCrashDemangleLanguageNone = 0,
    KSCrashDemangleLanguageCPlusPlus = 1,
    KSCrashDemangleLanguageSwift = 2,
    KSCrashDemangleLanguageAll = ~1
} KSCrashDemangleLanguage;

/**
 * Advanced interface to the KSCrash system.
 */
@interface KSCrash (Advanced)

#pragma mark - Information -

/** Total active time elapsed since the last crash. */
@property(nonatomic,readonly,assign) NSTimeInterval activeDurationSinceLastCrash;

/** Total time backgrounded elapsed since the last crash. */
@property(nonatomic,readonly,assign) NSTimeInterval backgroundDurationSinceLastCrash;

/** Number of app launches since the last crash. */
@property(nonatomic,readonly,assign) int launchesSinceLastCrash;

/** Number of sessions (launch, resume from suspend) since last crash. */
@property(nonatomic,readonly,assign) int sessionsSinceLastCrash;

/** Total active time elapsed since launch. */
@property(nonatomic,readonly,assign) NSTimeInterval activeDurationSinceLaunch;

/** Total time backgrounded elapsed since launch. */
@property(nonatomic,readonly,assign) NSTimeInterval backgroundDurationSinceLaunch;

/** Number of sessions (launch, resume from suspend) since app launch. */
@property(nonatomic,readonly,assign) int sessionsSinceLaunch;

/** If true, the application crashed on the previous launch. */
@property(nonatomic,readonly,assign) BOOL crashedLastLaunch;

/** Which languages to demangle when getting stack traces (default KSCrashDemangleLanguageAll) */
@property(nonatomic,readwrite,assign) KSCrashDemangleLanguage demangleLanguages;

/** The total number of unsent reports. Note: This is an expensive operation.
 */
- (NSUInteger) reportCount;


#pragma mark - Configuration -

/** Init KSCrash instance with custom report files directory path. */
//- (id) initWithReportFilesDirectory:(NSString *)reportFilesDirectory;

/** Store containing all crash reports. */
//@property(nonatomic, readwrite, retain) KSCrashReportStore* crashReportStore;

/** The report sink where reports get sent.
 * This MUST be set or else the reporter will not send reports (although it will
 * still record them).
 *
 * Note: If you use an installation, it will automatically set this property.
 *       Do not modify it in such a case.
 */
@property(nonatomic,readwrite,retain) id<KSCrashReportFilter> sink;

/** C Function to call during a crash report to give the callee an opportunity to
 * add to the report. NULL = ignore.
 *
 * WARNING: Only call async-safe functions from this function! DO NOT call
 * Objective-C methods!!!
 *
 * Note: If you use an installation, it will automatically set this property.
 *       Do not modify it in such a case.
 */
@property(nonatomic,readwrite,assign) KSReportWriteCallback onCrash;

/** Path where the log of KSCrash's activities will be written.
 * If nil, log entries will be printed to the console.
 *
 * This property cannot be set directly. Use one of the "redirectConsoleLogs"
 * methods instead.
 *
 * Default: nil
 */
@property(nonatomic,readonly,retain) NSString* logFilePath;

/** If YES, print a stack trace to stdout when a crash occurs.
 *
 * Default: NO
 */
@property(nonatomic,readwrite,assign) bool printTraceToStdout;

/** Redirect KSCrash's console log messages to a file inside the Data dir.
 * @return true if the operation was successful.
 */
- (BOOL) redirectConsoleLogToFile;


#pragma mark - Operations -

/** Send the specified reports to the current sink.
 *
 * @param reports The reports to send.
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void) sendReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion;

@end
