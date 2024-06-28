//
//  KSCrashMonitor_BootTime_Tests.m
//
//  Created by Gleb Linnik on 10.06.2024.
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
#import "KSCrashMonitor_BootTime.h"

#import "KSCrashMonitorContext.h"

extern void kscm_bootTime_resetState(void);

@interface KSCrashMonitorBootTimeTests : XCTestCase
@end

@implementation KSCrashMonitorBootTimeTests

- (void)setUp
{
    [super setUp];
    kscm_bootTime_resetState();
}

- (void)testMonitorActivation
{
    KSCrashMonitorAPI *bootTimeMonitor = kscm_boottime_getAPI();

    XCTAssertFalse(bootTimeMonitor->isEnabled(), @"Boot time monitor should be initially disabled.");
    bootTimeMonitor->setEnabled(true);
    XCTAssertTrue(bootTimeMonitor->isEnabled(), @"Boot time monitor should be enabled after setting.");
    bootTimeMonitor->setEnabled(false);
    XCTAssertFalse(bootTimeMonitor->isEnabled(), @"Boot time monitor should be disabled after setting.");
}

- (void)testAddContextualInfoWhenEnabled
{
    KSCrashMonitorAPI *bootTimeMonitor = kscm_boottime_getAPI();
    bootTimeMonitor->setEnabled(true);

    KSCrash_MonitorContext context = { 0 };
    bootTimeMonitor->addContextualInfoToEvent(&context);

    XCTAssertFalse(context.System.bootTime == NULL,
                   @"Boot time should be added to the context when the monitor is enabled.");

    // Clean up
    free((void *)context.System.bootTime);
}

- (void)testNoContextualInfoWhenDisabled
{
    KSCrashMonitorAPI *bootTimeMonitor = kscm_boottime_getAPI();
    bootTimeMonitor->setEnabled(false);

    KSCrash_MonitorContext context = { 0 };
    bootTimeMonitor->addContextualInfoToEvent(&context);

    XCTAssertTrue(context.System.bootTime == NULL,
                  @"Boot time should not be added to the context when the monitor is disabled.");
}

- (void)testDateSysctlFunctionIndirectly
{
    KSCrashMonitorAPI *bootTimeMonitor = kscm_boottime_getAPI();
    bootTimeMonitor->setEnabled(true);

    KSCrash_MonitorContext context = { 0 };
    bootTimeMonitor->addContextualInfoToEvent(&context);

    XCTAssertFalse(context.System.bootTime == NULL,
                   @"The boot time string should not be NULL when monitor is enabled.");

    NSString *bootTimeString = [NSString stringWithUTF8String:context.System.bootTime];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";  // Format from ksdate_utcStringFromTimestamp
    dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

    NSDate *bootTimeDate = [dateFormatter dateFromString:bootTimeString];

    XCTAssertNotNil(bootTimeDate, @"The boot time string should be a valid date string.");

    // Clean up
    free((void *)context.System.bootTime);
}

- (void)testMonitorName
{
    KSCrashMonitorAPI *bootTimeMonitor = kscm_boottime_getAPI();
    XCTAssertEqual(strcmp(bootTimeMonitor->monitorId(), "BootTime"), 0, @"The monitor name should be 'BootTime'.");
}

@end
