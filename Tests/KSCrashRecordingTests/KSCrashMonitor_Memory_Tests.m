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

#import "KSSystemCapabilities.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Memory.h"
#import "KSCrashReportStore.h"
#import "KSCrashAppStateTracker.h"
#import "KSCrashAppMemory+Private.h"

@interface KSCrashMonitor_Memory_Tests : XCTestCase @end

@implementation KSCrashMonitor_Memory_Tests

- (void)setUp
{
    [super setUp];
    
    // reset defaults
    ksmemory_set_nonfatal_report_level(KSCrash_Memory_NonFatalReportLevelNone);
    ksmemory_set_fatal_reports_enabled(true);
    setenv("ActivePrewarm", "0", 1);
}

- (void) testInstallAndRemove
{
    KSCrashMonitorAPI* api = kscm_memory_getAPI();
    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());
    [NSThread sleepForTimeInterval:0.1];
    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
}

- (void) testDoubleInstallAndRemove
{
    KSCrashMonitorAPI* api = kscm_memory_getAPI();
    
    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());
    api->setEnabled(true);
    XCTAssertTrue(api->isEnabled());
    
    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
    api->setEnabled(false);
    XCTAssertFalse(api->isEnabled());
}

- (void) testInstallation
{
    (void)KSCrash.sharedInstance;
    
    __KSCrashAppMemorySetProvider(^KSCrashAppMemory * _Nonnull{
        return [[KSCrashAppMemory alloc] initWithFootprint:100
                                                 remaining:0
                                                  pressure:KSCrashAppMemoryStateNormal];
    });
    
    // setup
    NSURL *installURL = [NSURL fileURLWithPath:@"/tmp/kscrash" isDirectory:YES];
    NSURL *dataURL = [installURL URLByAppendingPathComponent:@"Data"];
    NSURL *reportsPath = [installURL URLByAppendingPathComponent:@"Reports"];
    NSURL *memoryURL = [dataURL URLByAppendingPathComponent:@"memory.bin"];
    NSURL *breadcrumbURL = [dataURL URLByAppendingPathComponent:@"oom_breadcrumb_report.json"];
    
    // clear old files in case
    NSFileManager *mngr = [NSFileManager new];
    [mngr removeItemAtURL:memoryURL error:nil];
    [mngr removeItemAtURL:breadcrumbURL error:nil];
    
    
    // init
    kscrash_install("test", installURL.path.UTF8String);
    kscrash_setMonitoring(KSCrashMonitorTypeMemoryTermination);
    
    // init memory API
    KSCrashMonitorAPI* api = kscm_memory_getAPI();
    XCTAssertTrue(api->isEnabled());
    
    // validate we didn't OOM
    bool userPerceptible = false;
    BOOL oomed = ksmemory_previous_session_was_terminated_due_to_memory(&userPerceptible);
    XCTAssertFalse(oomed);
    XCTAssertTrue(userPerceptible);

#if KSCRASH_HAS_UIAPPLICATION
    // notify we're launching and becoming active
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidFinishLaunchingNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
#endif
    
    // disable
    kscrash_setMonitoring(KSCrashMonitorTypeNone);
    XCTAssertFalse(api->isEnabled());
    
    // init again
    ksmemory_initialize(dataURL.path.UTF8String);
    
    kscrash_setMonitoring(KSCrashMonitorTypeMemoryTermination);
    XCTAssertTrue(api->isEnabled());
    
    // notify the system is enabled
    api->notifyPostSystemEnable();
    
    // check oom
    oomed = ksmemory_previous_session_was_terminated_due_to_memory(&userPerceptible);
    XCTAssertTrue(oomed);
    XCTAssertTrue(userPerceptible);

    // check the last report, it should be the OOM report
    NSMutableArray<NSDictionary *> *reports = [NSMutableArray array];
    int64_t reportIDs[10] = {0};
    kscrash_getReportIDs(reportIDs, 10);
    for (int index = 0; index < 10; index++) {
        int64_t reportID = reportIDs[index];
        if (reportID) {
            char *report = kscrash_readReport(reportID);
            if (report) {
                NSData *data = [[NSData alloc] initWithBytes:report length:strlen(report)];
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                [reports addObject:json];
                free(report);
            }
        }
    }
    XCTAssert(reports.count > 0);
    
    NSUInteger oomReports = 0;
    for (NSDictionary<NSString *, id> *report in reports) {
        
        if (![report[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashField_Type] isEqualToString:@KSCrashExcType_MemoryTermination]) {
            continue;
        }
        
        oomReports++;
        
        XCTAssertEqualObjects(report[@KSCrashField_System][@KSCrashField_AppMemory][@KSCrashField_MemoryLevel], @"terminal");
        XCTAssertEqualObjects(report[@KSCrashField_System][@KSCrashField_AppMemory][@KSCrashField_MemoryPressure], @"normal");
        XCTAssertEqualObjects(report[@KSCrashField_System][@KSCrashField_AppMemory][@KSCrashField_MemoryFootprint], @(100));
        XCTAssertEqualObjects(report[@KSCrashField_System][@KSCrashField_AppMemory][@KSCrashField_MemoryRemaining], @(0));
        XCTAssertEqualObjects(report[@KSCrashField_System][@KSCrashField_AppMemory][@KSCrashField_MemoryLimit], @(100));
        
        XCTAssertEqualObjects(report[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashField_MemoryTermination][@KSCrashField_MemoryLevel], @"terminal");
        XCTAssertEqualObjects(report[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashField_MemoryTermination][@KSCrashField_MemoryPressure], @"normal");
        XCTAssertEqualObjects(report[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashField_MemoryTermination][@KSCrashField_MemoryFootprint], @(100));
        XCTAssertEqualObjects(report[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashField_MemoryTermination][@KSCrashField_MemoryRemaining], @(0));
        XCTAssertEqualObjects(report[@KSCrashField_Crash][@KSCrashField_Error][@KSCrashField_MemoryTermination][@KSCrashField_MemoryLimit], @(100));
        
        XCTAssertEqualObjects(report [@KSCrashField_Crash][@KSCrashField_Error][@KSCrashExcType_Signal][@KSCrashField_Signal], @(SIGKILL));
        XCTAssertEqualObjects(report [@KSCrashField_Crash][@KSCrashField_Error][@KSCrashExcType_Signal][@KSCrashField_Name], @"SIGKILL");
        
    }
    
    XCTAssert(oomReports > 0);
}

