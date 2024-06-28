//
//  KSCrashMonitor_DiscSpace_Tests.m
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
#import "KSCrashMonitorContext.h"

#import "KSCrashMonitor_DiscSpace.h"

// Function to reset global state for tests
extern void kscm_discSpace_resetState(void);

@interface KSCrashMonitorDiscSpaceTests : XCTestCase
@end

@implementation KSCrashMonitorDiscSpaceTests

- (void)setUp
{
    [super setUp];
    kscm_discSpace_resetState();
}

- (void)testMonitorActivation
{
    KSCrashMonitorAPI *discSpaceMonitor = kscm_discspace_getAPI();

    XCTAssertFalse(discSpaceMonitor->isEnabled(), @"Disc space monitor should be initially disabled.");
    discSpaceMonitor->setEnabled(true);
    XCTAssertTrue(discSpaceMonitor->isEnabled(), @"Disc space monitor should be enabled after setting.");
    discSpaceMonitor->setEnabled(false);
    XCTAssertFalse(discSpaceMonitor->isEnabled(), @"Disc space monitor should be disabled after setting.");
}

- (void)testAddContextualInfoWhenEnabled
{
    KSCrashMonitorAPI *discSpaceMonitor = kscm_discspace_getAPI();
    discSpaceMonitor->setEnabled(true);

    KSCrash_MonitorContext context = { 0 };
    discSpaceMonitor->addContextualInfoToEvent(&context);

    // Check that storage size is added to the context
    XCTAssertFalse(context.System.storageSize == 0,
                   @"Storage size should be added to the context when the monitor is enabled.");
}

- (void)testNoContextualInfoWhenDisabled
{
    KSCrashMonitorAPI *discSpaceMonitor = kscm_discspace_getAPI();
    discSpaceMonitor->setEnabled(false);

    KSCrash_MonitorContext context = { 0 };
    discSpaceMonitor->addContextualInfoToEvent(&context);

    XCTAssertTrue(context.System.storageSize == 0,
                  @"Storage size should not be added to the context when the monitor is disabled.");
}

- (void)testMonitorName
{
    KSCrashMonitorAPI *discSpaceMonitor = kscm_discspace_getAPI();
    XCTAssertEqual(strcmp(discSpaceMonitor->monitorId(), "DiscSpace"), 0, @"The monitor name should be 'DiscSpace'.");
}

@end
