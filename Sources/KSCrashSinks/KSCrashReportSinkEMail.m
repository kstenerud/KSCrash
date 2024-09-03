//
//  KSCrashReportSinkEMail.m
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

#import "KSCrashReportSinkEMail.h"

#import "KSCrashReport.h"
#import "KSCrashReportFilterAppleFmt.h"
#import "KSCrashReportFilterBasic.h"
#import "KSCrashReportFilterGZip.h"
#import "KSCrashReportFilterJSON.h"
#import "KSNSErrorHelper.h"
#import "KSSystemCapabilities.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#if KSCRASH_HAS_MESSAGEUI
#import <MessageUI/MessageUI.h>

@interface KSCrashMailProcess : NSObject <MFMailComposeViewControllerDelegate>

@property(nonatomic, readwrite, copy) NSArray<id<KSCrashReport>> *reports;
@property(nonatomic, readwrite, copy) KSCrashReportFilterCompletion onCompletion;

@property(nonatomic, readwrite, strong) UIViewController *dummyVC;

+ (KSCrashMailProcess *)process;

- (void)startWithController:(MFMailComposeViewController *)controller
                    reports:(NSArray<id<KSCrashReport>> *)reports
                filenameFmt:(NSString *)filenameFmt
               onCompletion:(KSCrashReportFilterCompletion)onCompletion;

- (void)presentModalVC:(UIViewController *)vc;
- (void)dismissModalVC;

@end

@implementation KSCrashMailProcess

+ (KSCrashMailProcess *)process
{
    return [[self alloc] init];
}

- (void)startWithController:(MFMailComposeViewController *)controller
                    reports:(NSArray<id<KSCrashReport>> *)reports
                filenameFmt:(NSString *)filenameFmt
               onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    self.reports = [reports copy];
    self.onCompletion = onCompletion;

    controller.mailComposeDelegate = self;

    int i = 1;
    for (KSCrashReportData *report in reports) {
        if ([report isKindOfClass:[KSCrashReportData class]] == NO || report.value == nil) {
            KSLOG_ERROR(@"Unexpected non-data report: %@", report);
            continue;
        }
        [controller addAttachmentData:report.value
                             mimeType:@"binary"
                             fileName:[NSString stringWithFormat:filenameFmt, i++]];
    }

    [self presentModalVC:controller];
}

- (void)mailComposeController:(__unused MFMailComposeViewController *)mailController
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error
{
    [self dismissModalVC];

    switch (result) {
        case MFMailComposeResultSent:
            kscrash_callCompletion(self.onCompletion, self.reports, nil);
            break;
        case MFMailComposeResultSaved:
            kscrash_callCompletion(self.onCompletion, self.reports, nil);
            break;
        case MFMailComposeResultCancelled:
            kscrash_callCompletion(self.onCompletion, self.reports,
                                   [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                               code:0
                                                        description:@"User cancelled"]);
            break;
        case MFMailComposeResultFailed:
            kscrash_callCompletion(self.onCompletion, self.reports, error);
            break;
        default: {
            kscrash_callCompletion(self.onCompletion, self.reports,
                                   [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                               code:0
                                                        description:@"Unknown MFMailComposeResult: %d", result]);
        }
    }
}

- (void)presentModalVC:(UIViewController *)vc
{
    self.dummyVC = [[UIViewController alloc] initWithNibName:nil bundle:nil];
    self.dummyVC.view = [[UIView alloc] init];

    UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
    [window addSubview:self.dummyVC.view];

    if ([self.dummyVC respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        [self.dummyVC presentViewController:vc animated:YES completion:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.dummyVC presentModalViewController:vc animated:YES];
#pragma clang diagnostic pop
    }
}

- (void)dismissModalVC
{
    if ([self.dummyVC respondsToSelector:@selector(dismissViewControllerAnimated:completion:)]) {
        [self.dummyVC dismissViewControllerAnimated:YES
                                         completion:^{
                                             [self.dummyVC.view removeFromSuperview];
                                             self.dummyVC = nil;
                                         }];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.dummyVC dismissModalViewControllerAnimated:NO];
#pragma clang diagnostic pop
        [self.dummyVC.view removeFromSuperview];
        self.dummyVC = nil;
    }
}

@end

@interface KSCrashReportSinkEMail ()

@property(nonatomic, readwrite, copy) NSArray *recipients;
@property(nonatomic, readwrite, copy) NSString *subject;
@property(nonatomic, readwrite, copy) NSString *message;
@property(nonatomic, readwrite, copy) NSString *filenameFmt;

