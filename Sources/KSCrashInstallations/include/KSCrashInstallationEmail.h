//
//  KSCrashInstallationEmail.h
//
//  Created by Karl Stenerud on 2013-03-02.
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

#import "KSCrashInstallation.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, KSCrashEmailReportStyle) {
    KSCrashEmailReportStyleJSON,
    KSCrashEmailReportStyleApple,
} NS_SWIFT_NAME(EmailReportStyle);

/**
 * Email installation.
 * Sends reports via email.
 */
NS_SWIFT_NAME(CrashInstallationEmail)
@interface KSCrashInstallationEmail : KSCrashInstallation

@property(class, readonly) KSCrashInstallationEmail *sharedInstance NS_SWIFT_NAME(shared);

/** List of email addresses to send to (mandatory) */
@property(nonatomic, readwrite, copy) NSArray<NSString *> *recipients;

/** Email subject (mandatory).
 *
 * Default: "Crash Report (YourBundleID)"
 */
@property(nonatomic, readwrite, copy) NSString *subject;

/** Message to accompany the reports (optional).
 *
 * Default: nil
 */
@property(nonatomic, readwrite, copy, nullable) NSString *message;

/** How to name the attachments (mandatory)
 *
 * You may use "%d" to differentiate when multiple reports are sent at once.
 *
 * Note: With the default filter set, files are gzipped text.
 *
 * Default: "crash-report-YourBundleID-%d.txt.gz"
 */
@property(nonatomic, readwrite, copy) NSString *filenameFmt;

/** Which report style to use.
 */
@property(nonatomic, readwrite, assign) KSCrashEmailReportStyle reportStyle;

/** Use the specified report format.
 *
 * useDefaultFilenameFormat If true, also change the filename format to the default
 *                          suitable for the report format.
 */
- (void)setReportStyle:(KSCrashEmailReportStyle)reportStyle useDefaultFilenameFormat:(BOOL)useDefaultFilenameFormat;

@end

NS_ASSUME_NONNULL_END
