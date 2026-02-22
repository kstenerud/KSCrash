//
//  KSCrashMonitor_System_Tests.m
//
//  Created by Alexander Cohen on 2026-02-16.
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

#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_System.h"
#import "KSCrashReportFields.h"
#import "KSFileUtils.h"
#import "KSJSONCodecObjC.h"
#import "KSSysCtl.h"
#import "KSSystemCapabilities.h"

#include <errno.h>
#include <fcntl.h>

static char g_sidecarPath[512];

static bool stubRunSidecarPath(const char *monitorId, char *pathBuffer, size_t pathBufferLength)
{
    if (g_sidecarPath[0] == '\0') {
        return false;
    }
    snprintf(pathBuffer, pathBufferLength, "%s/%s.ksscr", g_sidecarPath, monitorId);
    return true;
}

@interface KSCrashMonitor_System_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation KSCrashMonitor_System_Tests

- (void)setUp
{
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    strlcpy(g_sidecarPath, self.tempDir.fileSystemRepresentation, sizeof(g_sidecarPath));
}

- (void)tearDown
{
    KSCrashMonitorAPI *api = kscm_system_getAPI();
    api->setEnabled(false, NULL);

    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    g_sidecarPath[0] = '\0';
    [super tearDown];
}

- (void)testInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_system_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPath = stubRunSidecarPath };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testMmapStructPopulatedAtInit
{
    KSCrashMonitorAPI *api = kscm_system_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPath = stubRunSidecarPath };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    // Read the sidecar file back
    NSString *sidecarFile = [self.tempDir stringByAppendingPathComponent:@"System.ksscr"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:sidecarFile]);

    KSCrash_SystemData sc = {};
    int fd = open(sidecarFile.fileSystemRepresentation, O_RDONLY);
    XCTAssertNotEqual(fd, -1, @"Failed to open sidecar: %s", strerror(errno));
    XCTAssertTrue(ksfu_readBytesFromFD(fd, (char *)&sc, (int)sizeof(sc)));
    close(fd);

    XCTAssertEqual(sc.magic, KSSYS_MAGIC);
    XCTAssertEqual(sc.version, KSCrash_System_CurrentVersion);
    XCTAssertTrue(sc.processName[0] != '\0', @"processName should be populated");
    XCTAssertGreaterThan(sc.memorySize, 0ULL, @"memorySize should be non-zero");
    XCTAssertTrue(sc.cpuArchitecture[0] != '\0', @"cpuArchitecture should be populated");
    XCTAssertGreaterThan(sc.processID, 0, @"processID should be non-zero");

    api->setEnabled(false, NULL);
}

- (void)testOSVersionMatchesPlatform
{
    KSCrashMonitorAPI *api = kscm_system_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPath = stubRunSidecarPath };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    // Read the sidecar
    NSString *sidecarFile = [self.tempDir stringByAppendingPathComponent:@"System.ksscr"];
    KSCrash_SystemData sc = {};
    int fd = open(sidecarFile.fileSystemRepresentation, O_RDONLY);
    XCTAssertNotEqual(fd, -1);
    XCTAssertTrue(ksfu_readBytesFromFD(fd, (char *)&sc, (int)sizeof(sc)));
    close(fd);

    XCTAssertTrue(sc.osVersion[0] != '\0', @"osVersion should be populated");

#if TARGET_OS_SIMULATOR
    NSString *expected = [NSProcessInfo processInfo].environment[@"SIMULATOR_RUNTIME_BUILD_VERSION"];
    if (expected != nil) {
        XCTAssertEqualObjects(@(sc.osVersion), expected,
                              @"Simulator osVersion should match SIMULATOR_RUNTIME_BUILD_VERSION");
    }

    char kernBuild[256] = { 0 };
    int len = kssysctl_stringForName("kern.osversion", kernBuild, sizeof(kernBuild));
    if (len > 0 && expected != nil) {
        XCTAssertNotEqualObjects(@(sc.osVersion), @(kernBuild),
                                 @"Simulator osVersion should not be the host macOS build");
    }
#else
    char kernBuild[256] = { 0 };
    int len = kssysctl_stringForName("kern.osversion", kernBuild, sizeof(kernBuild));
    XCTAssertGreaterThan(len, 0);
    XCTAssertEqualObjects(@(sc.osVersion), @(kernBuild), @"osVersion should match kern.osversion on non-simulator");
#endif

    api->setEnabled(false, NULL);
}

