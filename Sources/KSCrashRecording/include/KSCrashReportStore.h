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
#import "KSCrashReportFilter.h"

NS_ASSUME_NONNULL_BEGIN

@class KSCrashReportDictionary;
@class KSCrashReportData;
@class KSCrashReportStoreConfiguration;
@class KSCrashSendConfiguration;

typedef NS_ENUM(NSUInteger, KSCrashReportCleanupPolicy) {
    KSCrashReportCleanupPolicyNever,
    KSCrashReportCleanupPolicyOnSuccess,
    KSCrashReportCleanupPolicyAlways,
} NS_SWIFT_NAME(CrashReportCleanupPolicy);

/** A unique identifier for a crash report. */
typedef int64_t KSCrashReportID NS_SWIFT_NAME(CrashReportID);

/** Sentinel value indicating no report is available. */
FOUNDATION_EXTERN const KSCrashReportID KSCrashReportNoID;

NS_SWIFT_NAME(CrashReportStore)
@interface KSCrashReportStore : NSObject

/** The default folder name inside the KSCrash install path that is used for report store.
 */
@property(nonatomic, class, copy, readonly) NSString *defaultInstallSubfolder;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** The report store with the default configuration.
 *
 * @param error If an error occurs, upon return contains an NSError object that
 *               describes the problem.
 *
 * @return The default report store or `nil` if an error occurred.
 */
+ (nullable instancetype)defaultStoreWithError:(NSError **)error;

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

/** The total number of unsent reports. Note: This is an expensive operation.
 */
@property(nonatomic, readonly, assign) NSInteger reportCount;

#pragma mark - Reports API

/** Get all unsent report IDs. */
@property(nonatomic, readonly, strong) NSArray<NSNumber *> *reportIDs;

/** Get the oldest unsent report ID, or KSCrashReportNoID if the store is empty. */
@property(nonatomic, readonly, assign) KSCrashReportID nextReportID;

/** Send all outstanding crash reports using the given send configuration.
 *
 * Reports are run through @c configuration.reportFilters in order; the last
 * filter is the terminal sink that actually delivers them. An empty
 * @c reportFilters chain completes with an error.
 *
 * It will only attempt to send the most recent reports; all others will be
 * deleted. Depending on @c configuration.reportCleanupPolicy the sent reports
 * may then be deleted locally.
 *
 * Reports from the current process run are excluded because they may still
 * be updated while the process is alive. To send a specific report by ID
 * (including current-run reports), use
 * @c sendReportWithID:configuration:completion:.
 *
 * @param configuration The filter chain and cleanup policy to use.
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void)sendAllReportsWithConfiguration:(KSCrashSendConfiguration *)configuration
                             completion:(nullable KSCrashReportFilterCompletion)onCompletion
    NS_SWIFT_NAME(sendAllReports(with:completion:));

/** Send a single report by ID using the given send configuration.
 *
 * Equivalent to calling
 * @c sendReportWithID:includeCurrentRun:configuration:completion: with @c YES.
 *
 * @param reportID The ID of the report to send.
 * @param configuration The filter chain and cleanup policy to use.
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void)sendReportWithID:(KSCrashReportID)reportID
           configuration:(KSCrashSendConfiguration *)configuration
              completion:(nullable KSCrashReportFilterCompletion)onCompletion
    NS_SWIFT_NAME(sendReport(id:with:completion:));

/** Send a single report by ID, optionally including current-run reports.
 *
 * @param reportID The ID of the report to send.
 * @param includeCurrentRun If YES, sends the report even if it belongs to the current run.
 *                          If NO and the report is from the current run, calls onCompletion
 *                          with an error.
 * @param configuration The filter chain and cleanup policy to use.
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void)sendReportWithID:(KSCrashReportID)reportID
       includeCurrentRun:(BOOL)includeCurrentRun
           configuration:(KSCrashSendConfiguration *)configuration
              completion:(nullable KSCrashReportFilterCompletion)onCompletion
    NS_SWIFT_NAME(sendReport(id:includeCurrentRun:with:completion:));

/** Get report.
 *
 * @param reportID An ID of report.
 *
 * @return A crash report with a dictionary value. The dictionary fields are described in KSCrashReportFields.h.
 */
- (nullable KSCrashReportDictionary *)reportForID:(KSCrashReportID)reportID NS_SWIFT_NAME(report(for:));

/** Get report Data.
 *
 * @param reportID An ID of report.
 *
 * @return A crash report with a data value.
 */
- (nullable KSCrashReportData *)reportDataForID:(int64_t)reportID NS_SWIFT_NAME(reportData(for:));

/** Delete all unsent reports.
 */
- (void)deleteAllReports;

/** Delete report.
 *
 * @param reportID An ID of report to delete.
 */
- (void)deleteReportWithID:(KSCrashReportID)reportID NS_SWIFT_NAME(deleteReport(with:));

/** Remove run sidecar directories that no longer have matching reports.
 *
 * Called automatically within @c sendAllReportsWithConfiguration:completion:.
 * If you handle report delivery yourself, call this periodically or after sending reports.
 * May block, so prefer calling from a background thread.
 */
- (void)cleanupOrphanedRunSidecars;

@end

NS_ASSUME_NONNULL_END
