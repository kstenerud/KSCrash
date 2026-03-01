//
//  KSCrashMonitor_SystemStitch_Tests.m
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

#import "KSCrashMonitor_System.h"
#import "KSCrashReportFields.h"
#import "KSJSONCodecObjC.h"

#include <fcntl.h>
#include <unistd.h>

// Forward-declare: not exposed in the header
char *kscm_system_stitchReport(const char *report, const char *sidecarPath, KSCrashSidecarScope scope, void *context);

#pragma mark - Helpers

static NSString *createTempDir(void)
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *writeSidecar(NSString *dir, KSCrash_SystemData sc)
{
    NSString *path = [dir stringByAppendingPathComponent:@"system.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    write(fd, &sc, sizeof(sc));
    close(fd);
    return path;
}

static KSCrash_SystemData makeValidSystemData(void)
{
    KSCrash_SystemData sc = {};
    sc.magic = KSSYS_MAGIC;
    sc.version = KSCrash_System_CurrentVersion;
    strlcpy(sc.systemName, "iOS", sizeof(sc.systemName));
    strlcpy(sc.systemVersion, "17.2", sizeof(sc.systemVersion));
    strlcpy(sc.machine, "iPhone15,2", sizeof(sc.machine));
    strlcpy(sc.model, "D73AP", sizeof(sc.model));
    strlcpy(sc.kernelVersion, "Darwin 23.2.0", sizeof(sc.kernelVersion));
    strlcpy(sc.osVersion, "21C62", sizeof(sc.osVersion));
    sc.isJailbroken = 0;
    sc.procTranslated = 1;
    sc.appStartTimestamp = 1700000000;
    strlcpy(sc.executablePath, "/var/containers/Bundle/App/MyApp", sizeof(sc.executablePath));
    strlcpy(sc.executableName, "MyApp", sizeof(sc.executableName));
    strlcpy(sc.bundleID, "com.example.myapp", sizeof(sc.bundleID));
    strlcpy(sc.bundleName, "MyApp", sizeof(sc.bundleName));
    strlcpy(sc.bundleVersion, "42", sizeof(sc.bundleVersion));
    strlcpy(sc.bundleShortVersion, "1.2.3", sizeof(sc.bundleShortVersion));
    strlcpy(sc.appID, "ABCDEF-1234", sizeof(sc.appID));
    strlcpy(sc.cpuArchitecture, "arm64e", sizeof(sc.cpuArchitecture));
    strlcpy(sc.binaryArchitecture, "arm64", sizeof(sc.binaryArchitecture));
    strlcpy(sc.clangVersion, "15.0.0", sizeof(sc.clangVersion));
    sc.cpuType = 16777228;
    sc.cpuSubType = 2;
    sc.binaryCPUType = 16777228;
    sc.binaryCPUSubType = 0;
    strlcpy(sc.timezone, "America/New_York", sizeof(sc.timezone));
    strlcpy(sc.processName, "MyApp", sizeof(sc.processName));
    sc.processID = 12345;
    sc.parentProcessID = 1;
    strlcpy(sc.deviceAppHash, "abc123def456", sizeof(sc.deviceAppHash));
    strlcpy(sc.buildType, "debug", sizeof(sc.buildType));
    sc.memorySize = 6442450944ULL;
    sc.bootTimestamp = 1699900000;
    sc.storageSize = 256000000000ULL;
    sc.freeStorageSize = 128000000000ULL;
    sc.freeMemory = 2000000000ULL;
    sc.usableMemory = 4000000000ULL;
    return sc;
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

@interface KSCrashMonitor_SystemStitch_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation KSCrashMonitor_SystemStitch_Tests

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
    XCTAssertTrue(kscm_system_stitchReport(NULL, "/tmp/fake", KSCrashSidecarScopeReport, NULL) == NULL);
}

- (void)testNullSidecarPathReturnsNull
{
    XCTAssertTrue(kscm_system_stitchReport("{}", NULL, KSCrashSidecarScopeReport, NULL) == NULL);
}

- (void)testMissingSidecarFileReturnsNull
{
    char *result = kscm_system_stitchReport("{}", "/tmp/nonexistent.ksscr", KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result == NULL);
}

#pragma mark - Invalid Sidecar

- (void)testBadMagicReturnsNull
{
    KSCrash_SystemData sc = makeValidSystemData();
    sc.magic = (int32_t)0xDEADBEEF;
    NSString *path = writeSidecar(self.tempDir, sc);

    char *result = kscm_system_stitchReport("{}", path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result == NULL);
}

- (void)testVersionZeroReturnsNull
{
    KSCrash_SystemData sc = makeValidSystemData();
    sc.version = 0;
    NSString *path = writeSidecar(self.tempDir, sc);

    char *result = kscm_system_stitchReport("{}", path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result == NULL);
}

- (void)testFutureVersionReturnsNull
{
    KSCrash_SystemData sc = makeValidSystemData();
    sc.version = KSCrash_System_CurrentVersion + 1;
    NSString *path = writeSidecar(self.tempDir, sc);

    char *result = kscm_system_stitchReport("{}", path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result == NULL);
}

- (void)testTruncatedSidecarReturnsNull
{
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"truncated.ksscr"];
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    uint8_t partial[] = { 0x73, 0x79, 0x73, 0x6B };  // just a few bytes
    write(fd, partial, sizeof(partial));
    close(fd);

    char *result = kscm_system_stitchReport("{}", path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result == NULL);
}

