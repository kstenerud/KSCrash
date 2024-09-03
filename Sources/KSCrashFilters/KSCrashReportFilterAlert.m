//
//  KSCrashReportFilterAlert.m
//
//  Created by Karl Stenerud on 2012-08-24.
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

#import "KSCrashReportFilterAlert.h"

#import "KSCrashReport.h"
#import "KSNSErrorHelper.h"
#import "KSSystemCapabilities.h"

// #define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#if KSCRASH_HAS_ALERTVIEW

#if KSCRASH_HAS_UIKIT
#import <UIKit/UIKit.h>
#endif

#if KSCRASH_HAS_NSALERT
#import <AppKit/AppKit.h>
#endif

@interface KSCrashAlertViewProcess : NSObject

@property(nonatomic, readwrite, copy) NSArray<id<KSCrashReport>> *reports;
@property(nonatomic, readwrite, copy) KSCrashReportFilterCompletion onCompletion;
@property(nonatomic, readwrite, assign) NSInteger expectedButtonIndex;

+ (KSCrashAlertViewProcess *)process;

- (void)startWithTitle:(NSString *)title
               message:(NSString *)message
             yesAnswer:(NSString *)yesAnswer
              noAnswer:(NSString *)noAnswer
               reports:(NSArray<id<KSCrashReport>> *)reports
          onCompletion:(KSCrashReportFilterCompletion)onCompletion;

@end

@implementation KSCrashAlertViewProcess

+ (KSCrashAlertViewProcess *)process
{
    return [[self alloc] init];
}

- (void)startWithTitle:(NSString *)title
               message:(NSString *)message
             yesAnswer:(NSString *)yesAnswer
              noAnswer:(NSString *)noAnswer
               reports:(NSArray<id<KSCrashReport>> *)reports
          onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    KSLOG_TRACE(@"Starting alert view process");
    _reports = [reports copy];
    _onCompletion = [onCompletion copy];
    _expectedButtonIndex = noAnswer == nil ? 0 : 1;

#if KSCRASH_HAS_UIALERTCONTROLLER
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *yesAction = [UIAlertAction actionWithTitle:yesAnswer
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(__unused UIAlertAction *_Nonnull action) {
                                                          kscrash_callCompletion(self.onCompletion, self.reports, nil);
                                                      }];
    UIAlertAction *noAction = [UIAlertAction
        actionWithTitle:noAnswer
                  style:UIAlertActionStyleCancel
                handler:^(__unused UIAlertAction *_Nonnull action) {
                    kscrash_callCompletion(self.onCompletion, self.reports, [[self class] cancellationError]);
                }];
    [alertController addAction:yesAction];
    [alertController addAction:noAction];
    UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
    [keyWindow.rootViewController presentViewController:alertController animated:YES completion:NULL];
#elif KSCRASH_HAS_NSALERT
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:yesAnswer];
    if (noAnswer != nil) {
        [alert addButtonWithTitle:noAnswer];
    }
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:NSAlertStyleInformational];

    NSModalResponse response = [alert runModal];
    NSError *error = nil;
    if (noAnswer != nil && response == NSAlertSecondButtonReturn) {
        error = [[self class] cancellationError];
    }
    kscrash_callCompletion(self.onCompletion, self.reports, error);
#endif
}

+ (NSError *)cancellationError
{
    return [KSNSErrorHelper errorWithDomain:[[self class] description] code:0 description:@"Cancelled by user"];
}

- (void)alertView:(__unused id)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    BOOL success = buttonIndex == self.expectedButtonIndex;
    kscrash_callCompletion(self.onCompletion, self.reports, success ? nil : [[self class] cancellationError]);
}

@end

@interface KSCrashReportFilterAlert ()

@property(nonatomic, readwrite, copy) NSString *title;
@property(nonatomic, readwrite, copy) NSString *message;
@property(nonatomic, readwrite, copy) NSString *yesAnswer;
@property(nonatomic, readwrite, copy) NSString *noAnswer;

@end

@implementation KSCrashReportFilterAlert

+ (instancetype)filterWithTitle:(NSString *)title
                        message:(nullable NSString *)message
                      yesAnswer:(NSString *)yesAnswer
                       noAnswer:(nullable NSString *)noAnswer;
{
    return [[self alloc] initWithTitle:title message:message yesAnswer:yesAnswer noAnswer:noAnswer];
}

- (instancetype)initWithTitle:(NSString *)title
                      message:(nullable NSString *)message
                    yesAnswer:(NSString *)yesAnswer
                     noAnswer:(nullable NSString *)noAnswer;
{
    if ((self = [super init])) {
        _title = [title copy];
        _message = [message copy];
        _yesAnswer = [yesAnswer copy];
        _noAnswer = [noAnswer copy];
    }
    return self;
}

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        KSLOG_TRACE(@"Launching new alert view process");
        __block KSCrashAlertViewProcess *process = [[KSCrashAlertViewProcess alloc] init];
        [process startWithTitle:self.title
                        message:self.message
                      yesAnswer:self.yesAnswer
                       noAnswer:self.noAnswer
                        reports:reports
                   onCompletion:^(NSArray *filteredReports, NSError *error) {
                       KSLOG_TRACE(@"alert process complete");
                       kscrash_callCompletion(onCompletion, filteredReports, error);
                       dispatch_async(dispatch_get_main_queue(), ^{
                           process = nil;
                       });
                   }];
    });
}

@end

#else

@implementation KSCrashReportFilterAlert

+ (KSCrashReportFilterAlert *)filterWithTitle:(NSString *)title
                                      message:(NSString *)message
                                    yesAnswer:(NSString *)yesAnswer
                                     noAnswer:(NSString *)noAnswer
{
    return [[self alloc] initWithTitle:title message:message yesAnswer:yesAnswer noAnswer:noAnswer];
}

- (id)initWithTitle:(__unused NSString *)title
            message:(__unused NSString *)message
          yesAnswer:(__unused NSString *)yesAnswer
           noAnswer:(__unused NSString *)noAnswer
{
    if ((self = [super init])) {
        KSLOG_WARN(@"Alert filter not available on this platform.");
    }
    return self;
}

- (void)filterReports:(NSArray<id<KSCrashReport>> *)reports onCompletion:(KSCrashReportFilterCompletion)onCompletion
{
    KSLOG_WARN(@"Alert filter not available on this platform.");
    kscrash_callCompletion(onCompletion, reports, nil);
}

@end

#endif
