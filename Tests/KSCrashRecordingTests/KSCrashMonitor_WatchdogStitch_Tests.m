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

#pragma mark - Tests

@interface KSCrashMonitor_WatchdogStitch_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation KSCrashMonitor_WatchdogStitch_Tests

- (void)setUp
{
    [super setUp];
    self.tempDir = createTempDir();
}

- (void)tearDown
{
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

- (void)testMissingSidecarFileReturnsNull
{
    NSString *missingPath = [self.tempDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef) @{}, missingPath.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == nil);
}

#pragma mark - Invalid Sidecar

- (void)testBadMagicReturnsNull
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
    XCTAssertTrue(result == nil);
}

- (void)testVersionZeroReturnsNull
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
    XCTAssertTrue(result == nil);
}

- (void)testFutureVersionReturnsNull
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
    XCTAssertTrue(result == nil);
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

- (void)testFatalHangDoesNotSetRecovered
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
    XCTAssertNil(hang[@"hang_recovered"]);
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

- (void)testTruncatedSidecarReturnsNull
{
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"truncated.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    uint8_t partial[] = { 0x73, 0x68, 0x73, 0x6b };  // just magic bytes, incomplete
    write(fd, partial, sizeof(partial));
    close(fd);

    NSDictionary *report = makeMinimalHangReport(1000, TASK_FOREGROUND_APPLICATION);

    NSDictionary *result = (__bridge_transfer NSDictionary *)kscm_watchdog_createStitchedReport(
        (__bridge CFDictionaryRef)report, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == nil);
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