#pragma mark - Invalid JSON

- (void)testInvalidJSONReturnsNull
{
    KSCrash_SystemData sc = makeValidSystemData();
    NSString *path = writeSidecar(self.tempDir, sc);

    char *result = kscm_system_stitchReport("not json at all", path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result == NULL);
}

#pragma mark - Valid Stitch — String Fields

- (void)testStringFieldsPopulated
{
    KSCrash_SystemData sc = makeValidSystemData();
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertEqualObjects(system[KSCrashField_SystemName], @"iOS");
    XCTAssertEqualObjects(system[KSCrashField_SystemVersion], @"17.2");
    XCTAssertEqualObjects(system[KSCrashField_Machine], @"iPhone15,2");
    XCTAssertEqualObjects(system[KSCrashField_Model], @"D73AP");
    XCTAssertEqualObjects(system[KSCrashField_KernelVersion], @"Darwin 23.2.0");
    XCTAssertEqualObjects(system[KSCrashField_OSVersion], @"21C62");
    XCTAssertEqualObjects(system[KSCrashField_BundleID], @"com.example.myapp");
    XCTAssertEqualObjects(system[KSCrashField_CPUArch], @"arm64e");
    XCTAssertEqualObjects(system[KSCrashField_BinaryArch], @"arm64");
    XCTAssertEqualObjects(system[KSCrashField_ClangVersion], @"15.0.0");
    XCTAssertEqualObjects(system[KSCrashField_TimeZone], @"America/New_York");
    XCTAssertEqualObjects(system[KSCrashField_DeviceAppHash], @"abc123def456");
    XCTAssertEqualObjects(system[KSCrashField_BuildType], @"debug");
    XCTAssertEqualObjects(system[KSCrashField_ProcessName], @"MyApp");
    XCTAssertEqualObjects(system[KSCrashField_ExecutablePath], @"/var/containers/Bundle/App/MyApp");
    XCTAssertEqualObjects(system[KSCrashField_Executable], @"MyApp");
    XCTAssertEqualObjects(system[KSCrashField_BundleName], @"MyApp");
    XCTAssertEqualObjects(system[KSCrashField_BundleVersion], @"42");
    XCTAssertEqualObjects(system[KSCrashField_BundleShortVersion], @"1.2.3");
    XCTAssertEqualObjects(system[KSCrashField_AppUUID], @"ABCDEF-1234");
}

#pragma mark - Valid Stitch — Numeric Fields

- (void)testNumericFieldsPopulated
{
    KSCrash_SystemData sc = makeValidSystemData();
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertEqualObjects(system[KSCrashField_CPUType], @(16777228));
    XCTAssertEqualObjects(system[KSCrashField_CPUSubType], @(2));
    XCTAssertEqualObjects(system[KSCrashField_BinaryCPUType], @(16777228));
    XCTAssertEqualObjects(system[KSCrashField_BinaryCPUSubType], @(0));
    XCTAssertEqualObjects(system[KSCrashField_ProcessID], @(12345));
    XCTAssertEqualObjects(system[KSCrashField_ParentProcessID], @(1));
}

#pragma mark - Valid Stitch — Booleans

- (void)testBooleanFieldsPopulated
{
    KSCrash_SystemData sc = makeValidSystemData();
    sc.isJailbroken = 0;
    sc.procTranslated = 1;
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertEqualObjects(system[KSCrashField_Jailbroken], @NO);
    XCTAssertEqualObjects(system[KSCrashField_ProcTranslated], @YES);
}

#pragma mark - Valid Stitch — Timestamps

