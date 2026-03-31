//
//  KSCrashCPUTracker_Tests.m
//
//  Created by Alexander Cohen on 2026-03-30.
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

#import "KSCrashCPUTracker.h"

#pragma mark - KSCrashCPUStateToString Tests

@interface KSCrashCPUStateToString_Tests : XCTestCase
@end

@implementation KSCrashCPUStateToString_Tests

- (void)testNormalStateToString
{
    XCTAssertTrue(strcmp(KSCrashCPUStateToString(KSCrashCPUStateNormal), "normal") == 0);
}

- (void)testWarningStateToString
{
    XCTAssertTrue(strcmp(KSCrashCPUStateToString(KSCrashCPUStateWarning), "warning") == 0);
}

- (void)testCriticalStateToString
{
    XCTAssertTrue(strcmp(KSCrashCPUStateToString(KSCrashCPUStateCritical), "critical") == 0);
}

- (void)testUnknownStateDefaultsToNormal
{
    XCTAssertTrue(strcmp(KSCrashCPUStateToString((KSCrashCPUState)99), "normal") == 0);
}

@end

#pragma mark - KSCrashCPUTracker Tests

@interface KSCrashCPUTracker_Tests : XCTestCase
@end

@implementation KSCrashCPUTracker_Tests

- (void)testSharedInstanceIsNotNil
{
    XCTAssertNotNil(KSCrashCPUTracker.sharedInstance);
}

- (void)testSharedInstanceReturnsSameObject
{
    KSCrashCPUTracker *a = KSCrashCPUTracker.sharedInstance;
    KSCrashCPUTracker *b = KSCrashCPUTracker.sharedInstance;
    XCTAssertEqual(a, b);
}

- (void)testInitialStateIsNormal
{
    // The shared instance auto-starts, but at low CPU it should be normal.
    XCTAssertEqual(KSCrashCPUTracker.sharedInstance.state, KSCrashCPUStateNormal);
}

- (void)testCurrentCPUReturnsSnapshot
{
    KSCrashCPU *cpu = KSCrashCPUTracker.sharedInstance.currentCPU;
    XCTAssertNotNil(cpu);
    XCTAssertTrue(cpu.threadCount > 0);
}

- (void)testCurrentCPUStateMatchesTrackerState
{
    KSCrashCPU *cpu = KSCrashCPUTracker.sharedInstance.currentCPU;
    XCTAssertNotNil(cpu);
    XCTAssertEqual(cpu.state, KSCrashCPUTracker.sharedInstance.state);
}

- (void)testNormalStateHasZeroWindowData
{
    KSCrashCPU *cpu = KSCrashCPUTracker.sharedInstance.currentCPU;
    XCTAssertNotNil(cpu);
    if (cpu.state == KSCrashCPUStateNormal) {
        XCTAssertEqualWithAccuracy(cpu.cpuTimeInWindow, 0, 0.001);
        XCTAssertEqualWithAccuracy(cpu.wallTimeInWindow, 0, 0.001);
        XCTAssertEqualWithAccuracy(cpu.averageUsageInWindow, 0, 0.001);
    }
}

- (void)testAddObserverReturnsNonNil
{
    id observer = [KSCrashCPUTracker.sharedInstance
        addObserverWithBlock:^(__unused KSCrashCPU *cpu, __unused KSCrashCPUTrackerChangeType changes) {
        }];
    XCTAssertNotNil(observer);
}

- (void)testAddObserverWithNilBlockReturnsNil
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    id observer = [KSCrashCPUTracker.sharedInstance addObserverWithBlock:nil];
#pragma clang diagnostic pop
    XCTAssertNil(observer);
}

- (void)testObserverReceivesCallback
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"Observer called"];
    expectation.assertForOverFulfill = NO;

    id observer =
        [KSCrashCPUTracker.sharedInstance addObserverWithBlock:^(KSCrashCPU *cpu, KSCrashCPUTrackerChangeType changes) {
            XCTAssertNotNil(cpu);
            XCTAssertTrue(changes & KSCrashCPUTrackerChangeTypeUsage);
            [expectation fulfill];
        }];

    [self waitForExpectations:@[ expectation ] timeout:10.0];
    (void)observer;
}

- (void)testObserverDeallocatedWhenNilled
{
    __weak id weakObserver = nil;
    @autoreleasepool {
        // Capture self to force the block onto the heap (global blocks never dealloc).
        id observer = [KSCrashCPUTracker.sharedInstance
            addObserverWithBlock:^(__unused KSCrashCPU *cpu, __unused KSCrashCPUTrackerChangeType changes) {
                (void)self;
            }];
        weakObserver = observer;
        XCTAssertNotNil(weakObserver);
        observer = nil;
    }
    XCTAssertNil(weakObserver);
}

- (void)testConcurrentPropertyAccess
{
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    for (int i = 0; i < 100; i++) {
        dispatch_group_async(group, queue, ^{
            KSCrashCPUState state = KSCrashCPUTracker.sharedInstance.state;
            (void)state;
        });
        dispatch_group_async(group, queue, ^{
            KSCrashCPU *cpu = KSCrashCPUTracker.sharedInstance.currentCPU;
            (void)cpu;
        });
    }

    long result = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    XCTAssertEqual(result, 0, @"Concurrent property access timed out");
}

@end
