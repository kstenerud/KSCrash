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
#import "KSCrashAppStateTracker+Private.h"
#import "KSCrashAppStateTracker.h"
#import "KSCrashNotificationNames.h"

// Only to compare the core's mirrored values and names with UIKit's own symbols.
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_VISION
#define KSCRASH_TEST_HAS_UIAPPLICATION_SYMBOLS 1
#import <UIKit/UIKit.h>
#endif

// Stands in for UIApplication: the tracker messages whatever class it is handed.
@interface KSFakeApplication : NSObject <KSCrashApplicationReading>
@property(nonatomic, readwrite) KSCrashApplicationState applicationState;
@end

static KSFakeApplication *gSharedFakeApplication;

@implementation KSFakeApplication
+ (id<KSCrashApplicationReading>)sharedApplication
{
    return gSharedFakeApplication;
}
@end

// What the tracker's atexit block calls.
@interface KSCrashAppStateTracker (ExitForTesting)
- (void)_exitCalled;
@end

@interface KSCrashAppMemory_Tests : XCTestCase
@end

@implementation KSCrashAppMemory_Tests

- (void)setUp
{
    [super setUp];
    setenv("ActivePrewarm", "0", 1);
}

- (void)tearDown
{
    gSharedFakeApplication = nil;
    [super tearDown];
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
    XCTAssertEqual(Memory(89).level, KSCrashAppMemoryStateCritical);
    XCTAssertEqual(Memory(90).level, KSCrashAppMemoryStateTerminal);
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
    // Baseline 0.80 shifts the 25/50/75/90 ladder into the top 20% of the
    // range: bands land at >15% / 10-15% / 5-10% / 2-5% / <2% remaining.
    XCTAssertEqual(SystemMemory(1000).headroom, KSCrashAppMemoryStateNormal);
    XCTAssertEqual(SystemMemory(200).headroom, KSCrashAppMemoryStateNormal);
    XCTAssertEqual(SystemMemory(150).headroom, KSCrashAppMemoryStateWarn);
    XCTAssertEqual(SystemMemory(100).headroom, KSCrashAppMemoryStateUrgent);
    XCTAssertEqual(SystemMemory(50).headroom, KSCrashAppMemoryStateCritical);
    XCTAssertEqual(SystemMemory(25).headroom, KSCrashAppMemoryStateCritical);
    XCTAssertEqual(SystemMemory(15).headroom, KSCrashAppMemoryStateTerminal);
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
    XCTAssertEqual(SystemMemory(2000).headroom, KSCrashAppMemoryStateNormal);
}

- (void)testEqualSamplesHashEqually
{
    KSCrashAppMemory *a = SystemMemory(200);
    KSCrashAppMemory *b = SystemMemory(200);
    XCTAssertEqualObjects(a, b);
    XCTAssertEqual(a.hash, b.hash);
    NSSet *set = [NSSet setWithObjects:a, b, nil];
    XCTAssertEqual(set.count, 1);
    XCTAssertNotEqualObjects(a, SystemMemory(201));
}

- (void)testStateToStringIsTotal
{
    XCTAssertEqual(strcmp(KSCrashAppMemoryStateToString(KSCrashAppMemoryStateNormal), "normal"), 0);
    XCTAssertEqual(strcmp(KSCrashAppMemoryStateToString(KSCrashAppMemoryStateTerminal), "terminal"), 0);
    // Sidecar bytes come off disk unvalidated; an out-of-range value must
    // still map to a string instead of asserting.
    XCTAssertEqual(strcmp(KSCrashAppMemoryStateToString((KSCrashAppMemoryState)200), "unknown"), 0);
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

static KSCrashAppStateTracker *AppTracker(NSNotificationCenter *center, KSFakeApplication *_Nullable shared)
{
    gSharedFakeApplication = shared;
    KSCrashAppStateTracker *tracker = [[KSCrashAppStateTracker alloc] initWithNotificationCenter:center];
    tracker.isAppExtension = NO;
    tracker.applicationClass = KSFakeApplication.class;
    return tracker;
}

static KSFakeApplication *FakeApplication(KSCrashApplicationState state)
{
    KSFakeApplication *application = [KSFakeApplication new];
    application.applicationState = state;
    return application;
}

// Lets every block performed on the main run loop so far run.
- (void)turnMainRunLoop
{
    XCTestExpectation *turned = [self expectationWithDescription:@"main run loop turned"];
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        [turned fulfill];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
    [self waitForExpectations:@[ turned ] timeout:5];
}

// Lets every block queued on the main queue so far run.
- (void)turnMainQueue
{
    XCTestExpectation *turned = [self expectationWithDescription:@"main queue turned"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [turned fulfill];
    });
    [self waitForExpectations:@[ turned ] timeout:5];
}

