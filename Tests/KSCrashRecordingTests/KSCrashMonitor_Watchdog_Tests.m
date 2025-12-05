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
- (id)addObserver:(KSHangObserverBlock)observer;
@end

@interface KSCrashMonitor_Watchdog_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Watchdog_Tests

#pragma mark - Observer Tests

- (void)testAddObserverReturnsToken
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true);

    id token = kscm_watchdogAddHangObserver(^(__unused KSHangChangeType change, __unused uint64_t start,
                                              __unused uint64_t end){
    });

    XCTAssertNotNil(token, @"Adding an observer should return a non-nil token");

    api->setEnabled(false);
}

- (void)testAddObserverWhenDisabledReturnsNil
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(false);

    id token = kscm_watchdogAddHangObserver(^(__unused KSHangChangeType change, __unused uint64_t start,
                                              __unused uint64_t end){
    });

    XCTAssertNil(token, @"Adding an observer when disabled should return nil");
}

- (void)testMultipleObserversCanBeAdded
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true);

    id token1 = kscm_watchdogAddHangObserver(^(__unused KSHangChangeType change, __unused uint64_t start,
                                               __unused uint64_t end){
    });
    id token2 = kscm_watchdogAddHangObserver(^(__unused KSHangChangeType change, __unused uint64_t start,
                                               __unused uint64_t end){
    });
    id token3 = kscm_watchdogAddHangObserver(^(__unused KSHangChangeType change, __unused uint64_t start,
                                               __unused uint64_t end){
    });

    XCTAssertNotNil(token1);
    XCTAssertNotNil(token2);
    XCTAssertNotNil(token3);

    // Tokens should be different objects
    XCTAssertNotEqual(token1, token2);
    XCTAssertNotEqual(token2, token3);

    api->setEnabled(false);
}

- (void)testObserverTokenIsWeaklyHeld
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true);

    __weak id weakToken = nil;
    @autoreleasepool {
        // Capture self to ensure the block is a heap block (not global)
        __weak typeof(self) weakSelf = self;
        id token = kscm_watchdogAddHangObserver(^(__unused KSHangChangeType change, __unused uint64_t start,
                                                  __unused uint64_t end) {
            (void)weakSelf;
        });
        weakToken = token;
        XCTAssertNotNil(weakToken, @"Token should exist while strongly held");
    }

    // After autoreleasepool drains, token should be deallocated
    // The weak reference should become nil
    XCTAssertNil(weakToken, @"Token should be deallocated when no longer retained");

    api->setEnabled(false);
}

- (void)testObserverOnKSHangMonitorDirectly
{
    @autoreleasepool {
        KSHangMonitor *monitor = [[KSHangMonitor alloc] initWithRunLoop:CFRunLoopGetMain() threshold:1.0];

        __block NSInteger callCount = 0;
        id token = [monitor addObserver:^(__unused KSHangChangeType change, __unused uint64_t start,
                                          __unused uint64_t end) {
            callCount++;
        }];

        XCTAssertNotNil(token, @"Observer token should not be nil");
        XCTAssertEqual(callCount, 0, @"Observer should not be called until a hang occurs");

        monitor = nil;
    }
}

- (void)testMultipleObserversOnKSHangMonitor
{
    @autoreleasepool {
        KSHangMonitor *monitor = [[KSHangMonitor alloc] initWithRunLoop:CFRunLoopGetMain() threshold:1.0];

        NSMutableArray *tokens = [NSMutableArray array];
        for (int i = 0; i < 5; i++) {
            id token = [monitor addObserver:^(__unused KSHangChangeType change, __unused uint64_t start,
                                              __unused uint64_t end){
            }];
            XCTAssertNotNil(token);
            [tokens addObject:token];
        }

        XCTAssertEqual(tokens.count, 5);

        monitor = nil;
    }
}

#pragma mark - Enable/Disable Tests

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
