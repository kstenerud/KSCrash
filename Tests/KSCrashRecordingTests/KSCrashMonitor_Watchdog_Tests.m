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

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Watchdog.h"

// Forward declare the private KSHangMonitor class for testing
@interface KSHangMonitor : NSObject
- (instancetype)initWithRunLoop:(CFRunLoopRef)runLoop threshold:(NSTimeInterval)threshold;
- (id)addObserver:(KSHangObserverBlock)observer;
@end

// Stub callbacks for testing hang detection
static KSCrash_MonitorContext g_stubContext;

static KSCrash_MonitorContext *stubNotify(__unused thread_t thread,
                                          __unused KSCrash_ExceptionHandlingRequirements requirements)
{
    memset(&g_stubContext, 0, sizeof(g_stubContext));
    return &g_stubContext;
}

static void stubHandle(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result)
{
    result->reportId = 12345;
    result->path[0] = '\0';
}

@interface KSCrashMonitor_Watchdog_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Watchdog_Tests

#pragma mark - Observer Tests

- (void)testAddObserverReturnsToken
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true);

    id token = kscm_watchdogAddHangObserver(
        ^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
        });

    XCTAssertNotNil(token, @"Adding an observer should return a non-nil token");

    api->setEnabled(false);
}

- (void)testAddObserverWhenDisabledReturnsNil
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(false);

    id token = kscm_watchdogAddHangObserver(
        ^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
        });

    XCTAssertNil(token, @"Adding an observer when disabled should return nil");
}

- (void)testMultipleObserversCanBeAdded
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true);

    id token1 = kscm_watchdogAddHangObserver(
        ^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
        });
    id token2 = kscm_watchdogAddHangObserver(
        ^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
        });
    id token3 = kscm_watchdogAddHangObserver(
        ^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
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
        id token = kscm_watchdogAddHangObserver(
            ^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
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
        id token =
            [monitor addObserver:^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
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
            id token = [monitor
                addObserver:^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
                }];
            XCTAssertNotNil(token);
            [tokens addObject:token];
        }

        XCTAssertEqual(tokens.count, 5);

        monitor = nil;
    }
}

#pragma mark - Hang Detection Tests (Direct KSHangMonitor)

- (void)testObserverReceivesHangStartedOnKSHangMonitor
{
    // Initialize callbacks so hang detection doesn't crash
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify, .handle = stubHandle };
    api->init(&callbacks);

    @autoreleasepool {
        // Use a short threshold (100ms) for faster tests
        KSHangMonitor *monitor = [[KSHangMonitor alloc] initWithRunLoop:CFRunLoopGetMain() threshold:0.1];

        XCTestExpectation *startedExpectation = [self expectationWithDescription:@"Hang started"];

        __weak typeof(self) weakSelf = self;
        id token = [monitor addObserver:^(KSHangChangeType change, uint64_t start, uint64_t end) {
            (void)weakSelf;
            if (change == KSHangChangeTypeStarted) {
                XCTAssertGreaterThan(start, 0ULL);
                XCTAssertGreaterThanOrEqual(end, start);
                [startedExpectation fulfill];
            }
        }];
        XCTAssertNotNil(token);

        // Block the main thread longer than the threshold (100ms)
        [NSThread sleepForTimeInterval:0.15];

        [self waitForExpectations:@[ startedExpectation ] timeout:1.0];

        monitor = nil;
    }
}

- (void)testMultipleObserversAllReceiveHangStartedOnKSHangMonitor
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify, .handle = stubHandle };
    api->init(&callbacks);

    @autoreleasepool {
        KSHangMonitor *monitor = [[KSHangMonitor alloc] initWithRunLoop:CFRunLoopGetMain() threshold:0.1];

        XCTestExpectation *observer1Started = [self expectationWithDescription:@"Observer 1 started"];
        XCTestExpectation *observer2Started = [self expectationWithDescription:@"Observer 2 started"];
        XCTestExpectation *observer3Started = [self expectationWithDescription:@"Observer 3 started"];

        __weak typeof(self) weakSelf = self;

        id token1 = [monitor addObserver:^(KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
            (void)weakSelf;
            if (change == KSHangChangeTypeStarted) {
                [observer1Started fulfill];
            }
        }];

        id token2 = [monitor addObserver:^(KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
            (void)weakSelf;
            if (change == KSHangChangeTypeStarted) {
                [observer2Started fulfill];
            }
        }];

        id token3 = [monitor addObserver:^(KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
            (void)weakSelf;
            if (change == KSHangChangeTypeStarted) {
                [observer3Started fulfill];
            }
        }];

        XCTAssertNotNil(token1);
        XCTAssertNotNil(token2);
        XCTAssertNotNil(token3);

        // Trigger hang
        [NSThread sleepForTimeInterval:1.0];

        [self waitForExpectations:@[ observer1Started, observer2Started, observer3Started ] timeout:1.0];

        monitor = nil;
    }
}

- (void)testHangStartTimestampIsReasonable
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify, .handle = stubHandle };
    api->init(&callbacks);

    @autoreleasepool {
        KSHangMonitor *monitor = [[KSHangMonitor alloc] initWithRunLoop:CFRunLoopGetMain() threshold:0.1];

        XCTestExpectation *startedExpectation = [self expectationWithDescription:@"Hang started"];

        __block uint64_t hangStart = 0;
        __block uint64_t hangEnd = 0;
        __weak typeof(self) weakSelf = self;
        id token = [monitor addObserver:^(KSHangChangeType change, uint64_t start, uint64_t end) {
            (void)weakSelf;
            if (change == KSHangChangeTypeStarted) {
                hangStart = start;
                hangEnd = end;
                [startedExpectation fulfill];
            }
        }];
        XCTAssertNotNil(token);

        NSTimeInterval sleepDuration = 0.15;  // 150ms (> 100ms threshold)
        [NSThread sleepForTimeInterval:sleepDuration];

        [self waitForExpectations:@[ startedExpectation ] timeout:1.0];

        // The hang duration at "started" time should be at least the threshold
        uint64_t durationNs = hangEnd - hangStart;
        double durationSeconds = (double)durationNs / 1000000000.0;

        // Duration should be at least the threshold (100ms)
        XCTAssertGreaterThanOrEqual(durationSeconds, 0.1, @"Hang should be at least threshold duration");
        // But not excessively long
        XCTAssertLessThan(durationSeconds, 1.0, @"Hang duration shouldn't be unreasonably long");

        monitor = nil;
    }
}

- (void)testHangChangeTypeValues
{
    // Verify the enum values are as expected
    XCTAssertEqual(KSHangChangeTypeNone, 0);
    XCTAssertEqual(KSHangChangeTypeStarted, 1);
    XCTAssertEqual(KSHangChangeTypeUpdated, 2);
    XCTAssertEqual(KSHangChangeTypeEnded, 3);
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

    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());

    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());

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
