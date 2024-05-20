//
//  KSCrashInstallationStandard_Tests.m
//
//  Created by Kelp on 2013-03-14.
//
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
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

#import "KSCrashInstallationVictory.h"


@interface KSCrashInstallationVictory_Tests : XCTestCase @end


@implementation KSCrashInstallationVictory_Tests

- (void) testInstall
{
    KSCrashInstallationVictory* installation = [KSCrashInstallationVictory sharedInstance];
    installation.url = [NSURL URLWithString:@"https://victory-demo.appspot.com/api/v1/crash/0571f5f6-652d-413f-8043-0e9531e1b689"];
    installation.userName = nil;
    installation.userEmail = nil;
    
    [installation install];
    [installation sendAllReportsWithCompletion:^(__unused NSArray *filteredReports, BOOL completed, NSError *error)
     {
         // There are no reports, so this will succeed.
         XCTAssertTrue(completed, @"");
         XCTAssertNil(error, @"");
     }];
}

@end
