//
//  KSCrashMonitor_NSException_Tests.m
//
//  Created by Karl Stenerud on 2013-01-26.
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

#import "KSCrash.h"
#import "KSCrashConfiguration.h"
#import "KSCrashMonitor.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_NSException.h"

@interface KSCrashMonitor_NSException_Tests : XCTestCase
@end

@implementation KSCrashMonitor_NSException_Tests

- (void)tearDown
{
    kscm_disableAllMonitors();
    [super tearDown];
}

- (void)testInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_nsexception_getAPI();
    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());
    [NSThread sleepForTimeInterval:0.1];
    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
}

- (void)testDoubleInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_nsexception_getAPI();

    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());
    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());

    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
}

- (void)testReportUserNSException
{
    // Install KSCrash to enable the NSException monitor (ignore if already installed)
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    [[KSCrash sharedInstance] installWithConfiguration:config error:NULL];

    // Create an exception with a real call stack by throwing and catching
    NSException *exception = nil;
    @try {
        @throw [NSException exceptionWithName:@"TestException" reason:@"Testing exception handling" userInfo:nil];
    } @catch (NSException *e) {
        exception = e;
    }

    XCTAssertNotNil(exception);
    XCTAssertNotNil(exception.callStackReturnAddresses);
    XCTAssertGreaterThan(exception.callStackReturnAddresses.count, 0);

    // Report the exception - this exercises handleException and initStackCursor
    [[KSCrash sharedInstance] reportNSException:exception logAllThreads:NO];
}

- (void)testReportUserNSExceptionWithEmptyCallStack
{
    // Install KSCrash to enable the NSException monitor (ignore if already installed)
    KSCrashConfiguration *config = [[KSCrashConfiguration alloc] init];
    [[KSCrash sharedInstance] installWithConfiguration:config error:NULL];

    // Create an exception without throwing (no call stack)
    NSException *exception = [NSException exceptionWithName:@"TestException"
                                                     reason:@"Testing exception without callstack"
                                                   userInfo:nil];

    XCTAssertNotNil(exception);
    XCTAssertEqual(exception.callStackReturnAddresses.count, 0);

    // Report the exception - this exercises the else branch in initStackCursor
    [[KSCrash sharedInstance] reportNSException:exception logAllThreads:NO];
}

@end
