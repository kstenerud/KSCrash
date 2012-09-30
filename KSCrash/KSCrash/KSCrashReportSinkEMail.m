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

#import "ARCSafe_MemMgmt.h"
#import "KSCrashReportFilterGZip.h"
#import "KSCrashReportFilterJSON.h"

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"

#import <MessageUI/MessageUI.h>


@interface KSCrashMailProcess : NSObject <MFMailComposeViewControllerDelegate>

@property(nonatomic,readwrite,retain) NSArray* reports;
@property(nonatomic,readwrite,copy) KSCrashReportFilterCompletion onCompletion;

@property(nonatomic,readwrite,retain) UIViewController* dummyVC;

+ (KSCrashMailProcess*) process;

- (void) startWithController:(MFMailComposeViewController*) controller
                     reports:(NSArray*) reports
                 filenameFmt:(NSString*) filenameFmt
                onCompletion:(KSCrashReportFilterCompletion) onCompletion;

- (void) presentModalVC:(UIViewController*) vc;
- (void) dismissModalVC;

@end

@implementation KSCrashMailProcess

@synthesize reports = _reports;
@synthesize onCompletion = _onCompletion;
@synthesize dummyVC = _dummyVC;

+ (KSCrashMailProcess*) process
{
    return as_autorelease([[self alloc] init]);
}

- (void) dealloc
{
    as_release(_reports);
    as_release(_onCompletion);
    as_release(_dummyVC);
    as_superdealloc();
}

- (void) startWithController:(MFMailComposeViewController*) controller
                     reports:(NSArray*) reports
                 filenameFmt:(NSString*) filenameFmt
                onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    self.reports = reports;
    self.onCompletion = onCompletion;

    controller.mailComposeDelegate = self;

    int i = 1;
    for(NSData* report in reports)
    {
        [controller addAttachmentData:report
                             mimeType:@"binary"
                             fileName:[NSString stringWithFormat:filenameFmt, i++]];
    }

    [self presentModalVC:controller];
}

- (void) mailComposeController:(MFMailComposeViewController*) mailController
           didFinishWithResult:(MFMailComposeResult) result
                         error:(NSError*) error
{
    #pragma unused(mailController)
    [self dismissModalVC];

    switch (result)
    {
        case MFMailComposeResultSent:
            self.onCompletion(self.reports, YES, nil);
            break;
        case MFMailComposeResultSaved:
            self.onCompletion(self.reports, YES, nil);
            break;
        case MFMailComposeResultCancelled:
            self.onCompletion(self.reports, NO, nil);
            break;
        case MFMailComposeResultFailed:
            self.onCompletion(self.reports, NO, error);
            break;
        default:
        {
            NSString* errorMsg = [NSString stringWithFormat:@"Unknown MFMailComposeResult: %d", result];
            NSError* error2 = [NSError errorWithDomain:@"KSCrashReportSinkEMail"
                                                  code:0
                                              userInfo:[NSDictionary dictionaryWithObject:errorMsg
                                                                                   forKey:NSLocalizedDescriptionKey]];
            self.onCompletion(self.reports, NO, error2);
        }
    }
}

- (void) presentModalVC:(UIViewController*) vc
{
	self.dummyVC = as_autorelease([[UIViewController alloc] initWithNibName:nil bundle:nil]);
	self.dummyVC.view = as_autorelease([[UIView alloc] init]);

    UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
    [window addSubview:self.dummyVC.view];

    [self.dummyVC presentModalViewController:vc animated:YES];
}

- (void) dismissModalVC
{
	[self.dummyVC dismissViewControllerAnimated:YES completion:^
     {
         [self.dummyVC.view removeFromSuperview];
         self.dummyVC = nil;
     }];
}

@end


@interface KSCrashReportSinkEMail ()

@property(nonatomic,readwrite,retain) NSArray* recipients;

@property(nonatomic,readwrite,retain) NSString* subject;

@property(nonatomic,readwrite,retain) NSString* filenameFmt;

@end


@implementation KSCrashReportSinkEMail

@synthesize recipients = _recipients;
@synthesize subject = _subject;
@synthesize filenameFmt = _filenameFmt;

+ (KSCrashReportSinkEMail*) sinkWithRecipients:(NSArray*) recipients
                                       subject:(NSString*) subject
                                   filenameFmt:(NSString*) filenameFmt
{
    return as_autorelease([[self alloc] initWithRecipients:recipients
                                                   subject:subject
                                               filenameFmt:filenameFmt]);
}

- (id) initWithRecipients:(NSArray*) recipients
                  subject:(NSString*) subject
              filenameFmt:(NSString*) filenameFmt
{
    if((self = [super init]))
    {
        self.recipients = recipients;
        self.subject = subject;
        self.filenameFmt = filenameFmt;
    }
    return self;
}

- (void) dealloc
{
    as_release(_recipients);
    as_release(_subject);
    as_release(_filenameFmt);
    as_superdealloc();
}

- (NSArray*) defaultCrashReportFilterSet
{
    return [NSArray arrayWithObjects:
            [KSCrashReportFilterJSONEncode filterWithOptions:KSJSONEncodeOptionSorted | KSJSONEncodeOptionPretty],
            [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1],
            self,
            nil];
}

- (void) filterReports:(NSArray*) reports
          onCompletion:(KSCrashReportFilterCompletion) onCompletion
{
    if(![MFMailComposeViewController canSendMail])
    {
        [as_autorelease([[UIAlertView alloc] initWithTitle:@"Email Error"
                                                   message:@"This device is not configured to send email."
                                                  delegate:nil
                                         cancelButtonTitle:@"OK"
                                         otherButtonTitles:nil]) show];

        onCompletion(reports, NO, [NSError errorWithDomain:@"KSCrashReportSinkEMail"
                                                      code:0
                                                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                            @"E-Mail not enabled on device",
                                                            NSLocalizedDescriptionKey,
                                                            nil]]);
        return;
    }

    MFMailComposeViewController* mailController = [[MFMailComposeViewController alloc] init];
    [mailController setToRecipients:self.recipients];
    [mailController setSubject:self.subject];
    NSString* filenameFmt = self.filenameFmt;

    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       __block KSCrashMailProcess* process = [[KSCrashMailProcess alloc] init];
                       [process startWithController:mailController
                                            reports:reports
                                        filenameFmt:filenameFmt
                                       onCompletion:^(NSArray* filteredReports,
                                                      BOOL completed,
                                                      NSError* error)
                        {
                            onCompletion(filteredReports, completed, error);
                            dispatch_async(dispatch_get_main_queue(), ^
                                           {
                                               as_release(process);
                                               process = nil;
                                           });
                        }];
                   });
}

@end
