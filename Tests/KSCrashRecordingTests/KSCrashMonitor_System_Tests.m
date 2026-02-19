//
//  KSCrashMonitor_System_Tests.m
//
//  Created by Alexander Cohen on 2026-02-16.
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
#import "KSCrashMonitor_System.h"
#import "KSSysCtl.h"
#import "KSSystemCapabilities.h"

@interface KSCrashMonitor_System_Tests : XCTestCase
@end

@implementation KSCrashMonitor_System_Tests

- (void)testInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_system_getAPI();
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testOSVersionMatchesPlatform
{
    KSCrashMonitorAPI *api = kscm_system_getAPI();
    api->setEnabled(true, NULL);

    KSCrash_MonitorContext context = { 0 };
    api->addContextualInfoToEvent(&context, NULL);

    XCTAssertNotEqual(context.System.osVersion, NULL, @"osVersion should be populated");

#if TARGET_OS_SIMULATOR
    // On simulator, osVersion should come from SIMULATOR_RUNTIME_BUILD_VERSION,
    // not from kern.osversion (which returns the host macOS build).
    NSString *expected = [NSProcessInfo processInfo].environment[@"SIMULATOR_RUNTIME_BUILD_VERSION"];
    if (expected != nil) {
        XCTAssertEqualObjects(@(context.System.osVersion), expected,
                              @"Simulator osVersion should match SIMULATOR_RUNTIME_BUILD_VERSION");
    }

    // Verify it does NOT match the host kern.osversion
    char kernBuild[256] = { 0 };
    int len = kssysctl_stringForName("kern.osversion", kernBuild, sizeof(kernBuild));
    if (len > 0 && expected != nil) {
        XCTAssertNotEqualObjects(@(context.System.osVersion), @(kernBuild),
                                 @"Simulator osVersion should not be the host macOS build");
    }
#else
    // On real devices / macOS, osVersion should match kern.osversion
    char kernBuild[256] = { 0 };
    int len = kssysctl_stringForName("kern.osversion", kernBuild, sizeof(kernBuild));
    XCTAssertGreaterThan(len, 0);
    XCTAssertEqualObjects(@(context.System.osVersion), @(kernBuild),
                          @"osVersion should match kern.osversion on non-simulator");
#endif

    api->setEnabled(false, NULL);
}

@end
