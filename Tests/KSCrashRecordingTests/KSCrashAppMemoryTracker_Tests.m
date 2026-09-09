//
//  KSCrashAppMemoryTracker_Tests.m
//
//  Created by Alexander Cohen on 2026-01-03.
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
#import <stdatomic.h>

#import "KSCrashAppMemory+Private.h"
#import "KSCrashAppMemoryTracker.h"

@interface KSCrashAppMemoryTracker_Tests : XCTestCase
@end

@implementation KSCrashAppMemoryTracker_Tests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    testsupport_KSCrashAppMemorySetProvider(nil);
    [super tearDown];
}

#pragma mark - Basic Initialization Tests

- (void)testInit
{
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    XCTAssertNotNil(tracker);
    XCTAssertEqual(tracker.level, KSCrashAppMemoryStateNormal);
    XCTAssertEqual(tracker.pressure, KSCrashAppMemoryStateNormal);
}

- (void)testStartAndStop
{
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    [tracker start];
    // Give time for dispatch sources to activate
    [NSThread sleepForTimeInterval:0.05];
    [tracker stop];
}

- (void)testDoubleStart
{
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    [tracker start];
    [tracker start];  // Should handle double start gracefully
    [NSThread sleepForTimeInterval:0.05];
    [tracker stop];
}

- (void)testDoubleStop
{
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    [tracker start];
    [NSThread sleepForTimeInterval:0.05];
    [tracker stop];
    [tracker stop];  // Should handle double stop gracefully
}

- (void)testCurrentAppMemory
{
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    KSCrashAppMemory *memory = tracker.currentAppMemory;
    XCTAssertNotNil(memory);
    XCTAssertTrue(memory.footprint > 0);
    XCTAssertTrue(memory.limit > 0);
}

- (void)testCurrentAppMemoryWithProvider
{
    testsupport_KSCrashAppMemorySetProvider(^KSCrashAppMemory *_Nonnull {
        return [[KSCrashAppMemory alloc] initWithFootprint:500
                                                 remaining:500
                                                  pressure:KSCrashAppMemoryStateWarn
                                           systemRemaining:0
                                               systemLimit:0];
    });

    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    KSCrashAppMemory *memory = tracker.currentAppMemory;
    XCTAssertNotNil(memory);
    XCTAssertEqual(memory.footprint, 500);
    XCTAssertEqual(memory.remaining, 500);
    XCTAssertEqual(memory.limit, 1000);
}

#pragma mark - Observer Tests

- (void)testAddObserver
{
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Observer called"];
    expectation.assertForOverFulfill = NO;

    id observer =
        [tracker addObserverWithBlock:^(KSCrashAppMemory *memory, __unused KSCrashAppMemoryTrackerChangeType changes) {
            XCTAssertNotNil(memory);
            [expectation fulfill];
        }];
    XCTAssertNotNil(observer);

    [tracker start];

    [self waitForExpectations:@[ expectation ] timeout:1.0];
    [tracker stop];
    (void)observer;  // prevent dealloc until stop
}

- (void)testMultipleObservers
{
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];

    XCTestExpectation *expectation1 = [self expectationWithDescription:@"Observer 1 called"];
    XCTestExpectation *expectation2 = [self expectationWithDescription:@"Observer 2 called"];
    XCTestExpectation *expectation3 = [self expectationWithDescription:@"Observer 3 called"];
    expectation1.assertForOverFulfill = NO;
    expectation2.assertForOverFulfill = NO;
    expectation3.assertForOverFulfill = NO;

    id observer1 = [tracker
        addObserverWithBlock:^(__unused KSCrashAppMemory *memory, __unused KSCrashAppMemoryTrackerChangeType changes) {
            [expectation1 fulfill];
        }];
    id observer2 = [tracker
        addObserverWithBlock:^(__unused KSCrashAppMemory *memory, __unused KSCrashAppMemoryTrackerChangeType changes) {
            [expectation2 fulfill];
        }];
    id observer3 = [tracker
        addObserverWithBlock:^(__unused KSCrashAppMemory *memory, __unused KSCrashAppMemoryTrackerChangeType changes) {
            [expectation3 fulfill];
        }];

    XCTAssertNotNil(observer1);
    XCTAssertNotNil(observer2);
    XCTAssertNotNil(observer3);

    [tracker start];

    [self waitForExpectations:@[ expectation1, expectation2, expectation3 ] timeout:1.0];
    [tracker stop];
    (void)observer1;
    (void)observer2;
    (void)observer3;
}

