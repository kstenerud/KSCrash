//
//  KSCrashMonitor_WatchdogStitch_Tests.m
//
//  Created by Alexander Cohen on 2026-02-01.
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

#import "KSCrashAppTransitionState.h"
#import "KSCrashC.h"
#import "KSCrashMonitor_Lifecycle.h"
#import "KSCrashMonitor_Watchdog.h"
#import "KSCrashMonitor_WatchdogSidecar.h"
#import "KSCrashReportFields.h"
#import "KSTaskRole.h"

#include <fcntl.h>
#include <unistd.h>

#pragma mark - Helpers

static NSString *createTempDir(void)
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *writeSidecar(NSString *dir, KSHangSidecar sc)
{
    NSString *path = [dir stringByAppendingPathComponent:@"test.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    NSCAssert(fd >= 0, @"Failed to open sidecar for writing: %s", path.UTF8String);
    ssize_t written = write(fd, &sc, sizeof(sc));
    NSCAssert(written == (ssize_t)sizeof(sc), @"Short write to sidecar");
    close(fd);
    return path;
}

static NSDictionary *makeMinimalHangReport(uint64_t startNanos, task_role_t startRole)
{
    return @{
        @"report" : @ { @"monitor_id" : @"Watchdog" },
        @"crash" : @ {
            @"error" : @ {
                @"type" : @"signal",
                @"hang" : @ {
                    @"hang_start_nanos" : @(startNanos),
                    @"hang_start_role" : @(kstaskrole_toString(startRole)),
                    @"hang_end_nanos" : @(0),
                    @"hang_end_role" : @"unknown",
                },
                @"signal" : @ { @"name" : @"SIGKILL" },
                @"mach" : @ { @"exception" : @(5) },
                @"exit_reason" : @ { @"code" : @(0x8badf00d) },
                @"is_fatal" : @YES,
                @"is_clean_exit" : @NO,
            },
        },
    };
}

// The stitch reads the report's run through RunContext, with the run sidecar paths the
// Watchdog monitor was initialized with. The tests point it at their own directory.
extern struct KSCrashMonitorSavedState *kscm_testcode_saveState(void);
extern void kscm_testcode_restoreState(struct KSCrashMonitorSavedState *saved);
static NSString *g_runSidecarsDir;

static bool testRunSidecarPathForRunID(const char *monitorId, const char *runID, char *pathBuffer,
                                       size_t pathBufferLength)
{
    NSString *path = [[g_runSidecarsDir stringByAppendingPathComponent:@(runID)]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.ksscr", monitorId]];
    return strlcpy(pathBuffer, path.fileSystemRepresentation, pathBufferLength) < pathBufferLength;
}

static NSString *const kTestRunID = @"5b1f0c3e-2d4a-4e6b-9c8d-7a6f5e4d3c2b";

/** Writes the lifecycle run sidecar of kTestRunID, recording how that run ended. */
static void writeLifecycle(bool cleanExit, bool monitorHandlerRan)
{
    KSCrash_LifecycleData lifecycle = {
        .magic = KSLIFECYCLE_MAGIC,
        .version = KSCrash_Lifecycle_CurrentVersion,
        .cleanExit = cleanExit,
        .monitorHandlerRan = monitorHandlerRan,
        .hangActive = true,
    };
    char path[PATH_MAX];
    NSCAssert(testRunSidecarPathForRunID("Lifecycle", kTestRunID.UTF8String, path, sizeof(path)), @"path too long");
    NSString *dir = [@(path) stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSData dataWithBytes:&lifecycle length:sizeof(lifecycle)] writeToFile:@(path) atomically:YES];
}

/** `report`, with kTestRunID as its run. */
static NSDictionary *inTestRun(NSDictionary *report)
{
    NSMutableDictionary *withRun = [report mutableCopy];
    NSMutableDictionary *info = [report[@"report"] mutableCopy] ?: [NSMutableDictionary dictionary];
    info[@"run_id"] = kTestRunID;
    withRun[@"report"] = info;
    return withRun;
}

#pragma mark - Tests

@interface KSCrashMonitor_WatchdogStitch_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@property(nonatomic, assign) struct KSCrashMonitorSavedState *savedMonitorState;
@end

@implementation KSCrashMonitor_WatchdogStitch_Tests

- (void)setUp
{
    [super setUp];
    self.tempDir = createTempDir();
    g_runSidecarsDir = [self.tempDir stringByAppendingPathComponent:@"RunSidecars"];
    self.savedMonitorState = kscm_testcode_saveState();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPathForRunID = testRunSidecarPathForRunID };
    KSCrashMonitorAPI *watchdog = kscm_watchdog_getAPI();
    watchdog->init(&callbacks, watchdog->context);
}

