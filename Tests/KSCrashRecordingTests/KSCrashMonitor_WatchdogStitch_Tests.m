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

#import "KSCrashMonitor_WatchdogSidecar.h"
#import "KSCrashReportFields.h"
#import "KSJSONCodecObjC.h"

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
    write(fd, &sc, sizeof(sc));
    close(fd);
    return path;
}

static NSDictionary *makeMinimalHangReport(uint64_t startNanos, NSString *startRole)
{
    return @{
        @"crash" : @ {
            @"error" : @ {
                @"type" : @"signal",
                @"hang" : @ {
                    @"hang_start_nanos" : @(startNanos),
                    @"hang_start_role" : startRole,
                    @"hang_end_nanos" : @(0),
                    @"hang_end_role" : @"unknown",
                },
                @"signal" : @ { @"name" : @"SIGKILL" },
                @"mach" : @ { @"exception" : @(5) },
                @"exit_reason" : @ { @"code" : @(0x8badf00d) },
            },
        },
    };
}

static NSString *jsonString(NSDictionary *dict)
{
    NSData *data = [KSJSONCodec encode:dict options:KSJSONEncodeOptionNone error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSDictionary *dictFromCString(const char *json)
{
    NSData *data = [NSData dataWithBytes:json length:strlen(json)];
    return [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
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
    XCTAssertTrue(kscm_watchdog_stitchReport(NULL, 0, "/tmp/fake") == NULL);
}

- (void)testNullSidecarPathReturnsNull
{
    XCTAssertTrue(kscm_watchdog_stitchReport("{}", 0, NULL) == NULL);
}

- (void)testMissingSidecarFileReturnsNull
{
    char *result = kscm_watchdog_stitchReport("{}", 0, "/tmp/nonexistent.ksscr");
    XCTAssertTrue(result == NULL);
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

    NSDictionary *report = makeMinimalHangReport(500, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result == NULL);
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

    NSDictionary *report = makeMinimalHangReport(500, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result == NULL);
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

    NSDictionary *report = makeMinimalHangReport(500, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result == NULL);
}

#pragma mark - No Hang In Report

- (void)testReportWithoutHangReturnsNull
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
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result == NULL);
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

    NSDictionary *report = makeMinimalHangReport(100000000, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *hang = stitched[@"crash"][@"error"][@"hang"];
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

    NSDictionary *report = makeMinimalHangReport(1000, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *error = stitched[@"crash"][@"error"];
    XCTAssertEqualObjects(error[@"type"], @"signal");
    XCTAssertNotNil(error[@"signal"]);
    XCTAssertNotNil(error[@"mach"]);
    XCTAssertNotNil(error[@"exit_reason"]);
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

    NSDictionary *report = makeMinimalHangReport(1000, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *hang = stitched[@"crash"][@"error"][@"hang"];
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

    NSDictionary *report = makeMinimalHangReport(1000, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *hang = stitched[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_recovered"], @YES);
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

    NSDictionary *report = makeMinimalHangReport(1000, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSString *type = stitched[@"crash"][@"error"][@"type"];
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

    NSDictionary *report = makeMinimalHangReport(1000, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *error = stitched[@"crash"][@"error"];
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

    NSDictionary *report = makeMinimalHangReport(1000, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *hang = stitched[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_end_nanos"], @(endTs));
}

- (void)testRecoveredHangPreservesStartFields
{
    uint64_t startNanos = 42000000;
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 99000000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = true,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = makeMinimalHangReport(startNanos, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *hang = stitched[@"crash"][@"error"][@"hang"];
    XCTAssertEqualObjects(hang[@"hang_start_nanos"], @(startNanos));
    XCTAssertEqualObjects(hang[@"hang_start_role"], @"foreground");
}

#pragma mark - Invalid JSON

- (void)testInvalidJSONReturnsNull
{
    KSHangSidecar sc = {
        .magic = KSHANG_SIDECAR_MAGIC,
        .version = KSHANG_SIDECAR_VERSION_1_0,
        .endTimestamp = 1000,
        .endRole = TASK_DEFAULT_APPLICATION,
        .recovered = false,
    };
    NSString *path = writeSidecar(self.tempDir, sc);

    char *result = kscm_watchdog_stitchReport("not json at all", 1, path.UTF8String);
    XCTAssertTrue(result == NULL);
}

#pragma mark - Truncated Sidecar

- (void)testTruncatedSidecarReturnsNull
{
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"truncated.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    uint8_t partial[] = { 0x73, 0x68, 0x73, 0x6b };  // just magic bytes, incomplete
    write(fd, partial, sizeof(partial));
    close(fd);

    NSDictionary *report = makeMinimalHangReport(1000, @"foreground");
    NSString *json = jsonString(report);

    char *result = kscm_watchdog_stitchReport(json.UTF8String, 1, path.UTF8String);
    XCTAssertTrue(result == NULL);
}

@end