// Runs `block` inside a callout of the running main run loop, as an app's code runs. A test method
// itself runs on the main thread outside any run loop callout, which is how the tracker sees a main
// run loop that has not started yet.
- (void)inMainRunLoopCallout:(void (^)(void))block
{
    XCTestExpectation *ran = [self expectationWithDescription:@"ran in a main run loop callout"];
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        block();
        [ran fulfill];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
    [self waitForExpectations:@[ ran ] timeout:5];
}

- (void)testAppStateTrackerNoPrewarm
{
    setenv("ActivePrewarm", "0", 1);
    __block KSCrashAppTransitionState state;

    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, nil);
    [tracker addObserverWithBlock:^(KSCrashAppTransitionState transitionState) {
        state = transitionState;
    }];

    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateStartup);

    [tracker start];

    [center postNotificationName:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:@"UIApplicationWillEnterForegroundNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateForegrounding);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:@"UIApplicationDidBecomeActiveNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:@"UIApplicationWillResignActiveNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateDeactivating);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:@"UIApplicationDidEnterBackgroundNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateBackground);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);
    XCTAssertEqual(tracker.transitionState, state);

    [center postNotificationName:@"UIApplicationWillTerminateNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateTerminating);
    XCTAssertEqual(tracker.transitionState, state);

    [tracker stop];
}

- (void)testAppStateTrackerWithoutApplicationIsActive
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, nil);
    tracker.applicationClass = Nil;
    [tracker start];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);

    [center postNotificationName:@"UIApplicationDidEnterBackgroundNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
}

- (void)testAppStateTrackerWithoutApplicationRecordsANormalExit
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, nil);
    tracker.applicationClass = Nil;
    [tracker start];
    [tracker _exitCalled];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateExiting);
}

- (void)testAppStateTrackerWithoutApplicationStoppedIgnoresExit
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, nil);
    tracker.applicationClass = Nil;
    [tracker start];
    [tracker stop];
    [tracker _exitCalled];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
}

- (void)testAppStateTrackerInAppExtensionFollowsHost
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, FakeApplication(KSCrashApplicationStateBackground));
    tracker.isAppExtension = YES;
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateStartup);
    [tracker start];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);

    [center postNotificationName:@"UIApplicationDidEnterBackgroundNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);

    [center postNotificationName:@"NSExtensionHostWillResignActiveNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateDeactivating);
    [center postNotificationName:@"NSExtensionHostDidEnterBackgroundNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateBackground);
    [center postNotificationName:@"NSExtensionHostWillEnterForegroundNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateForegrounding);
    [center postNotificationName:@"NSExtensionHostDidBecomeActiveNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);

    [tracker stop];
}

- (void)testAppStateTrackerInAppIgnoresExtensionHost
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, nil);
    [tracker start];

    [center postNotificationName:@"NSExtensionHostDidBecomeActiveNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateStartup);

    [center postNotificationName:@"UIApplicationDidBecomeActiveNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);

    [tracker stop];
}

- (void)testAppStateTrackerStartsFromARunningApplication
{
    KSCrashAppStateTracker *tracker =
        AppTracker([NSNotificationCenter new], FakeApplication(KSCrashApplicationStateActive));
    [self inMainRunLoopCallout:^{
        [tracker start];
        XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
    }];
    [tracker stop];
}

- (void)testAppStateTrackerStartedBeforeTheMainRunLoopRunsReadsOnceItDoes
{
    KSCrashAppStateTracker *tracker =
        AppTracker([NSNotificationCenter new], FakeApplication(KSCrashApplicationStateActive));
    [tracker start];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateStartup);

    [self turnMainRunLoop];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
    [tracker stop];
}

// A scene-based app, and a watch app, launches before the main run loop runs, reading background on
// its way to the foreground. The read waits for the run loop, by which time the launch notifications
// have moved the state on.
- (void)testAppStateTrackerDropsABackgroundReadFromALaunchBeforeTheMainRunLoop
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, FakeApplication(KSCrashApplicationStateBackground));
    [tracker start];
    [center postNotificationName:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);
    [center postNotificationName:@"UIApplicationWillEnterForegroundNotification" object:nil];

    [self turnMainRunLoop];
    [self turnMainQueue];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateForegrounding);
    [tracker stop];
}

