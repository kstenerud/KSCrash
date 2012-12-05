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
#import "KSCrashReportStore.h"


/** Advanced interface to the KSCrash system.
 */
@interface KSCrash ()

/** Get the global instance.
 */
+ (KSCrash*) instance;

/** The report sink where reports get sent. */
@property(nonatomic,readwrite,retain) id<KSCrashReportFilter> sink;

/** If YES, delete any reports that are successfully sent. */
@property(nonatomic,readwrite,assign) BOOL deleteAfterSend;

/** The total number of unsent reports. Note: This is an expensive operation. */
@property(nonatomic,readonly,assign) NSUInteger reportCount;

/** Where the crash reports are stored. */
@property(nonatomic,readonly,retain) NSString* crashReportsPath;

/** Store containing all crash reports. */
@property(nonatomic,readwrite,retain) KSCrashReportStore* crashReportStore;

/** Send any outstanding crash reports to the current sink.
 * It will only attempt to send the most recent 5 reports. All others will be
 * deleted. Once the reports are successfully sent to the server, they may be
 * deleted locally, depending on the property "deleteAfterSend".
 *
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void) sendAllReportsWithCompletion:(KSCrashReportFilterCompletion) onCompletion;

/** Send the specified reports to the current sink.
 *
 * @param reports The reports to send.
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void) sendReports:(NSArray*) reports onCompletion:(KSCrashReportFilterCompletion) onCompletion;

/** Get all reports, with data types corrected, as dictionaries.
 */
- (NSArray*) allReports;

/** Delete all unsent reports.
 */
- (void) deleteAllReports;

/** Redirect all log entries to the specified log file.
 *
 * @param filename The path to the logfile.
 * @param overwrite If true, overwrite the file.
 *
 * @return true if the operation was successful.
 */
+ (BOOL) redirectLogsToFile:(NSString*) filename overwrite:(BOOL) overwrite;

/** Redirect all log entries to Library/Caches/KSCrashReports/log.txt.
 * If the file exists, it will be overwritten.
 *
 * @return true if the operation was successful.
 */
+ (BOOL) logToFile;

/** TODO: Figure out how to get a collection of filename + data of everything
 * in the reports dir, ready to be attached to an email.
 * Must be able to specify maximum size.
 */
//- (NSArray*) reportsDirectoryContents;

@end