- (void) testTransitionState
{
    XCTAssertFalse(ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionStateStartupPrewarm));
    XCTAssertFalse(ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionStateBackground));
    XCTAssertFalse(ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionStateTerminating));
    XCTAssertFalse(ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionStateExiting));
    
    XCTAssertTrue(ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionStateStartup));
    XCTAssertTrue(ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionStateLaunching));
    XCTAssertTrue(ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionStateForegrounding));
    XCTAssertTrue(ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionStateActive));
    XCTAssertTrue(ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionStateDeactivating));
}

static KSCrashAppMemory *Memory(uint64_t footprint) {
    return [[KSCrashAppMemory alloc] initWithFootprint:footprint remaining:100-footprint pressure:KSCrashAppMemoryStateNormal];
}

- (void) testAppMemory
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
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    setenv("ActivePrewarm", "0", 1);
    __block KSCrashAppTransitionState state;
    
    KSCrashAppStateTracker *tracker = [KSCrashAppStateTracker new];
    [tracker addObserverWithBlock:^(KSCrashAppTransitionState transitionState) {
        state = transitionState;
    }];
    
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateStartup);
    
    [tracker start];
    
#if KSCRASH_HAS_UIAPPLICATION
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
#else
    XCTAssertEqual(tracker.transitionState, KSCrashAppTransitionStateActive);
    XCTAssertEqual(tracker.transitionState, state);
#endif
}

- (void)testReportMemoryTerminationsDefault
{
    KSCrash* handler = [KSCrash sharedInstance];
    XCTAssertTrue(handler.reportsMemoryTerminations);
    
    [handler install];
    
    XCTAssertTrue(handler.reportsMemoryTerminations);
}

- (void)testReportMemoryTerminationsOff
{
    KSCrash* handler = [KSCrash sharedInstance];
    XCTAssertTrue(handler.reportsMemoryTerminations);

    handler.reportsMemoryTerminations = NO;
    [handler install];
    
    XCTAssertFalse(handler.reportsMemoryTerminations);
}

- (void) testNonFatalReportLevel
{
    XCTAssertEqual(ksmemory_get_nonfatal_report_level(), KSCrash_Memory_NonFatalReportLevelNone);
    
    ksmemory_set_nonfatal_report_level(12);
    XCTAssertEqual(ksmemory_get_nonfatal_report_level(), 12);
    
    ksmemory_set_nonfatal_report_level(KSCrashAppMemoryStateUrgent);
    XCTAssertEqual(ksmemory_get_nonfatal_report_level(), KSCrashAppMemoryStateUrgent);
}

@end
