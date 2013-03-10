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

/** Show an alert before sending any reports. Reports will only be sent if the user
 * presses the "yes" button.
 *
 * @param title The alert title.
 * @param message The message to show the user.
 * @param yesAnswer The text to display in the "yes" box.
 * @param noAnswer The text to display in the "no" box.
 */
- (void) addConditionalAlertWithTitle:(NSString*) title
                              message:(NSString*) message
                            yesAnswer:(NSString*) yesAnswer
                             noAnswer:(NSString*) noAnswer;

/** Show an alert before sending any reports. Reports will be unconditionally sent
 * when the alert is dismissed.
 *
 * @param title The alert title.
 * @param message The message to show the user.
 * @param dismissButtonText The text to display in the dismiss button.
 */
- (void) addUnconditionalAlertWithTitle:(NSString*) title
                                message:(NSString*) message
                      dismissButtonText:(NSString*) dismissButtonText;

/** Install this installation. Call this instead of -[KSCrash install] to install
 * with everything needed for your particular backend.
 */
- (void) install;

/** Convenience method to call -[KSCrash sendAllReportsWithCompletion:].
 * This method will set the KSCrash sink and then send all outstanding reports.
 *
 * Note: Pay special attention to KSCrash's "deleteBehaviorAfterSendAll" property.
 *
 * @param onCompletion Called when sending is complete (nil = ignore).
 */
- (void) sendAllReportsWithCompletion:(KSCrashReportFilterCompletion) onCompletion;

@end
