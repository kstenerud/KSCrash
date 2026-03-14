//
//  KSCrashMonitor_Termination_Tests.m
//
//  Created by Alexander Cohen on 2026-03-07.
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

#import "KSCrashAppMemory.h"
#import "KSCrashMonitor_Lifecycle.h"
#import "KSCrashMonitor_Resource.h"
#import "KSCrashMonitor_System.h"
#import "KSCrashMonitor_Termination.h"

// Test helper declared extern (defined in production code with __attribute__((unused)))
extern KSTerminationReason kscm_termination_testcode_determineReason(const KSCrash_LifecycleData *prevLifecycle,
                                                                     const KSCrash_ResourceData *prevResource,
                                                                     const KSCrash_SystemData *prevSystem,
                                                                     const KSCrash_SystemData *currSystem);

#pragma mark - Helpers

static KSCrash_LifecycleData makeLifecycle(bool cleanShutdown, bool fatalReported)
{
    KSCrash_LifecycleData lc = { 0 };
    lc.magic = KSLIFECYCLE_MAGIC;
    lc.version = KSCrash_Lifecycle_CurrentVersion;
    lc.cleanShutdown = cleanShutdown;
    lc.fatalReported = fatalReported;
    return lc;
}

static KSCrash_ResourceData makeResource(void)
{
    KSCrash_ResourceData res = { 0 };
    res.magic = KSRESOURCE_MAGIC;
    res.version = KSCrash_Resource_CurrentVersion;
    res.cpuCoreCount = 4;
    return res;
}

static KSCrash_SystemData makeSystem(const char *systemVersion, const char *osVersion, const char *bundleShortVersion,
                                     const char *bundleVersion, int64_t bootTimestamp)
{
    KSCrash_SystemData sys = { 0 };
    sys.magic = KSSYS_MAGIC;
    sys.version = KSCrash_System_CurrentVersion;
    strlcpy(sys.systemVersion, systemVersion, sizeof(sys.systemVersion));
    strlcpy(sys.osVersion, osVersion, sizeof(sys.osVersion));
    strlcpy(sys.bundleShortVersion, bundleShortVersion, sizeof(sys.bundleShortVersion));
    strlcpy(sys.bundleVersion, bundleVersion, sizeof(sys.bundleVersion));
    sys.bootTimestamp = bootTimestamp;
    return sys;
}

/** Identical system data for tests that only exercise resource-based detection. */
static KSCrash_SystemData sameSystem(void) { return makeSystem("17.4", "21E258", "1.0", "100", 1000); }

#pragma mark - Tests

@interface KSCrashMonitor_Termination_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Termination_Tests

// MARK: - Clean shutdown / fatal reported → None

- (void)testCleanShutdownReturnsClean
{
    KSCrash_LifecycleData lc = makeLifecycle(true, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonClean);
}

- (void)testFatalReportedReturnsCrash
{
    KSCrash_LifecycleData lc = makeLifecycle(false, true);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonCrash);
}

// MARK: - Hang in progress → Hang

- (void)testHangInProgressReturnsHang
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    lc.hangInProgress = true;
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonHang);
}

// MARK: - First launch

- (void)testNoPrevSystemWithLifecycleReturnsUnexplained
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);

    // Lifecycle exists so we know a prior run happened — missing system is unexplained, not first launch.
    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, NULL, NULL, NULL), KSTerminationReasonUnexplained);
}

- (void)testNoPrevSystemWithResourceStillReturnsUnexplained
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;

    // Even with critical memory, no prevSystem means unexplained (lifecycle proves a prior run existed).
    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, NULL, NULL), KSTerminationReasonUnexplained);
}

// MARK: - Individual resource termination reasons

- (void)testMemoryLimitCritical
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonMemoryLimit);
}

- (void)testMemoryLimitTerminal
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateTerminal;
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonMemoryLimit);
}

- (void)testMemoryPressureCritical
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryPressure = KSCrashAppMemoryStateCritical;
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonMemoryPressure);
}

- (void)testCPUExcessive
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.cpuCoreCount = 4;
    // 80% of 4 cores = 3200 permil threshold. Set user+system above that.
    res.cpuUsageUser = 2500;
    res.cpuUsageSystem = 800;
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonCPU);
}

- (void)testCPUBelowThreshold
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.cpuCoreCount = 4;
    // Below 3200 threshold
    res.cpuUsageUser = 1000;
    res.cpuUsageSystem = 500;
    KSCrash_SystemData sys = sameSystem();

    // Should be unexplained (nothing critical), not CPU
    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonUnexplained);
}

- (void)testThermalCritical
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.thermalState = 3;  // NSProcessInfoThermalStateCritical
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonThermal);
}

- (void)testLowBattery
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.batteryLevel = 1;
    res.batteryState = 1;  // unplugged
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonLowBattery);
}

- (void)testLowBatteryWhileChargingIsNotLowBattery
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.batteryLevel = 1;
    res.batteryState = 2;  // charging
    KSCrash_SystemData sys = sameSystem();

    // Battery is low but plugged in — not a battery kill
    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonUnexplained);
}

// MARK: - System change reasons

- (void)testOSUpgrade
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.5", "21F258", "1.0", "100", 2000);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonOSUpgrade);
}

