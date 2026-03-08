//
//  KSCrashMonitor_ResourceStitch_Tests.m
//
//  Created by Alexander Cohen on 2026-03-04.
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

#import "KSCrashMonitor_Resource.h"
#import "KSCrashReportFields.h"
#import "KSJSONCodecObjC.h"

#include <fcntl.h>
#include <unistd.h>

// Stitch function declared in KSCrashMonitor_ResourceStitch.m
extern char *kscm_resource_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope,
                                        void *context);

#pragma mark - Helpers

static NSString *createTempDir(void)
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *writeResourceSidecar(NSString *dir, KSCrash_ResourceData data)
{
    NSString *path = [dir stringByAppendingPathComponent:@"Resource.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    NSCAssert(fd >= 0, @"Failed to open sidecar for writing: %s", path.UTF8String);
    ssize_t written = write(fd, &data, sizeof(data));
    NSCAssert(written == (ssize_t)sizeof(data), @"Short write to sidecar");
    close(fd);
    return path;
}

static KSCrash_ResourceData makeValidResourceData(void)
{
    KSCrash_ResourceData data = {};
    data.magic = KSRESOURCE_MAGIC;
    data.version = KSCrash_Resource_CurrentVersion;
    data.memoryPressure = 0;  // normal
    data.memoryLevel = 1;     // warn
    data.memoryFootprint = 50000000;
    data.memoryRemaining = 150000000;
    data.memoryLimit = 200000000;
    data.batteryLevel = 72;
    data.batteryState = 2;  // charging
    data.lowPowerMode = 0;
    data.cpuCoreCount = 6;
    data.cpuUsageUser = 350;    // 350 permil = 0.35 cores worth of user time
    data.cpuUsageSystem = 120;  // 120 permil = 0.12 cores worth of system time
    data.thermalState = 1;      // fair
    data.threadCount = 42;
    data.dataProtectionActive = 1;
    return data;
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

@interface KSCrashMonitor_ResourceStitch_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation KSCrashMonitor_ResourceStitch_Tests

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
    XCTAssertTrue(kscm_resource_stitchReport(NULL, "/tmp/fake", KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testNullSidecarPathReturnsNull
{
    XCTAssertTrue(kscm_resource_stitchReport("{}", NULL, KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testWrongScopeReturnsNull
{
    KSCrash_ResourceData data = makeValidResourceData();
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{ @"report" : @ {} });
    XCTAssertTrue(kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL) ==
                  NULL);
}

#pragma mark - Invalid Sidecar

- (void)testBadMagicReturnsNull
{
    KSCrash_ResourceData data = makeValidResourceData();
    data.magic = 0x12345678;
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{ @"report" : @ {} });
    XCTAssertTrue(kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testVersionZeroReturnsNull
{
    KSCrash_ResourceData data = makeValidResourceData();
    data.version = 0;
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{ @"report" : @ {} });
    XCTAssertTrue(kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testFutureVersionReturnsNull
{
    KSCrash_ResourceData data = makeValidResourceData();
    data.version = KSCrash_Resource_CurrentVersion + 1;
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{ @"report" : @ {} });
    XCTAssertTrue(kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testTruncatedSidecarReturnsNull
{
    // Write fewer bytes than sizeof(KSCrash_ResourceData)
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"Resource.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    XCTAssertTrue(fd >= 0);
    uint8_t partial[16] = {};
    write(fd, partial, sizeof(partial));
    close(fd);

    NSString *json = jsonString(@{ @"report" : @ {} });
    XCTAssertTrue(kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL) == NULL);
}

- (void)testMissingSidecarFileReturnsNull
{
    NSString *json = jsonString(@{ @"report" : @ {} });
    XCTAssertTrue(kscm_resource_stitchReport(json.UTF8String, "/tmp/nonexistent.ksscr", KSCrashSidecarScopeRun, NULL) ==
                  NULL);
}

#pragma mark - Invalid JSON

- (void)testMalformedJSONReturnsNull
{
    KSCrash_ResourceData data = makeValidResourceData();
    NSString *path = writeResourceSidecar(self.tempDir, data);
    XCTAssertTrue(kscm_resource_stitchReport("not json{{{", path.UTF8String, KSCrashSidecarScopeRun, NULL) == NULL);
}

#pragma mark - Valid Stitch

- (void)testStitchCreatesSystemDict
{
    KSCrash_ResourceData data = makeValidResourceData();
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{});

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertNotNil(stitched[KSCrashField_System]);
}

- (void)testStitchAppMemoryFields
{
    KSCrash_ResourceData data = makeValidResourceData();
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{});

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *appMemory = stitched[KSCrashField_System][KSCrashField_AppMemory];
    XCTAssertNotNil(appMemory);
    XCTAssertEqualObjects(appMemory[KSCrashField_MemoryFootprint], @(50000000));
    XCTAssertEqualObjects(appMemory[KSCrashField_MemoryRemaining], @(150000000));
    XCTAssertEqualObjects(appMemory[KSCrashField_MemoryLimit], @(200000000));
    XCTAssertEqualObjects(appMemory[KSCrashField_MemoryPressure], @"normal");
    XCTAssertEqualObjects(appMemory[KSCrashField_MemoryLevel], @"warn");
}

- (void)testStitchResourceFields
{
    KSCrash_ResourceData data = makeValidResourceData();
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{});

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertEqualObjects(system[KSCrashField_BatteryLevel], @(72));
    XCTAssertEqualObjects(system[KSCrashField_BatteryState], @(2));
    XCTAssertEqualObjects(system[KSCrashField_LowPowerModeEnabled], @NO);
    XCTAssertEqualObjects(system[KSCrashField_CPUCoreCount], @(6));
    XCTAssertEqualObjects(system[KSCrashField_CPUUsageUser], @(350));
    XCTAssertEqualObjects(system[KSCrashField_CPUUsageSystem], @(120));
    XCTAssertEqualObjects(system[KSCrashField_ThermalState], @(1));
    XCTAssertEqualObjects(system[KSCrashField_ThreadCount], @(42));
    XCTAssertEqualObjects(system[KSCrashField_DataProtectionActive], @YES);
}

- (void)testBatteryLevel255OmitsBatteryLevel
{
    KSCrash_ResourceData data = makeValidResourceData();
    data.batteryLevel = 255;
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{});

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertNil(system[KSCrashField_BatteryLevel]);
    // batteryState should still be present
    XCTAssertNotNil(system[KSCrashField_BatteryState]);
}

- (void)testDataProtectionInactive
{
    KSCrash_ResourceData data = makeValidResourceData();
    data.dataProtectionActive = 0;
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{});

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_System][KSCrashField_DataProtectionActive], @NO);
}

