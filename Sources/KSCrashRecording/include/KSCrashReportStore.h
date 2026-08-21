//
//  KSCrashReportStore.h
//
//  Created by Nikolay Volosatov on 2024-08-28.
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

#include "KSCrashNamespace.h"

NS_ASSUME_NONNULL_BEGIN

@class KSCrashReportStoreConfiguration;

/** A unique identifier for a crash report. */
typedef int64_t KSCrashReportID NS_SWIFT_NAME(CrashReportID);

NS_SWIFT_NAME(CrashReportStore)
@interface KSCrashReportStore : NSObject

/** The default folder name inside the KSCrash install path that is used for report store.
 */
@property(nonatomic, class, copy, readonly) NSString *defaultInstallSubfolder;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** The report store with the given configuration.
 * If the configuration is nil, the default configuration will be used.
 *
 * @param configuration The configuration to use.
 * @param error If an error occurs, upon return contains an NSError object that
 *
 * @return The report store or `nil` if an error occurred.
 */
+ (nullable instancetype)storeWithConfiguration:(nullable KSCrashReportStoreConfiguration *)configuration
                                          error:(NSError **)error;

#pragma mark - Configuration

/** The number of unsent reports; 0 when the store cannot be read (see
 * listReportIDsWithError: for the failure). Note: This is an expensive operation.
 */
@property(nonatomic, readonly, assign) NSInteger reportCount;

#pragma mark - Reports API

/** Get report Data. The JSON fields are described in KSCrashReportFields.h.
 *
 * @param reportID An ID of report.
 * @param error Set when the report could not be read (`NSFileReadUnknownError`)
 * or was read but is not a JSON report (`NSFileReadCorruptFileError`).
 *
 * @return The report's JSON data, or nil on error.
 */
- (nullable NSData *)reportDataForID:(KSCrashReportID)reportID error:(NSError **)error NS_SWIFT_NAME(reportData(for:));

/** The run a report belongs to, from the report file alone: nothing is
 * stitched and no run artifacts are touched.
 *
 * @param reportID An ID of report.
 *
 * @return The run id (a UUID string), or nil when the report cannot be read
 * or records no valid run.
 */
- (nullable NSString *)runIDForReportID:(KSCrashReportID)reportID NS_SWIFT_NAME(runID(of:));

/** Delete all unsent reports.
 */
- (void)deleteAllReports;

/** All unsent report IDs, oldest first.
 *
 * @param error Set when the reports directory cannot be enumerated.
 *
 * @return The report IDs, or nil on error. An empty store is an empty array.
 */
- (nullable NSArray<NSNumber *> *)listReportIDsWithError:(NSError **)error;

/** Delete one report.
 *
 * @param reportID The ID of the report to delete.
 * @param error Set when the report file could not be removed.
 *
 * @return YES if the report file was removed.
 */
- (BOOL)removeReportWithID:(KSCrashReportID)reportID error:(NSError **)error;

/** Remove on-disk run data (run sidecar directories and session sidecars) for
 * runs no longer referenced by any report or run summary.
 *
 * Called automatically within the send flows. If you handle delivery yourself,
 * call this periodically or after sending. May block, so prefer a background thread.
 */
- (void)reclaimOrphanedRunData;

@end

NS_ASSUME_NONNULL_END