- (void)tearDown
{
    kscm_testcode_restoreState(self.savedMonitorState);
    g_runSidecarsDir = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - NULL / Invalid Input

- (void)testNullReportReturnsNull
{
    XCTAssertTrue(kscm_watchdog_createStitchedReport(NULL, "/tmp/fake", KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testNullSidecarPathReturnsNull
{
    XCTAssertTrue(
        kscm_watchdog_createStitchedReport((__bridge CFDictionaryRef) @{}, NULL, KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testMissingSidecarFileDeliversTheReportUnchanged
{
    NSString *missingPath = [self.tempDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSDictionary *report = @{ @"report" : @ {} };
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, missingPath.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertEqualObjects(result, report);
}

#pragma mark - Invalid Sidecar

// A sidecar no later read could make sense of is a verdict, not a hiccup:
// returning the stitch's retry signal for one stops the report being finalized
// for good. These deliver the report without this monitor's section instead.

- (void)testBadMagicDeliversTheReportUnchanged
{
    KSHangSidecar sc = {
        .magic = (int32_t)0xDEADBEEF,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 1000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(500, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertEqualObjects(result, report);
}

- (void)testVersionZeroDeliversTheReportUnchanged
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = 0,
        .endTimestamp = 1000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(500, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertEqualObjects(result, report);
}

- (void)testFutureVersionDeliversTheReportUnchanged
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_CURRENT_VERSION + 1,
        .endTimestamp = 1000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(500, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertEqualObjects(result, report);
}

#pragma mark - No Hang In Report

- (void)testReportWithoutHangCreatesHangFromSidecar
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 1000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{ @"crash" : @ { @"error" : @ { @"type" : @"signal" } } };

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertNotNil(result);
    // Hang section is created from the sidecar even when not in the original report
    XCTAssertNotNil(result[@"crash"][@"error"][@"hang"]);
}

#pragma mark - Fatal Hang (not recovered)

- (void)testFatalHangUpdatesEndTimestamp
{
    uint64_t endTs = 999000000;
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = endTs,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(100000000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *hang = result[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_end_nanos"], @(endTs));
}

- (void)testFatalHangKeepsSignalAndMach
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 2000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"type"], @"signal");
    XCTAssertNotNil(error[@"signal"]);
    XCTAssertNotNil(error[@"mach"]);
    XCTAssertNotNil(error[@"exit_reason"]);
}

- (void)testFatalHangSetsIsFatalAndIsCleanExit
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 2000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"is_fatal"], @YES);
    XCTAssertEqualObjects(error[@"is_clean_exit"], @NO);
}

- (void)testFatalHangSaysItDidNotRecover
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 2000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *hang = result[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_recovered"], @NO);
}

#pragma mark - Hang In Progress When Something Else Ended The Run

/** Stitches an unrecovered hang report whose run's lifecycle records the given ending. */
static NSDictionary *stitchHangInRunThatEnded(NSString *dir, bool cleanExit, bool monitorHandlerRan)
{
    writeLifecycle(cleanExit, monitorHandlerRan);

    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_CURRENT_VERSION,
        .endTimestamp = 2000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(dir, sc);

    NSDictionary *report = inTestRun(makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION));
    return (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
}

static void assertHangStillInProgress(NSDictionary *result)
{
    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"type"], @"hang");
    XCTAssertEqualObjects(error[@"is_fatal"], @NO);
    XCTAssertNil(error[@"is_clean_exit"]);
    XCTAssertNil(error[@"signal"]);
    XCTAssertNil(error[@"mach"]);
    XCTAssertNil(error[@"exit_reason"]);
    XCTAssertEqualObjects(error[@"hang"][@"hang_recovered"], @NO);
}

- (void)testHangDuringCrashIsAHangNotTheCauseOfDeath
{
    assertHangStillInProgress(stitchHangInRunThatEnded(self.tempDir, false, true));
}

- (void)testHangDuringSIGTERMIsAHangNotTheCauseOfDeath
{
    assertHangStillInProgress(stitchHangInRunThatEnded(self.tempDir, true, true));
}

- (void)testHangDuringCleanShutdownIsAHangNotTheCauseOfDeath
{
    assertHangStillInProgress(stitchHangInRunThatEnded(self.tempDir, true, false));
}

- (void)testHangWithNothingElseEndingTheRunIsTheCauseOfDeath
{
    NSDictionary *result = stitchHangInRunThatEnded(self.tempDir, false, false);
    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"is_fatal"], @YES);
    XCTAssertEqualObjects(error[@"is_clean_exit"], @NO);
    XCTAssertEqualObjects(error[@"signal"][@"name"], @"SIGKILL");
    XCTAssertEqualObjects(error[@"exit_reason"][@"code"], @(0x8badf00d));
}

- (void)testNonWatchdogReportDuringHangKeepsItsOwnError
{
    // The crash that ended the run is still the crash, with the hang as context.
    writeLifecycle(false, true);
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_CURRENT_VERSION,
        .endTimestamp = 2000,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);
    NSDictionary *report = @{
        @"report" : @ { @"monitor_id" : @"NSException", @"run_id" : kTestRunID },
        @"crash" : @ { @"error" : @ { @"type" : @"nsexception", @"is_fatal" : @YES, @"is_clean_exit" : @NO } },
    };

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"type"], @"nsexception");
    XCTAssertEqualObjects(error[@"is_fatal"], @YES);
    XCTAssertEqualObjects(error[@"hang"][@"hang_recovered"], @NO, @"the hang was still going when the run ended");
}

