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
#include "KSCrashNamespace.h"
#import "KSCrashReportFilter.h"
#import "KSCrashReportWriter.h"

NS_ASSUME_NONNULL_BEGIN

@class KSCrashConfiguration;

/**
 * Crash system installation which handles backend-specific details.
 *
 * Only one installation can be installed at a time.
 *
 * This is an abstract class.
 */
NS_SWIFT_NAME(CrashInstallation)
@interface KSCrashInstallation : NSObject

/** C Function to call during a crash report to give the callee an opportunity to
 * add to the report. NULL = ignore (DEPRECATED).
 *
 * @deprecated Use `onCrashWithPolicy` for async-safety awareness (since v2.4.0).
 * This callback does not receive policy information and may not handle crash
 * scenarios safely.
 *
 * WARNING: Only call async-safe functions from this function! DO NOT call
 * Swift/Objective-C methods!!!
 */
@property(atomic, readwrite, assign, nullable) KSReportWriteCallback onCrash
    __attribute__((deprecated("Use `onCrashWithPolicy` for async-safety awareness (since v2.4.0).")));

/** C Function to call during a crash report to give the callee an opportunity to
 * add to the report. NULL = ignore.
 *
 * The policy parameter provides crucial information about the crash context and
 * safety constraints that must be observed within the callback.
 *
 * @see KSCrash_ExceptionHandlingPolicy
 *
 * WARNING: Only call async-safe functions from this function when policy.requiresAsyncSafety is true!
 * DO NOT call Swift/Objective-C methods unless policy allows it!!!
 */
@property(atomic, readwrite, assign, nullable) KSReportWriteCallbackWithPolicy onCrashWithPolicy;

/** Flag for disabling built-in demangling pre-filter.
 * If enabled an additional `KSCrashReportFilterDemangle` filter will be applied first.
 * @note Enabled by-default.
 */
@property(nonatomic, assign) BOOL isDemangleEnabled;

/** Flag for disabling a pre-filter for automated diagnostics.
 * If enabled an additional `KSCrashReportFilterDoctor` filter will be applied.
 * @note Enabled by-default.
 */
@property(nonatomic, assign) BOOL isDoctorEnabled;

/** Install this crash handler with a specific configuration.
 * Call this method instead of `-[KSCrash installWithConfiguration:error:]` to set up the crash handler
 * tailored for your specific backend requirements.
 *
 * @param configuration The configuration object containing the settings for the crash handler.
 * @param error         On input, a pointer to an error object. If an error occurs, this pointer
 *                      is set to an actual error object containing the error information.
 *                      You may specify nil for this parameter if you do not want the error information.
 *                      See KSCrashError.h for specific error codes that may be returned.
 *
 * @return YES if the installation was successful, NO otherwise.
 *
 * @note The `crashNotifyCallback` property of the provided `KSCrashConfiguration` will not take effect
 *       when using this method. The callback will be internally managed to ensure proper integration
 *       with the backend.
 *
 * @see KSCrashError.h for a complete list of possible error codes.
 */
- (BOOL)installWithConfiguration:(KSCrashConfiguration *)configuration error:(NSError **)error;

/** Convenience method to call -[KSCrash sendAllReportsWithCompletion:].
 * This method will set the KSCrash sink and then send all outstanding reports.
 *
 * Note: Pay special attention to KSCrash's "deleteBehaviorAfterSendAll" property.
 *
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void)sendAllReportsWithCompletion:(nullable KSCrashReportFilterCompletion)onCompletion;

/** Add a filter that gets executed before all normal filters.
 * Prepended filters will be executed in the order in which they were added.
 *
 * @param filter the filter to prepend.
 */
- (void)addPreFilter:(id<KSCrashReportFilter>)filter;

/** Creates a sink to be used for reports sending.
 * @note Subclasses MUST implement this, otherwise `sendAllReportsWithCompletion:` will complete with error.
 *
 * @return An instance that implements `KSCrashReportFilter` protocol to be used as a reports sending sink.
 */
- (id<KSCrashReportFilter>)sink;

/** Show an alert before sending any reports. Reports will only be sent if the user
 * presses the "yes" button.
 *
 * @param title The alert title.
 * @param message The message to show the user.
 * @param yesAnswer The text to display in the "yes" box.
 * @param noAnswer The text to display in the "no" box.
 */
- (void)addConditionalAlertWithTitle:(NSString *)title
                             message:(nullable NSString *)message
                           yesAnswer:(NSString *)yesAnswer
                            noAnswer:(nullable NSString *)noAnswer;

/** Show an alert before sending any reports. Reports will be unconditionally sent
 * when the alert is dismissed.
 *
 * @param title The alert title.
 * @param message The message to show the user.
 * @param dismissButtonText The text to display in the dismiss button.
 */
- (void)addUnconditionalAlertWithTitle:(NSString *)title
                               message:(nullable NSString *)message
                     dismissButtonText:(NSString *)dismissButtonText;

/** Validates properties of installation.
 *
 * Intended to be overriden in subclasses to handle properties validation
 * in the installation logic (e.g. before sending crash reports).
 *
 * @param error Pointer to an error object to store validation error.
 * @return `NO` if there is a validation error.
 */
- (BOOL)validateSetupWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