- (void)testLowPowerModeEnabled
{
    KSCrash_ResourceData data = makeValidResourceData();
    data.lowPowerMode = 1;
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{});

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_System][KSCrashField_LowPowerModeEnabled], @YES);
}

#pragma mark - Existing Data Preservation

- (void)testStitchPreservesExistingSystemFields
{
    KSCrash_ResourceData data = makeValidResourceData();
    NSString *path = writeResourceSidecar(self.tempDir, data);

    NSDictionary *existing = @{
        KSCrashField_System : @ {
            @"existing_field" : @"should_survive",
        }
    };
    NSString *json = jsonString(existing);

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertEqualObjects(system[@"existing_field"], @"should_survive");
    // Resource fields should also be present
    XCTAssertNotNil(system[KSCrashField_BatteryLevel]);
}

- (void)testStitchPreservesExistingAppMemoryFields
{
    KSCrash_ResourceData data = makeValidResourceData();
    NSString *path = writeResourceSidecar(self.tempDir, data);

    NSDictionary *existing = @{
        KSCrashField_System : @ {
            KSCrashField_AppMemory : @ {
                @"existing_memory_field" : @"should_survive",
            }
        }
    };
    NSString *json = jsonString(existing);

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *appMemory = stitched[KSCrashField_System][KSCrashField_AppMemory];
    XCTAssertEqualObjects(appMemory[@"existing_memory_field"], @"should_survive");
    // Resource memory fields should also be present
    XCTAssertNotNil(appMemory[KSCrashField_MemoryFootprint]);
}

- (void)testStitchPreservesNonSystemFields
{
    KSCrash_ResourceData data = makeValidResourceData();
    NSString *path = writeResourceSidecar(self.tempDir, data);

    NSDictionary *existing = @{
        @"crash" : @ { @"error" : @ { @"type" : @"mach" } },
    };
    NSString *json = jsonString(existing);

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[@"crash"][@"error"][@"type"], @"mach");
    XCTAssertNotNil(stitched[KSCrashField_System]);
}

#pragma mark - Edge Cases

- (void)testAllThermalStatesStitchCorrectly
{
    for (uint8_t state = 0; state <= 3; state++) {
        KSCrash_ResourceData data = makeValidResourceData();
        data.thermalState = state;
        NSString *path = writeResourceSidecar(self.tempDir, data);
        NSString *json = jsonString(@{});

        char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
        XCTAssertTrue(result != NULL);

        NSDictionary *stitched = dictFromCString(result);
        free(result);

        XCTAssertEqualObjects(stitched[KSCrashField_System][KSCrashField_ThermalState], @(state));
    }
}

- (void)testZeroCPUUsageStitchesCorrectly
{
    KSCrash_ResourceData data = makeValidResourceData();
    data.cpuUsageUser = 0;
    data.cpuUsageSystem = 0;
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{});

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_System][KSCrashField_CPUUsageUser], @(0));
    XCTAssertEqualObjects(stitched[KSCrashField_System][KSCrashField_CPUUsageSystem], @(0));
}

- (void)testHighCPUUsageStitchesCorrectly
{
    KSCrash_ResourceData data = makeValidResourceData();
    data.cpuUsageUser = 6000;    // 6 cores saturated
    data.cpuUsageSystem = 2000;  // 2 cores of kernel time
    NSString *path = writeResourceSidecar(self.tempDir, data);
    NSString *json = jsonString(@{});

    char *result = kscm_resource_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    XCTAssertEqualObjects(stitched[KSCrashField_System][KSCrashField_CPUUsageUser], @(6000));
    XCTAssertEqualObjects(stitched[KSCrashField_System][KSCrashField_CPUUsageSystem], @(2000));
}

@end
