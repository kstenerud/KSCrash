//
//  KSCrashMonitorSelection_Tests.m
//
//  Created by Mischan Toosarani-Hausberger on 2026-07-09.
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
#import "KSSystemCapabilities.h"

#import "KSCrashMonitor.h"
#import "KSCrashMonitorType.h"

extern void kscm_testcode_resetState(void);
struct KSCrashMonitorSavedState;
extern struct KSCrashMonitorSavedState *kscm_testcode_saveState(void);
extern void kscm_testcode_restoreState(struct KSCrashMonitorSavedState *saved);
static struct KSCrashMonitorSavedState *g_savedMonitorState;
extern void kscrash_testcode_setMonitors(KSCrashMonitorType monitorTypes);

@interface KSCrashMonitorSelection_Tests : XCTestCase
@end

@implementation KSCrashMonitorSelection_Tests

- (void)setUp
{
    [super setUp];
    g_savedMonitorState = kscm_testcode_saveState();
    kscm_testcode_resetState();
}

- (void)tearDown
{
    kscm_testcode_restoreState(g_savedMonitorState);
    [super tearDown];
}

- (void)testCustomMonitorMaskRegistersRequiredInfrastructureMonitors
{
    kscrash_testcode_setMonitors(KSCrashMonitorTypeUserReported);

    XCTAssertNotEqual(kscm_getMonitor("UserReported"), NULL);
    XCTAssertNotEqual(kscm_getMonitor("System"), NULL);
    XCTAssertNotEqual(kscm_getMonitor("Lifecycle"), NULL);
    XCTAssertNotEqual(kscm_getMonitor("UserInfo"), NULL);
    XCTAssertNotEqual(kscm_getMonitor("Resource"), NULL);

    XCTAssertEqual(kscm_getMonitor("Signal"), NULL);
    XCTAssertEqual(kscm_getMonitor("MachException"), NULL);
    XCTAssertEqual(kscm_getMonitor("NSException"), NULL);
    XCTAssertEqual(kscm_getMonitor("Zombie"), NULL);
}

- (void)testUserReportedIsAlwaysRegistered
{
    kscrash_testcode_setMonitors(KSCrashMonitorTypeNone);
    XCTAssertNotEqual(kscm_getMonitor("UserReported"), NULL);
    XCTAssertNotEqual(kscm_getMonitor("System"), NULL);
    XCTAssertEqual(kscm_getMonitor("Signal"), NULL);
}

- (void)testDefaultSetIsEveryDetectorButZombie
{
    kscrash_testcode_setMonitors(KSCrashMonitorTypeDefault);
    // Only the detectors this platform compiles in can register.
    NSMutableArray<NSString *> *expected =
        [@[ @"CPPException", @"NSException", @"Termination", @"Watchdog" ] mutableCopy];
#if KSCRASH_HAS_MACH
    [expected addObject:@"MachException"];
#endif
#if KSCRASH_HAS_SIGNAL
    [expected addObject:@"Signal"];
#endif
    for (NSString *monitor in expected) {
        XCTAssertNotEqual(kscm_getMonitor(monitor.UTF8String), NULL, @"%@", monitor);
    }
    XCTAssertEqual(kscm_getMonitor("Zombie"), NULL);
    kscrash_testcode_setMonitors(KSCrashMonitorTypeAll);
    XCTAssertNotEqual(kscm_getMonitor("Zombie"), NULL);
}

@end