- (void)testTimestampFieldsPopulated
{
    KSCrash_SystemData sc = makeValidSystemData();
    sc.appStartTimestamp = 1700000000;
    sc.bootTimestamp = 1699900000;
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    // Timestamps should be non-nil ISO 8601 strings
    XCTAssertNotNil(system[KSCrashField_AppStartTime]);
    XCTAssertTrue([system[KSCrashField_AppStartTime] isKindOfClass:[NSString class]]);
    XCTAssertNotNil(system[KSCrashField_BootTime]);
    XCTAssertTrue([system[KSCrashField_BootTime] isKindOfClass:[NSString class]]);
}

- (void)testZeroTimestampNotWritten
{
    KSCrash_SystemData sc = makeValidSystemData();
    sc.appStartTimestamp = 0;
    sc.bootTimestamp = 0;
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertNil(system[KSCrashField_AppStartTime]);
    XCTAssertNil(system[KSCrashField_BootTime]);
}

#pragma mark - Valid Stitch — Memory Sub-Object

- (void)testMemorySubObjectPopulated
{
    KSCrash_SystemData sc = makeValidSystemData();
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *memory = stitched[KSCrashField_System][KSCrashField_Memory];
    XCTAssertNotNil(memory);
    XCTAssertEqualObjects(memory[KSCrashField_Size], @(6442450944ULL));
    XCTAssertEqualObjects(memory[KSCrashField_Free], @(2000000000ULL));
    XCTAssertEqualObjects(memory[KSCrashField_Usable], @(4000000000ULL));
}

#pragma mark - Valid Stitch — Storage

- (void)testStorageFieldsPopulated
{
    KSCrash_SystemData sc = makeValidSystemData();
    sc.storageSize = 256000000000ULL;
    sc.freeStorageSize = 128000000000ULL;
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertEqualObjects(system[KSCrashField_Storage], @(256000000000ULL));
    XCTAssertEqualObjects(system[KSCrashField_FreeStorage], @(128000000000ULL));
}

- (void)testStorageZeroNotWritten
{
    KSCrash_SystemData sc = makeValidSystemData();
    sc.storageSize = 0;
    sc.freeStorageSize = 0;
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertNil(system[KSCrashField_Storage]);
    XCTAssertNil(system[KSCrashField_FreeStorage]);
}

#pragma mark - Empty Strings Skipped

- (void)testEmptyStringsSkipped
{
    KSCrash_SystemData sc = {};
    sc.magic = KSSYS_MAGIC;
    sc.version = KSCrash_System_CurrentVersion;
    // All string fields are zero-initialized (empty)
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertNil(system[KSCrashField_SystemName]);
    XCTAssertNil(system[KSCrashField_Machine]);
    XCTAssertNil(system[KSCrashField_Model]);
    XCTAssertNil(system[KSCrashField_BundleID]);
    XCTAssertNil(system[KSCrashField_CPUArch]);
    XCTAssertNil(system[KSCrashField_ProcessName]);
}

#pragma mark - ProcessName Propagation

- (void)testProcessNamePropagatedToReportInfo
{
    KSCrash_SystemData sc = makeValidSystemData();
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{ KSCrashField_Report : @ { @"id" : @"test-id" } };
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSString *processName = stitched[KSCrashField_Report][KSCrashField_ProcessName];
    XCTAssertEqualObjects(processName, @"MyApp");
}

- (void)testProcessNameNotPropagatedWhenReportInfoMissing
{
    KSCrash_SystemData sc = makeValidSystemData();
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{};
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    // No report section should be created just for process_name
    XCTAssertNil(stitched[KSCrashField_Report]);
}

#pragma mark - Existing System Dict Preserved

- (void)testExistingSystemFieldsPreserved
{
    KSCrash_SystemData sc = makeValidSystemData();
    NSString *path = writeSidecar(self.tempDir, sc);

    NSDictionary *report = @{
        KSCrashField_System : @ {
            @"custom_field" : @"custom_value",
        }
    };
    NSString *json = jsonString(report);

    char *result = kscm_system_stitchReport(json.UTF8String, path.UTF8String, KSCrashSidecarScopeReport, NULL);
    XCTAssertTrue(result != NULL);

    NSDictionary *stitched = dictFromCString(result);
    free(result);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertEqualObjects(system[@"custom_field"], @"custom_value");
    // Also verify new fields were added
    XCTAssertEqualObjects(system[KSCrashField_SystemName], @"iOS");
}

@end
