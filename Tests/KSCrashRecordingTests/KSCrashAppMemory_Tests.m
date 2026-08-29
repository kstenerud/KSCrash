//
//  KSCrashAppMemory_Tests.m
//
//  Created by Alexander Cohen on 2026-03-08.
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

#import "KSCrashAppMemory+Private.h"
#import "KSCrashAppStateTracker.h"
#import "KSSystemCapabilities.h"

@interface KSCrashAppMemory_Tests : XCTestCase
@end

@implementation KSCrashAppMemory_Tests

- (void)setUp
{
    [super setUp];
    setenv("ActivePrewarm", "0", 1);
}

#pragma mark - KSCrashAppMemory

static KSCrashAppMemory *Memory(uint64_t footprint)
{
    return [[KSCrashAppMemory alloc] initWithFootprint:footprint
                                             remaining:100 - footprint
                                              pressure:KSCrashAppMemoryStateNormal
                                       systemRemaining:0
                                           systemLimit:0];
}

static KSCrashAppMemory *SystemMemory(uint64_t systemRemaining)
{
    return [[KSCrashAppMemory alloc] initWithFootprint:50
                                             remaining:50
                                              pressure:KSCrashAppMemoryStateNormal
                                       systemRemaining:systemRemaining
                                           systemLimit:1000];
}

- (void)testAppMemoryLevels
{
    XCTAssertEqual(Memory(0).level, KSCrashAppMemoryStateNormal);
    XCTAssertEqual(Memory(25).level, KSCrashAppMemoryStateWarn);
    XCTAssertEqual(Memory(50).level, KSCrashAppMemoryStateUrgent);
    XCTAssertEqual(Memory(75).level, KSCrashAppMemoryStateCritical);
    XCTAssertEqual(Memory(95).level, KSCrashAppMemoryStateTerminal);

    XCTAssertEqual(Memory(0).isOutOfMemory, NO);
    XCTAssertEqual(Memory(25).isOutOfMemory, NO);
    XCTAssertEqual(Memory(50).isOutOfMemory, NO);
    XCTAssertEqual(Memory(75).isOutOfMemory, YES);
    XCTAssertEqual(Memory(95).isOutOfMemory, YES);

    KSCrashAppMemory *memory = Memory(50);
    XCTAssertEqual(memory.footprint, 50);
    XCTAssertEqual(memory.remaining, 50);
    XCTAssertEqual(memory.limit, 100);
}

- (void)testAppMemoryHeadroom
{
    // Baseline 0.80 shifts the 25/50/75/95 ladder into the top 20% of the
    // range: bands land at >15% / 10-15% / 5-10% / 1-5% / <1% remaining.
    XCTAssertEqual(SystemMemory(1000).headroom, KSCrashAppMemoryStateNormal);
    XCTAssertEqual(SystemMemory(200).headroom, KSCrashAppMemoryStateNormal);
    XCTAssertEqual(SystemMemory(150).headroom, KSCrashAppMemoryStateWarn);
    XCTAssertEqual(SystemMemory(100).headroom, KSCrashAppMemoryStateUrgent);
    XCTAssertEqual(SystemMemory(50).headroom, KSCrashAppMemoryStateCritical);
    XCTAssertEqual(SystemMemory(10).headroom, KSCrashAppMemoryStateTerminal);
    XCTAssertEqual(SystemMemory(0).headroom, KSCrashAppMemoryStateTerminal);

    KSCrashAppMemory *memory = SystemMemory(200);
    XCTAssertEqual(memory.systemRemaining, 200);
    XCTAssertEqual(memory.systemLimit, 1000);

    // Headroom never feeds the OOM heuristic.
    XCTAssertEqual(SystemMemory(0).isOutOfMemory, NO);
}

- (void)testAppMemoryHeadroomWithoutSystemValues
{
    // With no system values recorded, headroom reports normal.
    KSCrashAppMemory *memory = Memory(50);
    XCTAssertEqual(memory.systemRemaining, 0);
    XCTAssertEqual(memory.systemLimit, 0);
    XCTAssertEqual(memory.headroom, KSCrashAppMemoryStateNormal);

    // A remaining above the limit clamps to zero used rather than underflowing.
    KSCrashAppMemory *inverted = [[KSCrashAppMemory alloc] initWithFootprint:50
                                                                   remaining:50
                                                                    pressure:KSCrashAppMemoryStateNormal
                                                             systemRemaining:2000
                                                                 systemLimit:1000];
    XCTAssertEqual(inverted.headroom, KSCrashAppMemoryStateNormal);
}

#pragma mark - Transition State

- (void)testTransitionStateUserPerceptible
{
    XCTAssertFalse(ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionStateStartupPrewarm));
    XCTAssertFalse(ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionStateBackground));
    XCTAssertFalse(ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionStateTerminating));
    XCTAssertFalse(ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionStateExiting));

    XCTAssertTrue(ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionStateStartup));
    XCTAssertTrue(ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionStateLaunching));
    XCTAssertTrue(ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionStateForegrounding));
    XCTAssertTrue(ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionStateActive));
    XCTAssertTrue(ksapp_transitionStateIsUserPerceptible(KSCrashAppTransitionStateDeactivating));
}

#pragma mark - App State Tracker

- (void)testAppStateTrackerNoPrewarm
{
    setenv("ActivePrewarm", "0", 1);
    __block KSCrashAppTransitionState state;

    KSCrashAppStateTracker *tracker = [KSCrashAppStateTracker new];
    [tracker addObserverWithBlock:^(KSCrashAppTransitionState transitionState) {
        state = transitionState;
    }];

    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateStartup);

    [tracker start];

#if KSCRASH_HAS_UIAPPLICATION
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:UIApplicationDidFinishLaunchingNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:UIApplicationWillEnterForegroundNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateForegrounding);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateDeactivating);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateBackground);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:UIApplicationDidFinishLaunchingNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:UIApplicationWillTerminateNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateTerminating);
    XCTAssertEqual(tracker.transitionState, state);
#elif KSCRASH_HAS_NSEXTENSION
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:NSExtensionHostDidBecomeActiveNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:NSExtensionHostWillResignActiveNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateDeactivating);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:NSExtensionHostDidEnterBackgroundNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateBackground);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:NSExtensionHostWillEnterForegroundNotification object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateForegrounding);
    XCTAssertEqual(tracker.transitionState, state);
#else
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
    XCTAssertEqual(tracker.transitionState, state);
#endif
}

@end