#pragma mark - No Readable Sidecar

/** The final pass over a watchdog report of kTestRunID that no sidecar was stitched into. */
static NSDictionary *finalPassOfUnstitchedHangReport(bool cleanExit, bool monitorHandlerRan)
{
    writeLifecycle(cleanExit, monitorHandlerRan);
    NSMutableDictionary *report = [inTestRun(makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION)) mutableCopy];
    NSMutableDictionary *crash = [report[@"crash"] mutableCopy];
    NSMutableDictionary *error = [crash[@"error"] mutableCopy];
    [error removeObjectForKey:@"hang"];
    crash[@"error"] = error;
    report[@"crash"] = crash;
    return (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport((__bridge CFDictionaryRef)report, NULL,
                                                                                KSCrashSidecarScopeFinal, NULL);
}

- (void)testAWatchdogReportWithNoSidecarIsAHangWhenACrashEndedTheRun
{
    NSDictionary *error = finalPassOfUnstitchedHangReport(false, true)[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"type"], @"hang");
    XCTAssertEqualObjects(error[@"is_fatal"], @NO);
    XCTAssertNil(error[@"signal"]);
    XCTAssertNil(error[@"mach"]);
    XCTAssertNil(error[@"exit_reason"]);
}

- (void)testAWatchdogReportWithNoSidecarIsAHangWhenTheRunExitedCleanly
{
    NSDictionary *error = finalPassOfUnstitchedHangReport(true, false)[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"type"], @"hang");
    XCTAssertEqualObjects(error[@"is_fatal"], @NO);
}

- (void)testAWatchdogReportWithNoSidecarIsADeathWhenNothingElseEndedTheRun
{
    NSDictionary *error = finalPassOfUnstitchedHangReport(false, false)[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"is_fatal"], @YES);
    XCTAssertEqualObjects(error[@"signal"][@"name"], @"SIGKILL");
}

