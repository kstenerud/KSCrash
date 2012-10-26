//
//  KSCrashReportStore.h
//
//  Created by Karl Stenerud on 2012-02-05.
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

/** Location where reports are stored. */
@property(nonatomic,readonly,retain) NSString* path;

/** The total number of reports. Note: This is an expensive operation. */
@property(nonatomic,readonly,assign) NSUInteger reportCount;


/** Create a new store.
 *
 * @param path Where to store crash reports.
 *
 * @return A new crash report store.
 */
+ (KSCrashReportStore*) storeWithPath:(NSString*) path;

/** Initialize a store.
 *
 * @param path Where to store crash reports.
 *
 * @return The initialized crash report store.
 */
- (id) initWithPath:(NSString*) path;

/** Get a list of report IDs.
 *
 * @return A list of report IDs in chronological order (oldest first).
 */
- (NSArray*) reportIDs;

/** Fetch a report.
 *
 * @param reportID The ID of the report to fetch.
 *
 * @return The report or nil if not found.
 */
- (NSDictionary*) reportWithID:(NSString*) reportID;

/** Get a list of all reports.
 *
 * @return A list of reports in chronological order (oldest first).
 */
- (NSArray*) allReports;

/** Delete a report.
 *
 * @param reportID The report ID.
 */
- (void) deleteReportWithID:(NSString*) reportID;

/** Delete all reports.
 */
- (void) deleteAllReports;

/** Prune reports, keeping only the newest ones.
 *
 * @param numReports the number of reports to keep.
 */
- (void) pruneReportsLeaving:(int) numReports;

/** Full path to the crash report with the specified ID.
 *
 * @param reportID The report ID
 *
 * @return The full path.
 */
- (NSString*) pathToCrashReportWithID:(NSString*) reportID;

/** Full path to the recrash report with the specified ID.
 *
 * @param reportID The report ID
 *
 * @return The full path.
 */
- (NSString*) pathToRecrashReportWithID:(NSString*) reportID;

@end
