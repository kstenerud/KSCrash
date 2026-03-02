//
//  KSCrashMonitor_LifecycleStitch_Tests.m
//
//  Created by Alexander Cohen on 2026-02-28.
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

#import "KSCrashMonitor_Lifecycle.h"
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

static NSString *writeLifecycleSidecar(NSString *dir, KSCrash_LifecycleData lc)
{
    NSString *path = [dir stringByAppendingPathComponent:@"lifecycle.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    NSCAssert(fd >= 0, @"Failed to open sidecar for writing: %s", path.UTF8String);
    ssize_t written = write(fd, &lc, sizeof(lc));
    NSCAssert(written == (ssize_t)sizeof(lc), @"Short write to sidecar");
    close(fd);
    return path;
}

static KSCrash_LifecycleData makeValidLifecycleData(void)
{
    KSCrash_LifecycleData lc = {};
    lc.magic = KSLIFECYCLE_MAGIC;
    lc.version = KSCrash_Lifecycle_CurrentVersion;
    lc.applicationIsActive = 1;
    lc.applicationIsInForeground = 1;
    lc.launchesSinceLastCrash = 5;
    lc.sessionsSinceLastCrash = 10;
    lc.sessionsSinceLaunch = 3;
    lc.activeDurationSinceLaunchNs = 60000000000ULL;         // 60 seconds
    lc.backgroundDurationSinceLaunchNs = 30000000000ULL;     // 30 seconds
    lc.activeDurationSinceLastCrashNs = 120000000000ULL;     // 120 seconds
    lc.backgroundDurationSinceLastCrashNs = 45000000000ULL;  // 45 seconds
    return lc;
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

@interface KSCrashMonitor_LifecycleStitch_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation KSCrashMonitor_LifecycleStitch_Tests

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
    XCTAssertTrue(kscm_lifecycle_stitchReport(NULL, "/tmp/fake", KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testNullSidecarPathReturnsNull
{
    XCTAssertTrue(kscm_lifecycle_stitchReport("{}", NULL, KSCrashSidecarScopeRun, NULL) == NULL);
}

#pragma mark - Wrong Scope

- (void)testReportScopeReturnsNull
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    // Lifecycle is run-scope only; report scope should return NULL
    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result == NULL);
}

#pragma mark - Invalid Sidecar

- (void)testBadMagicReturnsNull
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    lc.magic = (int32_t)0xDEADBEEF;
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL);
}

- (void)testVersionZeroReturnsNull
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    lc.version = 0;
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL);
}

- (void)testFutureVersionReturnsNull
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    lc.version = KSCrash_Lifecycle_CurrentVersion + 1;
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL);
}

- (void)testTruncatedSidecarReturnsNull
{
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"truncated.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    uint8_t partial[] = { 0x63, 0x6C, 0x73, 0x6B };  // just magic bytes, incomplete
    write(fd, partial, sizeof(partial));
    close(fd);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL);
}

#pragma mark - Invalid JSON

- (void)testInvalidJSONReturnsNull
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    char *result = kscm_lifecycle_stitchReport("not json at all", path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL);
}

#pragma mark - Valid Stitch — All Stats

- (void)testAllStatsPopulated
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *stats = stitched[KSCrashField_System][KSCrashField_AppStats];
    XCTAssertNotNil(stats);
    XCTAssertEqualObjects(stats[KSCrashField_AppActive], @YES);
    XCTAssertEqualObjects(stats[KSCrashField_AppInFG], @YES);
    XCTAssertEqualObjects(stats[KSCrashField_LaunchesSinceCrash], @(5));
    XCTAssertEqualObjects(stats[KSCrashField_SessionsSinceCrash], @(10));
    XCTAssertEqualObjects(stats[KSCrashField_SessionsSinceLaunch], @(3));
}

#pragma mark - Valid Stitch — Durations

- (void)testDurationsConvertedToSeconds
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    lc.activeDurationSinceLaunchNs = 60000000000ULL;         // 60s
    lc.backgroundDurationSinceLaunchNs = 30000000000ULL;     // 30s
    lc.activeDurationSinceLastCrashNs = 120000000000ULL;     // 120s
    lc.backgroundDurationSinceLastCrashNs = 45000000000ULL;  // 45s
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *stats = stitched[KSCrashField_System][KSCrashField_AppStats];
    XCTAssertEqualWithAccuracy([stats[KSCrashField_ActiveTimeSinceLaunch] doubleValue], 60.0, 0.001);
    XCTAssertEqualWithAccuracy([stats[KSCrashField_BGTimeSinceLaunch] doubleValue], 30.0, 0.001);
    XCTAssertEqualWithAccuracy([stats[KSCrashField_ActiveTimeSinceCrash] doubleValue], 120.0, 0.001);
    XCTAssertEqualWithAccuracy([stats[KSCrashField_BGTimeSinceCrash] doubleValue], 45.0, 0.001);
}

- (void)testZeroDurationsAreZeroSeconds
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    lc.activeDurationSinceLaunchNs = 0;
    lc.backgroundDurationSinceLaunchNs = 0;
    lc.activeDurationSinceLastCrashNs = 0;
    lc.backgroundDurationSinceLastCrashNs = 0;
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *stats = stitched[KSCrashField_System][KSCrashField_AppStats];
    XCTAssertEqualWithAccuracy([stats[KSCrashField_ActiveTimeSinceLaunch] doubleValue], 0.0, 0.001);
    XCTAssertEqualWithAccuracy([stats[KSCrashField_BGTimeSinceLaunch] doubleValue], 0.0, 0.001);
    XCTAssertEqualWithAccuracy([stats[KSCrashField_ActiveTimeSinceCrash] doubleValue], 0.0, 0.001);
    XCTAssertEqualWithAccuracy([stats[KSCrashField_BGTimeSinceCrash] doubleValue], 0.0, 0.001);
}

#pragma mark - Stats Placed in Correct Path

- (void)testStatsPlacedUnderSystemAppStats
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    // Must be at report.system.application_stats
    XCTAssertNotNil(stitched[KSCrashField_System]);
    XCTAssertNotNil(stitched[KSCrashField_System][KSCrashField_AppStats]);
    XCTAssertTrue([stitched[KSCrashField_System][KSCrashField_AppStats] isKindOfClass:[NSDictionary class]]);
}

#pragma mark - Existing System Dict Preserved

- (void)testExistingSystemFieldsPreserved
{
    KSCrash_LifecycleData lc = makeValidLifecycleData();
    NSString *path = writeLifecycleSidecar(self.tempDir, lc);

    NSDictionary *report = @{
        KSCrashField_System : @ {
            @"custom_field" : @"custom_value",
            KSCrashField_SystemName : @"iOS",
        }
    };
    NSString *json = jsonString(report);

    char *result = kscm_lifecycle_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertEqualObjects(system[@"custom_field"], @"custom_value");
    XCTAssertEqualObjects(system[KSCrashField_SystemName], @"iOS");
    // Also verify stats were added
    XCTAssertNotNil(system[KSCrashField_AppStats]);
}

@end