- (void)testDynamicFieldsUpdated
{
    KSCrashMonitorAPI *api = kscm_system_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPath = stubRunSidecarPath };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    // Call addContextualInfoToEvent to trigger dynamic field update
    KSCrash_MonitorContext context = { 0 };
    api->addContextualInfoToEvent(&context, NULL);

    // Read the sidecar to check dynamic fields
    NSString *sidecarFile = [self.tempDir stringByAppendingPathComponent:@"System.ksscr"];
    KSCrash_SystemData sc = {};
    int fd = open(sidecarFile.fileSystemRepresentation, O_RDONLY);
    XCTAssertNotEqual(fd, -1);
    XCTAssertTrue(ksfu_readBytesFromFD(fd, (char *)&sc, (int)sizeof(sc)));
    close(fd);

    // freeMemory and usableMemory should be non-zero after update
    XCTAssertGreaterThan(sc.freeMemory, 0ULL, @"freeMemory should be populated after addContextualInfoToEvent");
    XCTAssertGreaterThan(sc.usableMemory, 0ULL, @"usableMemory should be populated after addContextualInfoToEvent");

    api->setEnabled(false, NULL);
}

- (void)testStitchProducesValidJSON
{
    KSCrashMonitorAPI *api = kscm_system_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPath = stubRunSidecarPath };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    // Update dynamic fields
    KSCrash_MonitorContext context = { 0 };
    api->addContextualInfoToEvent(&context, NULL);

    api->setEnabled(false, NULL);

    // Build a minimal report JSON
    NSDictionary *minimalReport = @{
        KSCrashField_System : @ {},
        KSCrashField_Report : @ { KSCrashField_ProcessName : @"placeholder" },
    };
    NSData *reportData = [KSJSONCodec encode:minimalReport options:KSJSONEncodeOptionNone error:nil];
    XCTAssertNotNil(reportData);

    NSString *reportStr = [[NSString alloc] initWithData:reportData encoding:NSUTF8StringEncoding];
    NSString *sidecarFile = [self.tempDir stringByAppendingPathComponent:@"System.ksscr"];

    char *result =
        api->stitchReport(reportStr.UTF8String, sidecarFile.fileSystemRepresentation, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result != NULL, @"stitchReport should return non-NULL");

    // Decode the stitched result
    NSData *stitchedData = [NSData dataWithBytesNoCopy:result length:strlen(result) freeWhenDone:YES];
    NSDictionary *stitched = [KSJSONCodec decode:stitchedData options:KSJSONDecodeOptionNone error:nil];
    XCTAssertTrue([stitched isKindOfClass:[NSDictionary class]]);

    NSDictionary *system = stitched[KSCrashField_System];
    XCTAssertTrue([system isKindOfClass:[NSDictionary class]]);
    XCTAssertNotNil(system[KSCrashField_Machine], @"machine should be populated");
    XCTAssertNotNil(system[KSCrashField_ProcessName], @"processName should be populated");
    XCTAssertNotNil(system[KSCrashField_CPUArch], @"cpuArchitecture should be populated");

    NSDictionary *memory = system[KSCrashField_Memory];
    XCTAssertTrue([memory isKindOfClass:[NSDictionary class]]);
    XCTAssertNotNil(memory[KSCrashField_Size], @"memorySize should be populated");
    XCTAssertNotNil(memory[KSCrashField_Free], @"freeMemory should be populated");
    XCTAssertNotNil(memory[KSCrashField_Usable], @"usableMemory should be populated");

    // processName should also be in report.report
    NSDictionary *reportInfo = stitched[KSCrashField_Report];
    XCTAssertNotNil(reportInfo[KSCrashField_ProcessName], @"processName should be stitched into report info");
}

- (void)testStitchRejectsInvalidMagic
{
    KSCrashMonitorAPI *api = kscm_system_getAPI();

    // Write a sidecar with bad magic
    NSString *sidecarFile = [self.tempDir stringByAppendingPathComponent:@"System.ksscr"];
    KSCrash_SystemData sc = {};
    sc.magic = (int32_t)0xDEADBEEF;
    sc.version = KSCrash_System_CurrentVersion;
    NSData *data = [NSData dataWithBytes:&sc length:sizeof(sc)];
    [data writeToFile:sidecarFile atomically:YES];

    NSDictionary *minimalReport = @{ KSCrashField_System : @ {} };
    NSData *reportData = [KSJSONCodec encode:minimalReport options:KSJSONEncodeOptionNone error:nil];
    NSString *reportStr = [[NSString alloc] initWithData:reportData encoding:NSUTF8StringEncoding];

    char *result =
        api->stitchReport(reportStr.UTF8String, sidecarFile.fileSystemRepresentation, KSCrashSidecarScopeRun, NULL);
    XCTAssertTrue(result == NULL, @"stitchReport should return NULL for invalid magic");
}

@end
