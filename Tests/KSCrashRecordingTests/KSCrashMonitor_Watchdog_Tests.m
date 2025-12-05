//
//  KSCrashMonitor_Watchdog_Tests.m
//
//  Created by Alexander Cohen on 2025-01-04.
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
#import <mach/task_policy.h>

#import "KSCrashMonitor_Watchdog.h"

// Forward declare the private KSHangMonitor class for testing
@interface KSHangMonitor : NSObject
- (instancetype)initWithRunLoop:(CFRunLoopRef)runLoop threshold:(NSTimeInterval)threshold;
@end

@interface KSCrashMonitor_Watchdog_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Watchdog_Tests

- (void)testInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());
    [NSThread sleepForTimeInterval:0.1];
    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
}

- (void)testDoubleInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();

    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());
    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());

    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
}

- (void)testReenableAfterDisable
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();

    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());
    [NSThread sleepForTimeInterval:0.05];

    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
    [NSThread sleepForTimeInterval:0.05];

    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());
    [NSThread sleepForTimeInterval:0.05];

    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
}

- (void)testMonitorId
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    XCTAssertTrue(strcmp(api->monitorId(), "Watchdog") == 0);
}

- (void)testMonitorFlags
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    XCTAssertEqual(api->monitorFlags(), KSCrashMonitorFlagNone);
}

- (void)testHangMonitorCleanDestruction
{
    // Create and destroy multiple KSHangMonitor instances to verify
    // that pthread_join properly waits for thread cleanup
    for (int i = 0; i < 5; i++) {
        @autoreleasepool {
            KSHangMonitor *monitor = [[KSHangMonitor alloc] initWithRunLoop:CFRunLoopGetMain() threshold:1.0];
            XCTAssertNotNil(monitor);
            [NSThread sleepForTimeInterval:0.05];
            monitor = nil;
        }
    }
}

- (void)testHangMonitorRapidCreateDestroy
{
    // Rapid creation and destruction without sleep
    for (int i = 0; i < 10; i++) {
        @autoreleasepool {
            KSHangMonitor *monitor = [[KSHangMonitor alloc] initWithRunLoop:CFRunLoopGetMain() threshold:0.5];
            XCTAssertNotNil(monitor);
            monitor = nil;
        }
    }
}

@end
