//
//  KSCrashReportWriterCallbacks.h
//
//  Created by Gleb Linnik on 2025-08-17.
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

#ifndef HDR_KSCrashReportWriterCallbacks_h
#define HDR_KSCrashReportWriterCallbacks_h

#include "KSCrashExceptionHandlingPlan.h"
#include "KSCrashNamespace.h"

#ifndef NS_SWIFT_UNAVAILABLE
#define NS_SWIFT_UNAVAILABLE(_msg)
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Various callbacks that will be called while handling a crash.
// The calling order is:
// * KSCrashWillWriteReportCallback
// * KSCrashIsWritingReportCallback
// * KSCrashDidWriteReportCallback

/** Callback type for when a crash has been detected, and we are about to write a report.
 * At this point, the user may alter the plan for how or whether to write the report.
 *
 * @see KSCrash_ExceptionHandlingPlan for a list of which parts of the plan can be modified.
 *
 * WARNING: The `context` parameter is an INTERNAL structure, which WILL change between minor versions!
 * It gives a lot of insight into what's going on during a crash - which makes it very powerful - but if you use it, it
 * will be YOUR responsibility to check for breakage between minor versions!
 *
 * @param plan The plan under which the report will be written.
 * @param context The monitor context of the report. WARNING: Subject to change without notice!
 */
typedef void (*KSCrashWillWriteReportCallback)(KSCrash_ExceptionHandlingPlan *_Nonnull const plan,
                                               const struct KSCrash_MonitorContext *_Nonnull context)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

/** Callback type for when a crash report is being written, giving the user an opportunity to add custom data to the
 * `user` section of the report.
 *
 * @param plan The plan under which the report is being written.
 * @param writer The report writer.
 */
typedef void (*KSCrashIsWritingReportCallback)(const KSCrash_ExceptionHandlingPlan *_Nonnull const plan,
                                               const KSCrashReportWriter *_Nonnull writer)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

/** Callback type for when a crash report is finished writing.
 *
 * @param plan The plan under which the report was written.
 * @param reportID The ID of the report that was written.
 */
typedef void (*KSCrashDidWriteReportCallback)(const KSCrash_ExceptionHandlingPlan *_Nonnull const plan,
                                              int64_t reportID) NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashReportWriterCallbacks_h
