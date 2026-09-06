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
#import "KSCrashMonitorAPI.h"
#import "KSCrashMonitorType.h"

extern void kscm_testcode_resetState(void);
struct KSCrashMonitorSavedState;
extern struct KSCrashMonitorSavedState *kscm_testcode_saveState(void);
extern void kscm_testcode_restoreState(struct KSCrashMonitorSavedState *saved);
static struct KSCrashMonitorSavedState *g_savedMonitorState;
extern void kscrash_testcode_setMonitors(KSCrashMonitorType monitorTypes);
extern bool kscrash_testcode_setPluginMonitors(KSCrashMonitorAPI *apis, int count);
extern void kscmr_testcode_setDuplicateIdAsserts(bool asserts);
extern void kscrash_testcode_clearPluginMonitors(void);
extern void *kscrash_testcode_savePluginMonitors(void);
extern void kscrash_testcode_restorePluginMonitors(void *saved);

static const char *pluginMonitorId(__unused void *context) { return "TestPlugin"; }
static KSCrashMonitorFlag pluginMonitorFlags(__unused void *context) { return KSCrashMonitorFlagPlugin; }
static bool g_pluginEnabled = false;
static void pluginSetEnabled(bool enabled, __unused void *context) { g_pluginEnabled = enabled; }
static bool pluginIsEnabled(__unused void *context) { return g_pluginEnabled; }

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

- (void)testClearingPluginMonitorsUnregistersAndDisablesThem
{
    // A failed install releases the plugin objects the registry's context
    // pointers refer to, so the entries must not outlive the install attempt.
    void *savedPlugins = kscrash_testcode_savePluginMonitors();
    KSCrashMonitorAPI api = { 0 };
    kscma_initAPI(&api);
    api.monitorId = pluginMonitorId;
    api.monitorFlags = pluginMonitorFlags;
    api.setEnabled = pluginSetEnabled;
    api.isEnabled = pluginIsEnabled;
    XCTAssertTrue(kscrash_testcode_setPluginMonitors(&api, 1));
    XCTAssertNotEqual(kscm_getMonitor("TestPlugin"), NULL);
    g_pluginEnabled = true;

    kscrash_testcode_clearPluginMonitors();

    XCTAssertEqual(kscm_getMonitor("TestPlugin"), NULL);
    // enableMonitors has already switched the plugins on by the time install
    // can fail, so removal has to turn them back off.
    XCTAssertFalse(g_pluginEnabled);
    kscrash_testcode_restorePluginMonitors(savedPlugins);
}

- (void)testARefusedPluginFailsTheInstallInsteadOfSilentlyDroppingIt
{
    // Something registered ahead of the install already owns the id (a monitor that
    // self-registers on first use, say). The registry refuses the plugin, and the install
    // must report that rather than succeed without the coverage it was configured with.
    // The refusal asserts in debug builds; the seam turns that off for this one test.
    void *savedPlugins = kscrash_testcode_savePluginMonitors();
    KSCrashMonitorAPI earlier = { 0 };
    kscma_initAPI(&earlier);
    earlier.monitorId = pluginMonitorId;
    earlier.monitorFlags = pluginMonitorFlags;
    earlier.setEnabled = pluginSetEnabled;
    earlier.isEnabled = pluginIsEnabled;
    XCTAssertTrue(kscm_addMonitor(&earlier));

    KSCrashMonitorAPI plugin = earlier;
    kscmr_testcode_setDuplicateIdAsserts(false);
    bool installed = kscrash_testcode_setPluginMonitors(&plugin, 1);
    kscmr_testcode_setDuplicateIdAsserts(true);
    XCTAssertFalse(installed);
    // The earlier registration is untouched and nothing of the plugin's stayed behind.
    XCTAssertEqual(kscm_getMonitor("TestPlugin"), &earlier);

    kscm_removeMonitor(&earlier);
    kscrash_testcode_restorePluginMonitors(savedPlugins);
}

@end
