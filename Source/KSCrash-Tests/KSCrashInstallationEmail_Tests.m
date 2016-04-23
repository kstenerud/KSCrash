//
//  KSCrashInstallationEmail_Tests.m
//
//  Created by Karl Stenerud on 2013-03-09.
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


#import <XCTest/XCTest.h>

#import <KSCrash/KSCrashInstallation+Alert.h>
#import "KSCrashInstallationEmail.h"


@interface KSCrashInstallationEmail_Tests : XCTestCase @end


@implementation KSCrashInstallationEmail_Tests

- (void) testInstall
{
    KSCrashInstallationEmail* installation = [KSCrashInstallationEmail sharedInstance];
    installation.recipients = [NSArray arrayWithObjects:@"nobody", nil];
    installation.subject = @"subject";
    installation.message = @"message";
    installation.filenameFmt = @"someFile.txt.gz";
    [installation addConditionalAlertWithTitle:@"title" message:@"message" yesAnswer:@"Yes" noAnswer:@"No"];
    [installation install];
    [installation sendAllReportsWithCompletion:^(__unused NSArray *filteredReports, BOOL completed, NSError *error)
     {
         // There are no reports, so this will succeed.
         XCTAssertTrue(completed, @"");
         XCTAssertNil(error, @"");
     }];
}

- (void) testInstallInvalid
{
    KSCrashInstallationEmail* installation = [KSCrashInstallationEmail sharedInstance];
    installation.recipients = nil;
    installation.subject = nil;
    installation.message = nil;
    installation.filenameFmt = nil;
    [installation addUnconditionalAlertWithTitle:@"title" message:@"message" dismissButtonText:@"dismiss"];
    [installation install];
    [installation sendAllReportsWithCompletion:^(__unused NSArray *filteredReports, BOOL completed, NSError *error)
     {
         XCTAssertFalse(completed, @"");
         XCTAssertNotNil(error, @"");
     }];
}

@end
