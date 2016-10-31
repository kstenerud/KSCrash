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

#include <sys/types.h>

#define KSCRS_MAX_PATH_LENGTH 500

/** Initialize the report store.
 *
 * @param appName The application's name.
 * @param reportsPath Full path to where the reports are to be stored.
 */
void kscrs_initialize(const char* appName, const char* reportsPath);

/** Get the paths to the next crash report components to be generated.
 * Max length for paths is KSCRS_MAX_PATH_LENGTH
 *
 * @param crashReportPathBuffer Buffer to store the crash report path.
 * @param recrashReportPathBuffer Buffer to store the recrash report path.
 */
void kscrs_getCrashReportPaths(char* crashReportPathBuffer, char* recrashReportPathBuffer);

/** Get the number of reports on disk.
 */
int kscrs_getReportCount();


/** Get a list of IDs for all reports on disk.
 *
 * @param reportIDs An array big enough to hold all report IDs.
 * @param count How many reports the array can hold.
 *
 * @return The number of report IDs that were placed in the array.
 */
int kscrs_getReportIDs(int64_t* reportIDs, int count);

/** Read a report.
 *
 * @param reportID The report's ID.
 * @param reportPtr (out) Will be filled with a pointer to the contents of the report, or NULL if not found.
 *                        Caller MUST call free() on the returned pointer if not NULL.
 * @param reportLengthPtr (out) Will be filled with the length of the report in bytes, or 0 if not found.
 * @param recrashPtr (out) Will be filled with a pointer to the contents of the recrash report, or NULL if none is persent.
 *                        Caller MUST call free() on the returned pointer if it is not NULL.
 * @param recrashLengthPtr (out) Will be filled with the length of the recrash report in bytes, or 0 if nons is present.
 */
void kscrs_readReport(int64_t reportID, char** reportPtr, int* reportLengthPtr,
                      char** recrashPtr, int* recrashLengthPtr);

/** Add a custom report to the store.
 *
 * @param report The report's contents (must be JSON encoded).
 * @param reportLength The length of the report in bytes.
 */
void kscrs_addUserReport(const char* report, int reportLength);

/** Delete all reports on disk.
 */
void kscrs_deleteAllReports();


/** Increment the crash report index.
 * Internal function. Do not use.
 */
void kscrsi_incrementCrashReportIndex();

/** Get the next crash report ID.
 * Internal function. Do not use.
 */
int64_t kscrsi_getNextCrashReportID();

/** Get the next user report ID.
 * Internal function. Do not use.
 */
int64_t kscrsi_getNextUserReportID();

#if 0

#import <Foundation/Foundation.h>


/**
 * Manages a store of crash reports.
 */
@interface KSCrashReportStore: NSObject

/** Location where reports are stored. */
@property(nonatomic,readonly,retain) NSString* path;

/** The total number of reports. Note: This is an expensive operation. */
@property(nonatomic,readonly,assign) NSUInteger reportCount;

/** If true, demangle any C++ symbols found in stack traces. */
@property(nonatomic,readwrite,assign) BOOL demangleCPP;

/** If true, demangle any Swift symbols found in stack traces. */
@property(nonatomic,readwrite,assign) BOOL demangleSwift;

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

/** Get a list of all reports.
 *
 * @return A list of reports in chronological order (oldest first).
 */
- (NSArray*) allReports;

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

/** Add a custom report to the store.
 *
 * @param report The report to store. This method will add a standard top-level "report" section to it.
 *
 * @return The report ID
 */
- (NSString*) addCustomReport:(NSDictionary*) report;

@end
#endif
