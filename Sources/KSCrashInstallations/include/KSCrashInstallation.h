//
//  KSCrashInstallation.h
//
//  Created by Karl Stenerud on 2013-02-10.
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
#import "KSCrashReportWriter.h"

@class KSCrashConfiguration;

/**
 * Crash system installation which handles backend-specific details.
 *
 * Only one installation can be installed at a time.
 *
 * This is an abstract class.
 */
@interface KSCrashInstallation : NSObject

/** C Function to call during a crash report to give the callee an opportunity to
 * add to the report. NULL = ignore.
 *
 * WARNING: Only call async-safe functions from this function! DO NOT call
 * Objective-C methods!!!
 */
@property(atomic,readwrite,assign) KSReportWriteCallback onCrash;

/** Install this crash handler with a specific configuration.
 * Call this method instead of `-[KSCrash installWithConfiguration:]` to set up the crash handler
 * tailored for your specific backend requirements.
 *
 * @param configuration The configuration object containing the settings for the crash handler.
 *                      If nil, a default KSCrashConfiguration will be used.
 *
 * @note The `crashNotifyCallback` property of the provided `KSCrashConfiguration` will not take effect
 *       when using this method. The callback will be internally managed to ensure proper integration
 *       with the backend.
 */
- (void) installWithConfiguration:(KSCrashConfiguration*) configuration;

/** Convenience method to call -[KSCrash sendAllReportsWithCompletion:].
 * This method will set the KSCrash sink and then send all outstanding reports.
 *
 * Note: Pay special attention to KSCrash's "deleteBehaviorAfterSendAll" property.
 *
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void) sendAllReportsWithCompletion:(KSCrashReportFilterCompletion) onCompletion;

/** Add a filter that gets executed before all normal filters.
 * Prepended filters will be executed in the order in which they were added.
 *
 * @param filter the filter to prepend.
 */
- (void) addPreFilter:(id<KSCrashReportFilter>) filter;

@end
