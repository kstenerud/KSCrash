//
//  KSCrashMonitor_ResourceTermination_Tests.m
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
#import "KSCrashMonitor_ResourceTermination.h"

// Test helper declared extern (defined in production code with __attribute__((unused)))
extern KSResourceTerminationReason kscm_resourcetermination_testcode_determineReason(
    const KSCrash_LifecycleData *lifecycle, const KSCrash_ResourceData *resource);

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

#pragma mark - Tests

@interface KSCrashMonitor_ResourceTermination_Tests : XCTestCase
@end

@implementation KSCrashMonitor_ResourceTermination_Tests

// MARK: - Clean shutdown / fatal reported → None

- (void)testCleanShutdownReturnsNone
{
    KSCrash_LifecycleData lc = makeLifecycle(true, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res), KSResourceTerminationReasonNone);
}

- (void)testFatalReportedReturnsNone
{
    KSCrash_LifecycleData lc = makeLifecycle(false, true);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res), KSResourceTerminationReasonNone);
}

// MARK: - NULL resource → None

- (void)testNullResourceReturnsNone
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, NULL), KSResourceTerminationReasonNone);
}

// MARK: - Individual termination reasons

- (void)testMemoryLimitCritical
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res),
                   KSResourceTerminationReasonMemoryLimit);
}

- (void)testMemoryLimitTerminal
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateTerminal;

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res),
                   KSResourceTerminationReasonMemoryLimit);
}

- (void)testMemoryPressureCritical
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryPressure = KSCrashAppMemoryStateCritical;

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res),
                   KSResourceTerminationReasonMemoryPressure);
}

- (void)testCPUExcessive
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.cpuCoreCount = 4;
    // 80% of 4 cores = 3200 permil threshold. Set user+system above that.
    res.cpuUsageUser = 2500;
    res.cpuUsageSystem = 800;

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res), KSResourceTerminationReasonCPU);
}

- (void)testCPUBelowThreshold
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.cpuCoreCount = 4;
    // Below 3200 threshold
    res.cpuUsageUser = 1000;
    res.cpuUsageSystem = 500;

    // Should be unexplained (nothing critical), not CPU
    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res),
                   KSResourceTerminationReasonUnexplained);
}

- (void)testThermalCritical
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.thermalState = 3;  // NSProcessInfoThermalStateCritical

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res), KSResourceTerminationReasonThermal);
}

- (void)testLowBattery
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.batteryLevel = 1;
    res.batteryState = 1;  // unplugged

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res), KSResourceTerminationReasonLowBattery);
}

- (void)testLowBatteryWhileChargingIsNotLowBattery
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.batteryLevel = 1;
    res.batteryState = 2;  // charging

    // Battery is low but plugged in — not a battery kill
    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res),
                   KSResourceTerminationReasonUnexplained);
}

// MARK: - Priority ordering

- (void)testMemoryLimitTakesPriorityOverPressure
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.memoryLevel = KSCrashAppMemoryStateCritical;
    res.memoryPressure = KSCrashAppMemoryStateCritical;

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res),
                   KSResourceTerminationReasonMemoryLimit);
}

- (void)testCPUTakesPriorityOverThermal
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.cpuCoreCount = 4;
    res.cpuUsageUser = 3000;
    res.cpuUsageSystem = 500;
    res.thermalState = 3;  // critical

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res), KSResourceTerminationReasonCPU);
}

- (void)testThermalTakesPriorityOverBattery
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    res.thermalState = 3;
    res.batteryLevel = 0;
    res.batteryState = 1;

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res), KSResourceTerminationReasonThermal);
}

// MARK: - Unexplained

- (void)testNothingCriticalReturnsUnexplained
{
    KSCrash_LifecycleData lc = makeLifecycle(false, false);
    KSCrash_ResourceData res = makeResource();
    // All fields at defaults (0/normal)

    XCTAssertEqual(kscm_resourcetermination_testcode_determineReason(&lc, &res),
                   KSResourceTerminationReasonUnexplained);
}

// MARK: - reasonToString

- (void)testReasonToString
{
    XCTAssertTrue(strcmp(ksresourcetermination_reasonToString(KSResourceTerminationReasonNone), "none") == 0);
    XCTAssertTrue(strcmp(ksresourcetermination_reasonToString(KSResourceTerminationReasonLowBattery), "low_battery") ==
                  0);
    XCTAssertTrue(
        strcmp(ksresourcetermination_reasonToString(KSResourceTerminationReasonMemoryLimit), "memory_limit") == 0);
    XCTAssertTrue(strcmp(ksresourcetermination_reasonToString(KSResourceTerminationReasonMemoryPressure),
                         "memory_pressure") == 0);
    XCTAssertTrue(strcmp(ksresourcetermination_reasonToString(KSResourceTerminationReasonThermal), "thermal") == 0);
    XCTAssertTrue(strcmp(ksresourcetermination_reasonToString(KSResourceTerminationReasonCPU), "cpu") == 0);
    XCTAssertTrue(strcmp(ksresourcetermination_reasonToString(KSResourceTerminationReasonUnexplained), "unexplained") ==
                  0);
}

@end
