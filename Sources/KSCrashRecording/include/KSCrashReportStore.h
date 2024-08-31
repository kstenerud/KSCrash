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

#import "KSCrashReportFilter.h"

NS_ASSUME_NONNULL_BEGIN

@class KSCrashReportDictionary;
@class KSCrashReportStoreConfiguration;

typedef NS_ENUM(NSUInteger, KSCDeleteBehavior) {
    KSCDeleteNever,
    KSCDeleteOnSucess,
    KSCDeleteAlways
} NS_SWIFT_NAME(DeleteBehavior);

NS_SWIFT_NAME(CrashReportStore)
@interface KSCrashReportStore : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** TODO: Add doc
 */
+ (nullable instancetype)defaultStoreWithError:(NSError **)error;

/** TODO: doc
 */
+ (instancetype)storeWithConfiguration:(nullable KSCrashReportStoreConfiguration *)configuration
                                 error:(NSError **)error;

#pragma mark - Configuration

/** The report sink where reports get sent.
 * This MUST be set or else the reporter will not send reports (although it will
 * still record them).
 *
 * Note: If you use an installation, it will automatically set this property.
 *       Do not modify it in such a case.
 */
@property(nonatomic, readwrite, strong, nullable) id<KSCrashReportFilter> sink;

/** What to do after sending reports via sendAllReportsWithCompletion:
 *
 * - Use KSCDeleteNever if you will manually manage the reports.
 * - Use KSCDeleteAlways if you will be using an alert confirmation (otherwise it
 *   will nag the user incessantly until he selects "yes").
 * - Use KSCDeleteOnSuccess for all other situations.
 *
 * Default: KSCDeleteAlways
 */
@property(nonatomic, assign) KSCDeleteBehavior deleteBehaviorAfterSendAll;

#pragma mark - Reports API

/** Get all unsent report IDs. */
@property(nonatomic, readonly, strong) NSArray<NSNumber *> *reportIDs;

/** Send all outstanding crash reports to the current sink.
 * It will only attempt to send the most recent 5 reports. All others will be
 * deleted. Once the reports are successfully sent to the server, they may be
 * deleted locally, depending on the property "deleteAfterSendAll".
 *
 * @note A call of `setupReportStoreWithPath:error:` or `installWithConfiguration:error:` is required
 *       before working with crash reports.
 * @note Property "sink" MUST be set or else this method will call `onCompletion` with an error.
 *
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void)sendAllReportsWithCompletion:(nullable KSCrashReportFilterCompletion)onCompletion;

/** Get report.
 *
 * @note A call of `setupReportStoreWithPath:error:` or `installWithConfiguration:error:` is required
 *       before working with crash reports.
 *
 * @param reportID An ID of report.
 *
 * @return A crash report with a dictionary value. The dectionary fields are described in KSCrashReportFields.h.
 */
- (nullable KSCrashReportDictionary *)reportForID:(int64_t)reportID NS_SWIFT_NAME(report(for:));

/** Delete all unsent reports.
 * @note A call of `setupReportStoreWithPath:error:` or `installWithConfiguration:error:` is required
 *       before working with crash reports.
 */
- (void)deleteAllReports;

/** Delete report.
 *
 * @note A call of `setupReportStoreWithPath:error:` or `installWithConfiguration:error:` is required
 *       before working with crash reports.
 *
 * @param reportID An ID of report to delete.
 */
- (void)deleteReportWithID:(int64_t)reportID NS_SWIFT_NAME(deleteReport(with:));

@end

NS_ASSUME_NONNULL_END
