//
//  KSCrashReporter.h
//
//  Created by Karl Stenerud on 12-02-05.
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


/**
 * Manages a store of crash reports.
 */
@interface KSCrashReportStore: NSObject

/** Create a new store.
 *
 * @param path The path to the crash reports directory.
 *
 * @param filenamePrefix A filename prefix that identifies crash report files.
 *
 * @return A new crash report store.
 */
+ (KSCrashReportStore*) storeWithPath:(NSString*) path
                       filenamePrefix:(NSString*) filenamePrefix;

/** Initialize a store.
 *
 * @param path The path to the crash reports directory.
 *
 * @param filenamePrefix A filename prefix that identifies crash report files.
 *
 * @return The initialized crash report store.
 */
- (id) initWithPath:(NSString*) path
     filenamePrefix:(NSString*) filenamePrefix;

/** Get a list of report names.
 *
 * @return A list of report names in chronological order (oldest first).
 */
- (NSArray*) reportNames;

/** Fetch a report.
 *
 * @param name The name of the report to fetch.
 *
 * @return The report or nil if not found.
 */
- (NSDictionary*) reportNamed:(NSString*) name;

/** Get a list of all reports.
 *
 * @return A list of reports in chronological order (oldest first).
 */
- (NSArray*) allReports;

/** Delete a report.
 *
 * @param name The report name.
 */
- (void) deleteReportNamed:(NSString*) name;

/** Delete all reports.
 */
- (void) deleteAllReports;

/** Prune reports, keeping only the newest ones.
 *
 * @param numReports the number of reports to keep.
 */
- (void) pruneReportsLeaving:(int) numReports;

@end
