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

#import "KSCrash+Hang.h"
#import "KSCrashHang.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Watchdog.h"

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

static void stubHandle_deprecated(KSCrash_MonitorContext *context) { stubHandle(context, NULL); }

@interface KSSempahore : NSObject {
    dispatch_semaphore_t _semaphore;
}

+ (instancetype)withValue:(NSInteger)value;

- (instancetype)initWithValue:(NSInteger)value NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

@end

@implementation KSSempahore

- (instancetype)init
{
    return [self initWithValue:0];
}

- (instancetype)initWithValue:(NSInteger)value
{
    if ((self = [super init])) {
        _semaphore = dispatch_semaphore_create(value);
    }
    return self;
}

+ (instancetype)withValue:(NSInteger)value
{
    return [[[self class] alloc] initWithValue:value];
}

- (BOOL)wait
{
    return dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER) == 0;
}

- (BOOL)waitForTimeInterval:(NSTimeInterval)timeout
{
    dispatch_time_t t = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    return dispatch_semaphore_wait(_semaphore, t) == 0;
}

- (void)signal
{
    dispatch_semaphore_signal(_semaphore);
}

@end

@interface KSCrashMonitor_Watchdog_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Watchdog_Tests

#pragma mark - Observer Tests

- (void)setUp
{
    [super setUp];
    setenv("KSCRASH_FORCE_ENABLE_WATCHDOG", "1", 1);
}

- (void)tearDown
{
    unsetenv("KSCRASH_FORCE_ENABLE_WATCHDOG");
    [super tearDown];
}

- (void)testAddObserverReturnsToken
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true, NULL);

    id token = [KSCrash.sharedInstance
        addHangObserver:^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
        }];

    XCTAssertNotNil(token, @"Adding an observer should return a non-nil token");

    api->setEnabled(false, NULL);
}

- (void)testAddObserverWhenDisabledReturnsNil
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(false, NULL);

    id token = [KSCrash.sharedInstance
        addHangObserver:^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
        }];

    XCTAssertNil(token, @"Adding an observer when disabled should return nil");
}

- (void)testMultipleObserversCanBeAdded
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true, NULL);

    id token1 = [KSCrash.sharedInstance
        addHangObserver:^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
        }];
    id token2 = [KSCrash.sharedInstance
        addHangObserver:^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
        }];
    id token3 = [KSCrash.sharedInstance
        addHangObserver:^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
        }];

    XCTAssertNotNil(token1);
    XCTAssertNotNil(token2);
    XCTAssertNotNil(token3);

    // Tokens should be different objects
    XCTAssertNotEqual(token1, token2);
    XCTAssertNotEqual(token2, token3);

    api->setEnabled(false, NULL);
}

- (void)testObserverTokenIsWeaklyHeld
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true, NULL);

    __weak id weakToken = nil;
    @autoreleasepool {
        // Capture self to ensure the block is a heap block (not global)
        __weak typeof(self) weakSelf = self;
        id token = [KSCrash.sharedInstance
            addHangObserver:^(__unused KSHangChangeType change, __unused uint64_t start, __unused uint64_t end) {
                (void)weakSelf;
            }];
        weakToken = token;
        XCTAssertNotNil(weakToken, @"Token should exist while strongly held");
    }

    // After autoreleasepool drains, token should be deallocated
    // The weak reference should become nil
    XCTAssertNil(weakToken, @"Token should be deallocated when no longer retained");

    api->setEnabled(false, NULL);
}

#pragma mark - Hang Detection Tests

- (void)testObserverReceivesHangStarted
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify,
                                                    .handle = stubHandle_deprecated,
                                                    .handleWithResult = stubHandle };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    KSSempahore *waiter = [KSSempahore withValue:0];
    __block uint64_t receivedStart = 0;
    __block uint64_t receivedEnd = 0;

    __weak typeof(self) weakSelf = self;
    __block id token =
        [KSCrash.sharedInstance addHangObserver:^(KSHangChangeType change, uint64_t start, uint64_t end) {
            (void)weakSelf;
            if (change == KSHangChangeTypeStarted) {
                receivedStart = start;
                receivedEnd = end;
                token = nil;
                [waiter signal];
            }
        }];
    XCTAssertNotNil(token);

    XCTAssertTrue([waiter waitForTimeInterval:5]);

    XCTAssertGreaterThan(receivedStart, 0ULL);
    XCTAssertGreaterThanOrEqual(receivedEnd, receivedStart);

    api->setEnabled(false, NULL);
}

- (void)testHangStartTimestampIsReasonable
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify,
                                                    .handle = stubHandle_deprecated,
                                                    .handleWithResult = stubHandle };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    KSSempahore *waiter = [KSSempahore withValue:0];
    __block uint64_t hangStart = 0;
    __block uint64_t hangEnd = 0;
    __weak typeof(self) weakSelf = self;
    __block id token =
        [KSCrash.sharedInstance addHangObserver:^(KSHangChangeType change, uint64_t start, uint64_t end) {
            (void)weakSelf;
            if (change == KSHangChangeTypeStarted) {
                hangStart = start;
                hangEnd = end;
                token = nil;
                [waiter signal];
            }
        }];
    XCTAssertNotNil(token);

    XCTAssertTrue([waiter waitForTimeInterval:5]);

    // The hang duration at "started" time should be at least the threshold
    uint64_t durationNs = hangEnd - hangStart;
    double durationSeconds = (double)durationNs / 1000000000.0;

    // Duration should be at least the threshold (249ms)
    XCTAssertGreaterThanOrEqual(durationSeconds, 0.249, @"Hang should be at least threshold duration");
    // But not excessively long
    XCTAssertLessThan(durationSeconds, 3.0, @"Hang duration shouldn't be unreasonably long");

    api->setEnabled(false, NULL);
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
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testDoubleInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testReenableAfterDisable
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));

    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));

    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testMonitorId
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    XCTAssertTrue(strcmp(api->monitorId(NULL), "Watchdog") == 0);
}

- (void)testMonitorFlags
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    XCTAssertEqual(api->monitorFlags(NULL), KSCrashMonitorFlagNone);
}

- (void)testCleanEnableDisable
{
    // Enable and disable multiple times to verify clean lifecycle
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    for (int i = 0; i < 5; i++) {
        api->setEnabled(true, NULL);
        XCTAssertTrue(api->isEnabled(NULL));
        [NSThread sleepForTimeInterval:0.1];
        api->setEnabled(false, NULL);
        XCTAssertFalse(api->isEnabled(NULL));
    }
}

- (void)testRapidEnableDisable
{
    // Rapid enable/disable without sleep
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    for (int i = 0; i < 10; i++) {
        api->setEnabled(true, NULL);
        XCTAssertTrue(api->isEnabled(NULL));
        api->setEnabled(false, NULL);
        XCTAssertFalse(api->isEnabled(NULL));
    }
}

@end
