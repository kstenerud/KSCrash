//
//  KSCrashRunFilter.h
//
//  Created by Alexander Cohen on 2026-04-20.
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

@class KSCrashRunSummary;

/** Callback for run-summary filter operations.
 *
 * @param filteredRuns The filtered run summaries (may be incomplete if error is non-nil).
 * @param error Non-nil if an error occurred.
 */
typedef void (^KSCrashRunFilterCompletion)(NSArray<KSCrashRunSummary *> *_Nullable filteredRuns,
                                           NSError *_Nullable error)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

/**
 * A filter that processes per-run stability summaries (crash-free rate,
 * OOM rate, etc.). Separate from `KSCrashReportFilter` — run summaries
 * and crash reports have different shapes and typically ship to
 * different endpoints.
 *
 * Implementations are typically used as `KSCrashConfiguration.runSink`.
 */
NS_SWIFT_NAME(CrashRunFilter)
@protocol KSCrashRunFilter <NSObject>

/** Filter the specified run summaries.
 *
 * @param runs The run summaries to process.
 * @param onCompletion Block to call when processing is complete.
 */
- (void)filterRuns:(NSArray<KSCrashRunSummary *> *)runs onCompletion:(nullable KSCrashRunFilterCompletion)onCompletion;

@end

NS_ASSUME_NONNULL_END
