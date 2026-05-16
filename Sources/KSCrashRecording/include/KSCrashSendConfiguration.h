//
//  KSCrashSendConfiguration.h
//
//  Created by Alexander Cohen on 2026-05-16.
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
#import "KSCrashReportStore.h"
#import "KSCrashRunFilter.h"

NS_ASSUME_NONNULL_BEGIN

/** Per-send configuration: the filter chains and cleanup policy used when
 *  sending crash reports or run summaries.
 *
 *  Pass an instance to the `KSCrash` / `KSCrashReportStore` send methods. The
 *  same configuration can be reused across calls; each method only reads the
 *  fields relevant to it (report sends ignore `runSummaryFilters`, run-summary
 *  sends ignore `reportFilters` and `reportCleanupPolicy`).
 */
NS_SWIFT_NAME(CrashSendConfiguration)
@interface KSCrashSendConfiguration : NSObject <NSCopying>

/** Ordered filter chain for crash reports. The output of each filter feeds the
 *  next; the last filter is the terminal sink that delivers the reports.
 *  An empty chain causes report sends to complete with an error.
 *
 *  **Default**: empty
 */
@property(nonatomic, copy) NSArray<id<KSCrashReportFilter>> *reportFilters;

/** Ordered filter chain for run summaries. The output of each filter feeds the
 *  next; the last filter is the terminal sink that delivers the summaries.
 *  An empty chain causes run-summary sends to complete with an error.
 *
 *  **Default**: empty
 */
@property(nonatomic, copy) NSArray<id<KSCrashRunFilter>> *runSummaryFilters;

/** What to do with crash reports after sending. Has no effect on run summaries
 *  (delivered summaries are always removed; the rest are retried).
 *
 *  **Default**: `KSCrashReportCleanupPolicyAlways`
 */
@property(nonatomic, assign) KSCrashReportCleanupPolicy reportCleanupPolicy;

@end

NS_ASSUME_NONNULL_END