// A launch into the background gets no foreground notification, and still reads background on the
// main queue's next turn.
- (void)testAppStateTrackerSettlesABackgroundLaunchAsBackground
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, nil);
    [tracker start];

    gSharedFakeApplication = FakeApplication(KSCrashApplicationStateBackground);
    [center postNotificationName:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);

    [self turnMainQueue];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateBackground);
    [tracker stop];
}

// A foreground launch has moved past Launching by the main queue's next turn, even though a
// scene-based app still reads background when the launch notification arrives.
- (void)testAppStateTrackerLeavesAForegroundLaunchAlone
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, nil);
    [tracker start];

    KSFakeApplication *application = FakeApplication(KSCrashApplicationStateBackground);
    gSharedFakeApplication = application;
    [center postNotificationName:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    application.applicationState = KSCrashApplicationStateInactive;
    [center postNotificationName:@"UIApplicationWillEnterForegroundNotification" object:nil];

    [self turnMainQueue];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateForegrounding);
    [tracker stop];
}

// A tracker stopped before the main queue turns no longer follows the application.
- (void)testAppStateTrackerStoppedBeforeTheLaunchSettlesStaysLaunching
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, FakeApplication(KSCrashApplicationStateBackground));
    [tracker start];
    [center postNotificationName:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    [tracker stop];

    [self turnMainQueue];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);
}

// A tracker started before UIApplicationMain, by a +load, finds no application object. The one
// UIApplicationMain makes reads background on the run loop's first turn, before UIKit has started
// the launch, so that read must not label the launch.
- (void)testAppStateTrackerStartedBeforeTheApplicationExistsWaitsForTheLaunch
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, nil);
    [tracker start];

    gSharedFakeApplication = FakeApplication(KSCrashApplicationStateBackground);
    [self turnMainRunLoop];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateStartup);

    [center postNotificationName:@"UIApplicationDidFinishLaunchingNotification" object:nil];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);
    [tracker stop];
}

// Starts the tracker on a background thread and returns once start has.
static void StartOffTheMainThread(KSCrashAppStateTracker *tracker)
{
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [tracker start];
    });
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

- (void)testAppStateTrackerStartedOffTheMainThreadReadsOnTheMainRunLoop
{
    KSCrashAppStateTracker *tracker =
        AppTracker([NSNotificationCenter new], FakeApplication(KSCrashApplicationStateActive));
    StartOffTheMainThread(tracker);
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateStartup);

    [self turnMainRunLoop];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
    [tracker stop];
}

// The hop to the main run loop is the wait an inactive read needs, so it is not taken twice.
- (void)testAppStateTrackerStartedOffTheMainThreadTakesAnInactiveApplicationAfterOneTurn
{
    KSCrashAppStateTracker *tracker =
        AppTracker([NSNotificationCenter new], FakeApplication(KSCrashApplicationStateInactive));
    StartOffTheMainThread(tracker);

    [self turnMainRunLoop];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateDeactivating);
    [tracker stop];
}