- (void)testAppUpgradeShortVersion
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.4", "21E258", "1.1", "100", 1000);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonAppUpgrade);
}

- (void)testAppUpgradeBuildVersion
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.4", "21E258", "1.0", "101", 1000);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonAppUpgrade);
}

- (void)testReboot
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.4", "21E258", "1.0", "100", 2000);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonReboot);
}

- (void)testOSUpgradeTakesPriorityOverReboot
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    // OS upgraded AND boot timestamp changed — OS upgrade wins.
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.5", "21F258", "1.0", "100", 2000);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonOSUpgrade);
}

- (void)testSystemChangeTakesPriorityOverResource
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;
    // Reboot detected — should take priority over memory limit.
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.4", "21E258", "1.0", "100", 2000);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonReboot);
}

- (void)testOSVersionOnlyChangeIsOSUpgrade
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    // Same systemVersion, different osVersion (build number changed).
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.4", "21E300", "1.0", "100", 1000);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonOSUpgrade);
}

- (void)testNoSystemChangeReturnsUnexplained
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.4", "21E258", "1.0", "100", 1000);

    // No system change, resource data exists but nothing critical → unexplained
    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonUnexplained);
}

- (void)testRebootZeroPrevTimestampIsNotReboot
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    // prev boot timestamp is zero (couldn't read it) — should not detect reboot.
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 0);
    KSCrash_SystemData curr = makeSystem("17.4", "21E258", "1.0", "100", 2000);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonUnexplained);
}

- (void)testRebootZeroCurrTimestampIsNotReboot
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.4", "21E258", "1.0", "100", 0);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonUnexplained);
}

- (void)testRebootWithinJitterIsNotReboot
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    // 15 seconds difference — within 30s jitter tolerance.
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.4", "21E258", "1.0", "100", 1015);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonUnexplained);
}

- (void)testRebootJustOutsideJitter
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    // 31 seconds difference — just beyond 30s jitter tolerance.
    KSCrash_SystemData prev = makeSystem("17.4", "21E258", "1.0", "100", 1000);
    KSCrash_SystemData curr = makeSystem("17.4", "21E258", "1.0", "100", 1031);

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &prev, &curr), KSTerminationReasonReboot);
}

// MARK: - Priority ordering (resource)

- (void)testMemoryLimitTakesPriorityOverPressure
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;
    res.memoryPressure = KSCrashAppMemoryStateCritical;
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonMemoryLimit);
}

- (void)testCPUTakesPriorityOverThermal
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.cpuCoreCount = 4;
    res.cpuUsageUser = 3000;
    res.cpuUsageSystem = 500;
    res.thermalState = 3;  // critical
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonCPU);
}

- (void)testThermalTakesPriorityOverBattery
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.thermalState = 3;
    res.batteryLevel = 0;
    res.batteryState = 1;
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonThermal);
}

// MARK: - Unexplained

- (void)testNothingCriticalReturnsUnexplained
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    KSCrash_SystemData sys = sameSystem();

    XCTAssertEqual(kscm_termination_testcode_determineReason(&lc, &res, &sys, &sys), KSTerminationReasonUnexplained);
}

// MARK: - reasonToString

- (void)testReasonToString
{
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonNone), "none") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonClean), "clean") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonCrash), "crash") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonHang), "hang") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonFirstLaunch), "first_launch") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonLowBattery), "low_battery") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonMemoryLimit), "memory_limit") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonMemoryPressure), "memory_pressure") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonThermal), "thermal") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonCPU), "cpu") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonOSUpgrade), "os_upgrade") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonAppUpgrade), "app_upgrade") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonReboot), "reboot") == 0);
    XCTAssertTrue(strcmp(kstermination_reasonToString(KSTerminationReasonUnexplained), "unexplained") == 0);
}

// MARK: - producesReport

- (void)testProducesReportForResourceKills
{
    XCTAssertTrue(kstermination_producesReport(KSTerminationReasonMemoryLimit));
    XCTAssertTrue(kstermination_producesReport(KSTerminationReasonMemoryPressure));
    XCTAssertTrue(kstermination_producesReport(KSTerminationReasonCPU));
    XCTAssertTrue(kstermination_producesReport(KSTerminationReasonThermal));
    XCTAssertTrue(kstermination_producesReport(KSTerminationReasonLowBattery));
    XCTAssertTrue(kstermination_producesReport(KSTerminationReasonUnexplained));
}

- (void)testProducesReportForCrashAndHang
{
    XCTAssertTrue(kstermination_producesReport(KSTerminationReasonCrash));
    XCTAssertTrue(kstermination_producesReport(KSTerminationReasonHang));
}

- (void)testDoesNotProduceReportForNonCrashReasons
{
    XCTAssertFalse(kstermination_producesReport(KSTerminationReasonNone));
    XCTAssertFalse(kstermination_producesReport(KSTerminationReasonClean));
    XCTAssertFalse(kstermination_producesReport(KSTerminationReasonFirstLaunch));
    XCTAssertFalse(kstermination_producesReport(KSTerminationReasonOSUpgrade));
    XCTAssertFalse(kstermination_producesReport(KSTerminationReasonAppUpgrade));
    XCTAssertFalse(kstermination_producesReport(KSTerminationReasonReboot));
}

@end