- (void)testTheFinalPassLeavesAStitchedWatchdogReportAlone
{
    // The run pass already decided, from the sidecar: the hang recovered.
    writeLifecycle(false, false);
    NSDictionary *report = @{
        @"report" : @ { @"monitor_id" : @"Watchdog", @"run_id" : kTestRunID },
        @"crash" :
            @ { @"error" : @ { @"type" : @"hang", @"is_fatal" : @NO, @"hang" : @ { @"hang_recovered" : @YES } } },
    };
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, NULL, KSCrashSidecarScopeFinal, NULL);
    XCTAssertEqualObjects(result, report);
}

extern void kscrash_testcode_setRunID(const char *runID);

- (void)testTheFinalPassLeavesALiveRunsWatchdogReportAlone
{
    // The live run has not ended, so there is no cause of death to decide yet.
    const char *live = kscrash_getRunID();
    char savedRunID[64] = { 0 };
    if (live != NULL) {
        strlcpy(savedRunID, live, sizeof(savedRunID));
    }
    kscrash_testcode_setRunID(kTestRunID.UTF8String);
    NSDictionary *error = finalPassOfUnstitchedHangReport(false, true)[@"crash"][@"error"];
    kscrash_testcode_setRunID(savedRunID[0] != '\0' ? savedRunID : NULL);
    XCTAssertEqualObjects(error[@"type"], @"signal");
    XCTAssertEqualObjects(error[@"is_fatal"], @YES);
}

#pragma mark - Recovered Hang

- (void)testRecoveredHangSetsRecoveredFlag
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 5000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *hang = result[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_recovered"], @YES);
}

- (void)testRecoveredHangIsNonFatal
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 5000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"is_fatal"], @NO);
    XCTAssertNil(error[@"is_clean_exit"]);
}

- (void)testRecoveredHangChangesTypeToHang
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 5000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSString *type = result[@"crash"][@"error"][@"type"];
    XCTAssertEqualObjects(type, @"hang");
}

- (void)testRecoveredHangRemovesSignalMachAndExitReason
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 5000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertNil(error[@"signal"]);
    XCTAssertNil(error[@"mach"]);
    XCTAssertNil(error[@"exit_reason"]);
}

- (void)testRecoveredHangUpdatesEndTimestamp
{
    uint64_t endTs = 7777777;
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = endTs,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *hang = result[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_end_nanos"], @(endTs));
}

- (void)testRecoveredHangPreservesStartFields
{
    uint64_t startNanos = 42000000;
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .startTimestamp = startNanos,
        .startRole = TASK_FOREGROUND_APPLICATION,
        .endTimestamp = 99000000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(startNanos, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *hang = result[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_start_nanos"], @(startNanos));
    XCTAssertEqualObjects(hang[@"hang_start_role"], @(kstaskrole_toString(TASK_FOREGROUND_APPLICATION)));
}

#pragma mark - Truncated Sidecar

- (void)testTruncatedSidecarDeliversTheReportUnchanged
{
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"truncated.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    uint8_t partial[] = { 0x73, 0x68, 0x73, 0x6b };  // just magic bytes, incomplete
    write(fd, partial, sizeof(partial));
    close(fd);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertEqualObjects(result, report);
}

#pragma mark - Malformed Reports

- (void)testMissingCrashKeyReturnsNull
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 1000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{ @"other" : @"value" };

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == nil);
}

- (void)testCrashIsNSNullReturnsNull
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 1000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{ @"crash" : [NSNull null] };

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == nil);
}

- (void)testErrorIsNSNullReturnsNull
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 1000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{ @"crash" : @ { @"error" : [NSNull null] } };

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == nil);
}

- (void)testHangIsNSNullCreatesHangFromSidecar
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 1000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{ @"crash" : @ { @"error" : @ { @"type" : @"signal", @"hang" : [NSNull null] } } };

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertNotNil(result);
    XCTAssertNotNil(result[@"crash"][@"error"][@"hang"]);
}

#pragma mark - End Role

- (void)testStitchUpdatesHangEndRole
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 5000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != nil);

    NSDictionary *hang = result[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_end_role"], @"DEFAULT_APPLICATION");
}

#pragma mark - Transition State