- (void)testAppStateTrackerTakesAnInactiveApplicationAfterACallout
{
    KSCrashAppStateTracker *tracker =
        AppTracker([NSNotificationCenter new], FakeApplication(KSCrashApplicationStateInactive));
    [self inMainRunLoopCallout:^{
        [tracker start];
        XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateStartup);
    }];

    [self turnMainRunLoop];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateDeactivating);
    [tracker stop];
}

// An app without scenes reads inactive all through its launch; the launch notification follows in
// the same main run loop callout, before the tracker's second read.
- (void)testAppStateTrackerDropsAnInactiveReadOnceALaunchNotificationArrives
{
    NSNotificationCenter *center = [NSNotificationCenter new];
    KSCrashAppStateTracker *tracker = AppTracker(center, FakeApplication(KSCrashApplicationStateInactive));
    [self inMainRunLoopCallout:^{
        [tracker start];
        [center postNotificationName:@"UIApplicationDidFinishLaunchingNotification" object:nil];
        XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);
    }];

    [self turnMainRunLoop];
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateLaunching);
    [tracker stop];
}

- (void)testAppStateTrackerStateTakenFromARunningApplication
{
    KSCrashAppTransitionState startup = KSCrashAppTransitionStateStartup;

    XCTAssertEqual(ksapp_transitionStateForApplicationState(KSCrashApplicationStateActive, startup),
                   KSCrashAppTransitionStateActive);
    XCTAssertEqual(ksapp_transitionStateForApplicationState(KSCrashApplicationStateBackground, startup),
                   KSCrashAppTransitionStateBackground);
    XCTAssertEqual(ksapp_transitionStateForApplicationState(KSCrashApplicationStateInactive, startup),
                   KSCrashAppTransitionStateDeactivating);
}

#if KSCRASH_TEST_HAS_UIAPPLICATION_SYMBOLS
// The core mirrors these by value and by name; this is where the real symbols can be compared.
- (void)testAppStateTrackerMirrorsUIKit
{
    XCTAssertEqual((NSInteger)KSCrashApplicationStateActive, (NSInteger)UIApplicationStateActive);
    XCTAssertEqual((NSInteger)KSCrashApplicationStateInactive, (NSInteger)UIApplicationStateInactive);
    XCTAssertEqual((NSInteger)KSCrashApplicationStateBackground, (NSInteger)UIApplicationStateBackground);
    XCTAssertEqualObjects(NSClassFromString(@"UIApplication"), UIApplication.class);

    NSArray<NSNotificationName> *symbols = @[
        UIApplicationDidFinishLaunchingNotification,
        UIApplicationWillEnterForegroundNotification,
        UIApplicationDidBecomeActiveNotification,
        UIApplicationWillResignActiveNotification,
        UIApplicationDidEnterBackgroundNotification,
        UIApplicationWillTerminateNotification,
        UIApplicationProtectedDataDidBecomeAvailable,
        UIApplicationProtectedDataWillBecomeUnavailable,
        NSExtensionHostDidBecomeActiveNotification,
        NSExtensionHostWillResignActiveNotification,
        NSExtensionHostDidEnterBackgroundNotification,
        NSExtensionHostWillEnterForegroundNotification,
    ];
    NSArray<NSNotificationName> *names = @[
        KSApplicationDidFinishLaunchingNotification,
        KSApplicationWillEnterForegroundNotification,
        KSApplicationDidBecomeActiveNotification,
        KSApplicationWillResignActiveNotification,
        KSApplicationDidEnterBackgroundNotification,
        KSApplicationWillTerminateNotification,
        KSApplicationProtectedDataDidBecomeAvailableNotification,
        KSApplicationProtectedDataWillBecomeUnavailableNotification,
        KSExtensionHostDidBecomeActiveNotification,
        KSExtensionHostWillResignActiveNotification,
        KSExtensionHostDidEnterBackgroundNotification,
        KSExtensionHostWillEnterForegroundNotification,
    ];
    XCTAssertEqualObjects(symbols, names);
}
#endif

@end