@end

@implementation KSCrashReportSinkEMail

+ (instancetype)sinkWithRecipients:(NSArray<NSString *> *)recipients
                           subject:(NSString *)subject
                           message:(nullable NSString *)message
                       filenameFmt:(NSString *)filenameFmt
{
    return [[self alloc] initWithRecipients:recipients subject:subject message:message filenameFmt:filenameFmt];
}

- (instancetype)initWithRecipients:(NSArray<NSString *> *)recipients
                           subject:(NSString *)subject
                           message:(nullable NSString *)message
                       filenameFmt:(NSString *)filenameFmt
{
    if ((self = [super init])) {
        _recipients = [recipients copy];
        _subject = [subject copy];
        _message = [message copy];
        _filenameFmt = [filenameFmt copy];
    }
    return self;
}

- (id<KSCrashReportFilter>)defaultCrashReportFilterSet
{
    return [KSCrashReportFilterPipeline
        filterWithFilters:[KSCrashReportFilterJSONEncode
                              filterWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
                          [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1], self, nil];
}

- (id<KSCrashReportFilter>)defaultCrashReportFilterSetAppleFmt
{
    return [KSCrashReportFilterPipeline
        filterWithFilters:[KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
                          [KSCrashReportFilterStringToData filter],
                          [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1], self, nil];
}

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    if (![MFMailComposeViewController canSendMail]) {
        UIAlertController *alertController =
            [UIAlertController alertControllerWithTitle:@"Email Error"
                                                message:@"This device is not configured to send email."
                                         preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alertController addAction:okAction];
        UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
        [keyWindow.rootViewController presentViewController:alertController animated:YES completion:NULL];

        kscrash_callCompletion(onCompletion, reports,
                               [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                           code:0
                                                    description:@"E-Mail not enabled on device"]);
        return;
    }

    MFMailComposeViewController *mailController = [[MFMailComposeViewController alloc] init];
    [mailController setToRecipients:self.recipients];
    [mailController setSubject:self.subject];
    if (self.message != nil) {
        [mailController setMessageBody:self.message isHTML:NO];
    }
    NSString *filenameFmt = self.filenameFmt;

    dispatch_async(dispatch_get_main_queue(), ^{
        __block KSCrashMailProcess *process = [[KSCrashMailProcess alloc] init];
        [process startWithController:mailController
                             reports:reports
                         filenameFmt:filenameFmt
                        onCompletion:^(NSArray *filteredReports, NSError *error) {
                            kscrash_callCompletion(onCompletion, filteredReports, error);
                            dispatch_async(dispatch_get_main_queue(), ^{
                                process = nil;
                            });
                        }];
    });
}

@end

#else

#import "KSNSErrorHelper.h"

@implementation KSCrashReportSinkEMail

+ (KSCrashReportSinkEMail *)sinkWithRecipients:(NSArray *)recipients
                                       subject:(NSString *)subject
                                       message:(NSString *)message
                                   filenameFmt:(NSString *)filenameFmt
{
    return [[self alloc] initWithRecipients:recipients subject:subject message:message filenameFmt:filenameFmt];
}

- (id)initWithRecipients:(__unused NSArray *)recipients
                 subject:(__unused NSString *)subject
                 message:(__unused NSString *)message
             filenameFmt:(__unused NSString *)filenameFmt
{
    return [super init];
}

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    for (id<KSCrashReport> report in reports) {
        NSLog(@"Report\n%@", report);
    }
    kscrash_callCompletion(onCompletion, reports,
                           [KSNSErrorHelper errorWithDomain:[[self class] description]
                                                       code:0
                                                description:@"Cannot send mail on this platform"]);
}

- (id<KSCrashReportFilter>)defaultCrashReportFilterSet
{
    return [KSCrashReportFilterPipeline
        filterWithFilters:[KSCrashReportFilterJSONEncode
                              filterWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
                          [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1], self, nil];
}

- (id<KSCrashReportFilter>)defaultCrashReportFilterSetAppleFmt
{
    return [KSCrashReportFilterPipeline
        filterWithFilters:[KSCrashReportFilterAppleFmt filterWithReportStyle:KSAppleReportStyleSymbolicatedSideBySide],
                          [KSCrashReportFilterStringToData filter],
                          [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1], self, nil];
}

@end

#endif