- (void)testStitchWritesTransitionStatesFromSidecar
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .startTimestamp = 1000,
        .startRole = TASK_FOREGROUND_APPLICATION,
        .startTransitionState = KSCrashAppTransitionStateLaunching,
        .endTimestamp = 5000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .endTransitionState = KSCrashAppTransitionStateActive,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertNotNil(result);

    NSDictionary *hang = result[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_start_transition_state"], @"launching");
    XCTAssertEqualObjects(hang[@"hang_end_transition_state"], @"active");
}

- (void)testFatalHangIncludesTransitionStates
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .startTimestamp = 1000,
        .startRole = TASK_FOREGROUND_APPLICATION,
        .startTransitionState = KSCrashAppTransitionStateActive,
        .endTimestamp = 5000,
        .endRole = TASK_FOREGROUND_APPLICATION,
        .endTransitionState = KSCrashAppTransitionStateActive,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertNotNil(result);

    NSDictionary *hang = result[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_start_transition_state"], @"active");
    XCTAssertEqualObjects(hang[@"hang_end_transition_state"], @"active");
}

#pragma mark - Sidecar Scope

- (void)testReportScopeIsNoOp
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 5000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertNotNil(result);

    // Report scope should pass through unchanged — no hang modifications
    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"type"], @"signal", @"Type should be unchanged");
    XCTAssertEqualObjects(error[@"is_fatal"], @YES, @"is_fatal should be unchanged");
}

#pragma mark - Non-Watchdog Reports

- (void)testNonWatchdogReportKeepsOriginalFatality
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .startTimestamp = 1000,
        .startRole = TASK_FOREGROUND_APPLICATION,
        .endTimestamp = 5000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{
        @"report" : @ { @"monitor_id" : @"profile" },
        @"crash" : @ {
            @"error" : @ {
                @"type" : @"profile",
                @"is_fatal" : @NO,
            },
        },
    };

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertNotNil(result);

    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"is_fatal"], @NO, @"Non-watchdog report should keep its original is_fatal");
    XCTAssertEqualObjects(error[@"type"], @"profile", @"Non-watchdog report should keep its original type");
    XCTAssertNil(error[@"is_clean_exit"], @"Non-watchdog report should not gain is_clean_exit");
    XCTAssertNotNil(error[@"hang"], @"Hang section should still be added as context");
}

- (void)testNonWatchdogRecoveredHangKeepsOriginalFields
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .startTimestamp = 1000,
        .startRole = TASK_FOREGROUND_APPLICATION,
        .endTimestamp = 5000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{
        @"report" : @ { @"monitor_id" : @"Signal" },
        @"crash" : @ {
            @"error" : @ {
                @"type" : @"signal",
                @"is_fatal" : @YES,
                @"is_clean_exit" : @NO,
                @"signal" : @ { @"name" : @"SIGSEGV" },
                @"mach" : @ { @"exception" : @(1) },
            },
        },
    };

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertNotNil(result);

    NSDictionary *error = result[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"type"], @"signal", @"Signal report should keep its type");
    XCTAssertEqualObjects(error[@"is_fatal"], @YES, @"Signal report should keep its fatality");
    XCTAssertNotNil(error[@"signal"], @"Signal section should not be removed");
    XCTAssertNotNil(error[@"mach"], @"Mach section should not be removed");
    XCTAssertNotNil(error[@"hang"], @"Hang section should be added as context");
    XCTAssertEqualObjects(error[@"hang"][@"hang_recovered"], @YES);
}

#pragma mark - Start Values From Sidecar

- (void)testStartValuesOverwriteJsonValues
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .startTimestamp = 9999,
        .startRole = TASK_DEFAULT_APPLICATION,
        .startTransitionState = KSCrashAppTransitionStateBackground,
        .endTimestamp = 20000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .endTransitionState = KSCrashAppTransitionStateBackground,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    // JSON has different start values than the sidecar
    NSDictionary *report = makeMinimalHangReport(1111, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertNotNil(result);

    // Sidecar values must win
    NSDictionary *hang = result[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_start_nanos"], @(9999));
    XCTAssertEqualObjects(hang[@"hang_start_role"], @"DEFAULT_APPLICATION");
    XCTAssertEqualObjects(hang[@"hang_start_transition_state"], @"background");
}

@end
