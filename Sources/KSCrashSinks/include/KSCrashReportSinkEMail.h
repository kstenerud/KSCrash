//
//  KSCrashReportSinkEMail.h
//
//  Created by Karl Stenerud on 2012-05-06.
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

/** Sends reports via email.
 *
 * Input: NSData
 * Output: Same as input (passthrough)
 */
NS_SWIFT_NAME(CrashReportSinkEmail)
@interface KSCrashReportSinkEMail : NSObject <KSCrashReportFilter>

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/**
 * @param recipients List of email addresses to send to.
 * @param subject What to put in the subject field.
 * @param message A message to accompany the reports (optional - nil = ignore).
 * @param filenameFmt How to name the attachments. You may use "%d" to differentiate
 *                    when multiple reports are sent at once.
 *                    Note: With the default filter set, files are gzipped text.
 */
- (instancetype)initWithRecipients:(NSArray<NSString *> *)recipients
                           subject:(NSString *)subject
                           message:(nullable NSString *)message
                       filenameFmt:(NSString *)filenameFmt;

@property(nonatomic, readonly) id<KSCrashReportFilter> defaultCrashReportFilterSet;
@property(nonatomic, readonly) id<KSCrashReportFilter> defaultCrashReportFilterSetAppleFmt;

@end

NS_ASSUME_NONNULL_END
