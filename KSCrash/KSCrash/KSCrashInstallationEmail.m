//
//  KSCrashInstallationEmail.m
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


#import "KSCrashInstallationEmail.h"
#import "KSCrashInstallation+Private.h"
#import "ARCSafe_MemMgmt.h"
#import "KSCrashReportSinkEMail.h"
#import "KSCrashReportFilterAlert.h"
#import "KSSingleton.h"


@implementation KSCrashInstallationEmail

IMPLEMENT_EXCLUSIVE_SHARED_INSTANCE(KSCrashInstallationEmail)

@synthesize recipients = _recipients;
@synthesize subject = _subject;
@synthesize message = _message;
@synthesize filenameFmt = _filenameFmt;

- (id) init
{
    if((self = [super initWithMaxReportFieldCount:10
                               requiredProperties:[NSArray arrayWithObjects:
                                                   @"recipients",
                                                   @"subject",
                                                   @"filenameFmt",
                                                   nil]]))
    {
        NSString* bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
        self.subject = [NSString stringWithFormat:@"Crash Report (%@)", bundleName];
        self.filenameFmt = [NSString stringWithFormat:@"crash-report-%@-%%d.txt.gz", bundleName];
    }
    return self;
}

- (void) dealloc
{
    as_release(_recipients);
    as_release(_subject);
    as_release(_message);
    as_release(_filenameFmt);
    as_superdealloc();
}

- (id<KSCrashReportFilter>) sink
{
    KSCrashReportSinkEMail* sink = [KSCrashReportSinkEMail sinkWithRecipients:self.recipients
                                                                      subject:self.subject
                                                                      message:self.message
                                                                  filenameFmt:self.filenameFmt];
    return [KSCrashReportFilterPipeline filterWithFilters:[sink defaultCrashReportFilterSet], nil];
}

@end
