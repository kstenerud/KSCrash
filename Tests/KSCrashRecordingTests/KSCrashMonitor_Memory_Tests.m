//
//  KSCrashMonitor_Memory_Tests.m
//
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
#import "KSCrashMonitor_Memory.h"
#import "KSSystemCapabilities.h"

@interface KSCrashMonitor_Memory_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Memory_Tests

- (void)setUp
{
    [super setUp];

    // reset defaults
    ksmemory_set_nonfatal_report_level(KSCrash_Memory_NonFatalReportLevelNone);
    ksmemory_set_fatal_reports_enabled(true);
    setenv("ActivePrewarm", "0", 1);
}

- (void)tearDown
{
    testsupport_KSCrashAppMemorySetProvider(nil);
    [super tearDown];
}

- (void)testInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_memory_getAPI();
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    [NSThread sleepForTimeInterval:0.1];
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testDoubleInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_memory_getAPI();

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));

    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testTransitionState
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

static KSCrashAppMemory *Memory(uint64_t footprint)
{
    return [[KSCrashAppMemory alloc] initWithFootprint:footprint
                                             remaining:100 - footprint
                                              pressure:KSCrashAppMemoryStateNormal];
}

- (void)testAppMemory
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

- (void)testNonFatalReportLevel
{
    XCTAssertEqual(ksmemory_get_nonfatal_report_level(), KSCrash_Memory_NonFatalReportLevelNone);

    ksmemory_set_nonfatal_report_level(12);
    XCTAssertEqual(ksmemory_get_nonfatal_report_level(), 12);

    ksmemory_set_nonfatal_report_level(KSCrashAppMemoryStateUrgent);
    XCTAssertEqual(ksmemory_get_nonfatal_report_level(), KSCrashAppMemoryStateUrgent);
}

- (void)testRapidEnableDisableCycles
{
    // Test rapid enable/disable cycles to ensure proper cleanup
    // This helps catch issues with memory mapping/unmapping
    KSCrashMonitorAPI *api = kscm_memory_getAPI();

    for (int i = 0; i < 10; i++) {
        api->setEnabled(true, NULL);
        XCTAssertTrue(api->isEnabled(NULL));
        api->setEnabled(false, NULL);
        XCTAssertFalse(api->isEnabled(NULL));
    }
}

- (void)testEnableDisableWithoutInitialize
{
    // Test that enable/disable handles edge cases gracefully
    KSCrashMonitorAPI *api = kscm_memory_getAPI();

    // Should handle being disabled when already disabled
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));

    // Enable then disable
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    [NSThread sleepForTimeInterval:0.05];
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

@end
