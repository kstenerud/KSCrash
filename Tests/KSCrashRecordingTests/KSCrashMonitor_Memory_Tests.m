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

@interface KSCrashMonitor_Memory_Tests : XCTestCase @end

@implementation KSCrashMonitor_Memory_Tests

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
    __KSCrashAppMemorySetProvider(^KSCrashAppMemory * _Nonnull{
        return [[KSCrashAppMemory alloc] initWithFootprint:100
                                                 remaining:0
                                                  pressure:KSCrashAppMemoryStateNormal];
    });
    
    // setup
    NSURL *installURL = [NSURL fileURLWithPath:@"/tmp/kscrash" isDirectory:YES];
    NSURL *reportsPath = [[installURL URLByAppendingPathComponent:@"Data"] URLByAppendingPathComponent:@"Reports"];
    NSURL *memoryURL = [[installURL URLByAppendingPathComponent:@"Data"] URLByAppendingPathComponent:@"memory"];
    NSURL *breadcrumbURL = [[installURL URLByAppendingPathComponent:@"Data"] URLByAppendingPathComponent:@"oom_breadcrumb_report.json"];
    
    // clear old files in case
    NSFileManager *mngr = [NSFileManager new];
    [mngr removeItemAtURL:memoryURL error:nil];
    [mngr removeItemAtURL:breadcrumbURL error:nil];
    
    // init
    kscrash_setMonitoring(KSCrashMonitorTypeMemoryTermination);
    kscrash_install("test", installURL.path.UTF8String);

    // init memory API
    KSCrashMonitorAPI* api = kscm_memory_getAPI();
    XCTAssertTrue(api->isEnabled());
    
    // validate we didn't OOM
    BOOL userPerceptible = NO;
    BOOL oomed = ksmemory_previous_session_was_terminated_due_to_memory(&userPerceptible);
    XCTAssertFalse(oomed);
    XCTAssertTrue(userPerceptible);

    // notify we're launching and becoming active
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidFinishLaunchingNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    
    // Pump the runloop a bit
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0]];
    
    // disable
    kscrash_setMonitoring(KSCrashMonitorTypeNone);
    XCTAssertFalse(api->isEnabled());
    
    kscrash_setMonitoring(KSCrashMonitorTypeMemoryTermination);
    XCTAssertTrue(api->isEnabled());
    
    // init again
    ksmemory_initialize(installURL.path.UTF8String);
    
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
    XCTAssertFalse( ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionStateStartupPrewarm));
    XCTAssertFalse( ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionStateBackground));
    XCTAssertFalse( ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionStateTerminating));
    XCTAssertFalse( ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionStateExiting));
    
    XCTAssertTrue( ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionStateStartup));
    XCTAssertTrue( ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionStateLaunching));
    XCTAssertTrue( ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionStateForegrounding));
    XCTAssertTrue( ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionStateActive));
    XCTAssertTrue( ksapp_transition_state_is_user_perceptible(KSCrash_ApplicationTransitionStateDeactivating));
}

@end