- (void)testObserverWeakReference
{
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];

    __block BOOL observerCalled = NO;

    @autoreleasepool {
        id observer = [tracker addObserverWithBlock:^(__unused KSCrashAppMemory *memory,
                                                      __unused KSCrashAppMemoryTrackerChangeType changes) {
            observerCalled = YES;
        }];
        XCTAssertNotNil(observer);
        // observer goes out of scope here and should be deallocated
    }

    // Give time for deallocation
    [NSThread sleepForTimeInterval:0.1];

    // Reset and check that the weak reference was cleaned up
    observerCalled = NO;
    [tracker start];
    [NSThread sleepForTimeInterval:0.1];
    [tracker stop];

    // Observer should not have been called since it was deallocated
    XCTAssertFalse(observerCalled);
}

#pragma mark - Concurrent Access Tests

- (void)testConcurrentObserverAddition
{
    // This test verifies thread safety when adding observers from multiple threads
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    NSMutableArray *observers = [NSMutableArray array];
    NSLock *arrayLock = [[NSLock alloc] init];

    const int numObservers = 100;

    for (int i = 0; i < numObservers; i++) {
        dispatch_group_async(group, queue, ^{
            id observer = [tracker addObserverWithBlock:^(__unused KSCrashAppMemory *memory,
                                                          __unused KSCrashAppMemoryTrackerChangeType changes) {
            }];
            if (observer) {
                [arrayLock lock];
                [observers addObject:observer];
                [arrayLock unlock];
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    XCTAssertEqual(observers.count, numObservers);
}

- (void)testConcurrentObserverAdditionDuringStart
{
    // This test specifically targets the race condition that was fixed:
    // adding observers while start() is reading them
    //
    // We start the tracker first, then concurrently add observers while the
    // heartbeat timer fires (which also reads observers under the lock).
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    [tracker start];

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    NSMutableArray *observers = [NSMutableArray array];
    NSLock *arrayLock = [[NSLock alloc] init];

    const int iterations = 100;

    for (int i = 0; i < iterations; i++) {
        // Add observers from background threads while tracker is running
        dispatch_group_async(group, queue, ^{
            id observer = [tracker addObserverWithBlock:^(__unused KSCrashAppMemory *memory,
                                                          __unused KSCrashAppMemoryTrackerChangeType changes) {
            }];
            if (observer) {
                [arrayLock lock];
                [observers addObject:observer];
                [arrayLock unlock];
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // Let the heartbeat fire a few times while observers exist
    [NSThread sleepForTimeInterval:0.1];

    [tracker stop];

    XCTAssertEqual(observers.count, iterations);
}

- (void)testConcurrentPropertyAccess
{
    // Test thread safety of pressure and level property access
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    [tracker start];

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    const int iterations = 1000;

    for (int i = 0; i < iterations; i++) {
        dispatch_group_async(group, queue, ^{
            KSCrashAppMemoryState pressure = tracker.pressure;
            (void)pressure;  // Suppress unused variable warning
        });

        dispatch_group_async(group, queue, ^{
            KSCrashAppMemoryState level = tracker.level;
            (void)level;
        });

        dispatch_group_async(group, queue, ^{
            KSCrashAppMemory *memory = tracker.currentAppMemory;
            (void)memory;
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [tracker stop];
}

- (void)testRapidStartStop
{
    // Test rapid sequential start/stop cycles
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];

    const int iterations = 20;

    for (int i = 0; i < iterations; i++) {
        [tracker start];
        [tracker stop];
    }
}

- (void)testConcurrentObserverAdditionAndMemoryAccess
{
    // Combined stress test: add observers while also accessing memory state
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    [tracker start];

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    NSMutableArray *observers = [NSMutableArray array];
    NSLock *arrayLock = [[NSLock alloc] init];

    const int iterations = 100;

    for (int i = 0; i < iterations; i++) {
        dispatch_group_async(group, queue, ^{
            id observer = [tracker
                addObserverWithBlock:^(KSCrashAppMemory *memory, __unused KSCrashAppMemoryTrackerChangeType changes) {
                    // Access memory properties in callback
                    (void)memory.footprint;
                    (void)memory.level;
                }];
            if (observer) {
                [arrayLock lock];
                [observers addObject:observer];
                [arrayLock unlock];
            }
        });

        dispatch_group_async(group, queue, ^{
            (void)tracker.pressure;
            (void)tracker.level;
            (void)tracker.currentAppMemory;
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [tracker stop];

    XCTAssertEqual(observers.count, iterations);
}

#pragma mark - Memory Level Change Tests

- (void)testLevelChangeNotification
{
    __block _Atomic(uint64_t) currentFootprint = 10;  // Start at normal level

    testsupport_KSCrashAppMemorySetProvider(^KSCrashAppMemory *_Nonnull {
        uint64_t footprint = atomic_load(&currentFootprint);
        return [[KSCrashAppMemory alloc] initWithFootprint:footprint
                                                 remaining:100 - footprint
                                                  pressure:KSCrashAppMemoryStateNormal
                                           systemRemaining:0
                                               systemLimit:0];
    });

    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Level change detected"];
    expectation.expectedFulfillmentCount = 1;

    __block BOOL levelChangeDetected = NO;

    id observer =
        [tracker addObserverWithBlock:^(__unused KSCrashAppMemory *memory, KSCrashAppMemoryTrackerChangeType changes) {
            if ((changes & KSCrashAppMemoryTrackerChangeTypeLevel) && !levelChangeDetected) {
                levelChangeDetected = YES;
                // A level transition publishes the footprint bytes that caused
                // it even when they moved by less than the 1 MiB threshold
                // (here: 40 bytes), so the sidecar never records a new level
                // against stale bytes.
                XCTAssertTrue(changes & KSCrashAppMemoryTrackerChangeTypeFootprint);
                [expectation fulfill];
            }
        }];

    [tracker start];

    // Wait a bit then change the footprint to trigger a level change
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        atomic_store(&currentFootprint, 50);  // Change to urgent level
    });

    [self waitForExpectations:@[ expectation ] timeout:3.0];
    [tracker stop];

    (void)observer;  // Keep observer alive
}

#pragma mark - Headroom Tests

- (void)testCurrentAppMemoryHasSystemValues
{
    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];
    KSCrashAppMemory *memory = tracker.currentAppMemory;
    XCTAssertNotNil(memory);
    XCTAssertTrue(memory.systemLimit > 0);
    XCTAssertTrue(memory.systemRemaining > 0);
    XCTAssertTrue(memory.systemRemaining < memory.systemLimit);
}

- (void)testHeadroomChangeNotification
{
    __block _Atomic(uint64_t) currentSystemRemaining = 500;  // Start at normal headroom

    testsupport_KSCrashAppMemorySetProvider(^KSCrashAppMemory *_Nonnull {
        uint64_t systemRemaining = atomic_load(&currentSystemRemaining);
        return [[KSCrashAppMemory alloc] initWithFootprint:10
                                                 remaining:90
                                                  pressure:KSCrashAppMemoryStateNormal
                                           systemRemaining:systemRemaining
                                               systemLimit:1000];
    });

    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Headroom change detected"];
    expectation.expectedFulfillmentCount = 1;

    __block BOOL headroomChangeDetected = NO;

    id observer = [tracker addObserverWithBlock:^(KSCrashAppMemory *memory, KSCrashAppMemoryTrackerChangeType changes) {
        if ((changes & KSCrashAppMemoryTrackerChangeTypeHeadroom) && !headroomChangeDetected) {
            headroomChangeDetected = YES;
            XCTAssertEqual(memory.headroom, KSCrashAppMemoryStateCritical);
            // Resource sidecars refresh system byte values on this flag, so a
            // headroom transition must include it even when system remaining
            // moved by less than the change threshold.
            XCTAssertTrue(changes & KSCrashAppMemoryTrackerChangeTypeSystemRemaining);
            XCTAssertEqual(memory.systemRemaining, 20);
            [expectation fulfill];
        }
    }];

    [tracker start];
    XCTAssertEqual(tracker.headroom, KSCrashAppMemoryStateNormal);

    // Wait a bit then shrink system memory to trigger a headroom change
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        atomic_store(&currentSystemRemaining, 20);  // Change to critical headroom
    });

    [self waitForExpectations:@[ expectation ] timeout:3.0];
    XCTAssertEqual(tracker.headroom, KSCrashAppMemoryStateCritical);
    [tracker stop];

    (void)observer;  // Keep observer alive
}

- (void)testSystemRemainingChangeDoesNotClaimFootprintChange
{
    __block _Atomic(uint64_t) currentSystemRemaining = 9000;

    testsupport_KSCrashAppMemorySetProvider(^KSCrashAppMemory *_Nonnull {
        uint64_t systemRemaining = atomic_load(&currentSystemRemaining);
        return [[KSCrashAppMemory alloc] initWithFootprint:10
                                                 remaining:90
                                                  pressure:KSCrashAppMemoryStateNormal
                                           systemRemaining:systemRemaining
                                               systemLimit:10000];
    });

    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];

    XCTestExpectation *expectation = [self expectationWithDescription:@"System remaining change detected"];
    expectation.expectedFulfillmentCount = 1;

    __block BOOL systemChangeDetected = NO;

    // The first heartbeat also reports SystemRemaining (0 -> 9000), so key on
    // the 9000 -> 8000 move specifically.
    id observer = [tracker addObserverWithBlock:^(KSCrashAppMemory *memory, KSCrashAppMemoryTrackerChangeType changes) {
        if ((changes & KSCrashAppMemoryTrackerChangeTypeSystemRemaining) && memory.systemRemaining == 8000 &&
            !systemChangeDetected) {
            systemChangeDetected = YES;
            // Device-wide movement is not an app footprint change; observers
            // must be able to tell the two apart.
            XCTAssertFalse(changes & KSCrashAppMemoryTrackerChangeTypeFootprint);
            XCTAssertFalse(changes & KSCrashAppMemoryTrackerChangeTypeHeadroom);
            [expectation fulfill];
        }
    }];

    [tracker start];

    // Move system remaining well past the 1% threshold, but stay inside the
    // normal headroom band and leave the footprint untouched.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        atomic_store(&currentSystemRemaining, 8000);
    });

    [self waitForExpectations:@[ expectation ] timeout:3.0];
    [tracker stop];

    (void)observer;  // Keep observer alive
}

- (void)testProviderFailureKeepsLastState
{
    __block _Atomic(bool) providerFails = false;

    testsupport_KSCrashAppMemorySetProvider(^KSCrashAppMemory *_Nullable {
        if (atomic_load(&providerFails)) {
            return nil;
        }
        return [[KSCrashAppMemory alloc] initWithFootprint:80
                                                 remaining:20
                                                  pressure:KSCrashAppMemoryStateNormal
                                           systemRemaining:40
                                               systemLimit:1000];
    });

    KSCrashAppMemoryTracker *tracker = [[KSCrashAppMemoryTracker alloc] init];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Critical level reached"];
    expectation.assertForOverFulfill = NO;

    id observer = [tracker addObserverWithBlock:^(KSCrashAppMemory *memory, KSCrashAppMemoryTrackerChangeType changes) {
        // A failed sample must never surface as a nil snapshot.
        XCTAssertNotNil(memory);
        if (changes & KSCrashAppMemoryTrackerChangeTypeLevel) {
            [expectation fulfill];
        }
    }];

    [tracker start];
    [self waitForExpectations:@[ expectation ] timeout:3.0];
    XCTAssertEqual(tracker.level, KSCrashAppMemoryStateCritical);
    XCTAssertEqual(tracker.headroom, KSCrashAppMemoryStateCritical);

    // Make the provider fail, let at least one more heartbeat fire, and
    // verify the failure did not fabricate a recovery to normal.
    atomic_store(&providerFails, true);
    [NSThread sleepForTimeInterval:1.3];
    XCTAssertEqual(tracker.level, KSCrashAppMemoryStateCritical);
    XCTAssertEqual(tracker.headroom, KSCrashAppMemoryStateCritical);
    [tracker stop];

    (void)observer;  // Keep observer alive
}

@end
