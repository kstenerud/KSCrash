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

#include "KSCrashNamespace.h"

#ifndef NS_SWIFT_UNAVAILABLE
#define NS_SWIFT_UNAVAILABLE(_msg)
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Various callbacks that will be called while handling a crash.
// The calling order is:
// * KSCrashEventNotifyCallback
// * KSReportWriteCallbackWithPolicy
// * KSReportWrittenCallbackWithPolicy

/** Callback type for when a crash has been detected, and we are deciding what to do about it.
 *
 * Normally a callback will just return `policy` as-is, but the user could return a modified policy to change how
 * this exception is handled.
 *
 * @see KSCrash_ExceptionHandlingPolicy for a list of which policies can be modified.
 *
 * @param policy The current policy for handling this exception
 * @param context The monitor context of the report. Note: This is an INTERNAL structure, subject to change without
 * notice!
 * @return The recommended policy for handling this exception
 */
typedef KSCrash_ExceptionHandlingPolicy (*KSCrashEventNotifyCallback)(
    KSCrash_ExceptionHandlingPolicy policy, const struct KSCrash_MonitorContext *_Nonnull context)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

/** Callback type for when a crash report is being written, giving the user an opportunity to add custom data to the
 * user section of the report..
 *
 * @param policy The policy under which the report was written.
 * @param writer The report writer.
 */
typedef void (*KSReportWriteCallbackWithPolicy)(struct KSCrash_ExceptionHandlingPolicy policy,
                                                const KSCrashReportWriter *_Nonnull writer)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

/** Callback type for when a crash report is finished writing.
 *
 * @param policy The policy under which the report was written.
 * @param reportID The ID of the report that was written.
 */
typedef void (*KSReportWrittenCallbackWithPolicy)(struct KSCrash_ExceptionHandlingPolicy policy, int64_t reportID)
    NS_SWIFT_UNAVAILABLE("Use Swift closures instead!");

#ifdef __cplusplus
}
#endif

#endif  // HDR_KSCrashReportWriterCallbacks_h
