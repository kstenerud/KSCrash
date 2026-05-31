//
//  KSCrashReportStoreC_RunSidecar_Tests.m
//
//  Created by Alexander Cohen on 2026-02-19.
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

#import "FileBasedTestCase.h"

#import "KSCrashMonitor.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportStoreC+Private.h"
#import "KSCrashReportStoreC.h"
#import "KSJSONCodecObjC.h"

#include <inttypes.h>

#pragma mark - Test monitor stitch callback

static const char *testMonitorId(__unused void *context) { return "TestStitchMonitor"; }

// Reads the sidecar file as UTF-8 text and inserts it under "test_stitch" in the report.
static CFDictionaryRef testStitchReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                        __unused KSCrashSidecarScope scope, __unused void *context)
{
    @autoreleasepool {
        NSDictionary *decoded = (__bridge NSDictionary *)reportDict;
        if (![decoded isKindOfClass:[NSDictionary class]]) {
            return NULL;
        }
        NSString *sidecarContent = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:sidecarPath]
                                                             encoding:NSUTF8StringEncoding
                                                                error:nil];
        if (sidecarContent == nil) {
            return NULL;
        }
        NSMutableDictionary *dict = [decoded mutableCopy];
        dict[@"test_stitch"] = sidecarContent;
        return (__bridge_retained CFDictionaryRef)dict;
    }
}

@interface KSCrashReportStoreC_RunSidecar_Tests : FileBasedTestCase
@end

@implementation KSCrashReportStoreC_RunSidecar_Tests {
    KSCrashReportStoreCConfiguration _storeConfig;
}

- (void)setUp
{
    [super setUp];
    memset(&_storeConfig, 0, sizeof(_storeConfig));
}

- (void)tearDown
{
    kscrs_setStitchConfig(NULL);
    [super tearDown];
}

- (void)prepareStoreWithRunSidecars:(NSString *)name
{
    NSString *reportsPath = [self.tempPath stringByAppendingPathComponent:name];
    NSString *sidecarsPath = [self.tempPath stringByAppendingPathComponent:@"Sidecars"];
    NSString *runSidecarsPath = [self.tempPath stringByAppendingPathComponent:@"RunSidecars"];
    _storeConfig.appName = "testapp";
    _storeConfig.reportsPath = reportsPath.UTF8String;
    _storeConfig.reportSidecarsPath = sidecarsPath.UTF8String;
    _storeConfig.runSidecarsPath = runSidecarsPath.UTF8String;
    _storeConfig.maxReportCount = 10;
    kscrs_initialize(&_storeConfig);
    kscrs_setStitchConfig(&_storeConfig);
}

- (int64_t)writeReportWithRunId:(NSString *)runId
{
    NSString *json = [NSString stringWithFormat:@"{\"report\":{\"run_id\":\"%@\",\"id\":\"evt1\"}}", runId];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    return kscrs_addUserReport(data.bytes, (int)data.length, &_storeConfig);
}

- (void)writeRunSidecar:(NSString *)monitorId runId:(NSString *)runId contents:(NSString *)contents
{
    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    [[NSFileManager defaultManager] createDirectoryAtPath:runDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *path = [runDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.ksscr", monitorId]];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - kscrs_getRunSidecarFilePath
// Note: tests requiring a valid run ID (path format, directory creation) need
// kscrash_install() which is too heavy for unit tests. We test those paths
// indirectly via the cleanup tests that write run sidecar files manually.

- (void)testGetRunSidecarFilePathNullMonitorId
{
    [self prepareStoreWithRunSidecars:@"testRunSidecarNullMon"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getRunSidecarFilePath(NULL, pathBuffer, sizeof(pathBuffer), &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetRunSidecarFilePathNullBuffer
{
    [self prepareStoreWithRunSidecars:@"testRunSidecarNullBuf"];
    bool result = kscrs_getRunSidecarFilePath("Mon", NULL, 100, &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetRunSidecarFilePathZeroBufferLength
{
    [self prepareStoreWithRunSidecars:@"testRunSidecarZeroBuf"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getRunSidecarFilePath("Mon", pathBuffer, 0, &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetRunSidecarFilePathNullRunSidecarsPath
{
    [self prepareStoreWithRunSidecars:@"testRunSidecarNoPath"];
    _storeConfig.runSidecarsPath = NULL;
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getRunSidecarFilePath("Mon", pathBuffer, sizeof(pathBuffer), &_storeConfig);
    XCTAssertFalse(result);
}

#pragma mark - Run Sidecar Directory Lifecycle

- (void)testRunSidecarsDirectoryCreatedOnInitialize
{
    [self prepareStoreWithRunSidecars:@"testRunSidecarsInit"];
    BOOL isDir = NO;
    BOOL exists =
        [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:_storeConfig.runSidecarsPath]
                                             isDirectory:&isDir];
    XCTAssertTrue(exists);
    XCTAssertTrue(isDir);
}

- (void)testDeleteAllReportsCleansRunSidecars
{
    [self prepareStoreWithRunSidecars:@"testDeleteAllRunSidecars"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"System" runId:runId contents:@"system data"];

    kscrs_deleteAllReports(&_storeConfig);

    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), 0);
    NSString *runSidecarsDir = [NSString stringWithUTF8String:_storeConfig.runSidecarsPath];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:runSidecarsDir error:nil];
    XCTAssertEqual(contents.count, 0u);
}

#pragma mark - Run Sidecar Orphan Cleanup

- (void)testInitializationCleansOrphanedRunSidecars
{
    [self prepareStoreWithRunSidecars:@"testOrphanCleanup"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"System" runId:runId contents:@"system data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);

    // Delete the report, leaving the run sidecar orphaned
    kscrs_deleteReportWithID(reportID, &_storeConfig);
    // Orphan still exists after deletion (cleanup is deferred)
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);

    // Cleanup orphans — orphan should be removed
    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:runDir]);
}

- (void)testInitializationKeepsRunSidecarsWithMatchingReports
{
    [self prepareStoreWithRunSidecars:@"testKeepRunSidecars"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"System" runId:runId contents:@"system data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);

    // Cleanup orphans — run sidecar should survive since report still exists
    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);
}

- (void)testInitializationCleansOnlyOrphanedRunSidecars
{
    [self prepareStoreWithRunSidecars:@"testSelectiveCleanup"];
    NSString *activeRunId = [[NSUUID UUID] UUIDString];
    NSString *orphanRunId = [[NSUUID UUID] UUIDString];

    [self writeReportWithRunId:activeRunId];
    [self writeRunSidecar:@"System" runId:activeRunId contents:@"active data"];
    [self writeRunSidecar:@"System" runId:orphanRunId contents:@"orphan data"];

    NSString *activeDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:activeRunId];
    NSString *orphanDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:orphanRunId];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:activeDir]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:orphanDir]);

    // Cleanup orphans — only orphan should be removed
    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:activeDir]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:orphanDir]);
}

// Regression: cleanup used to enumerate reports into a fixed 512-slot buffer, so
// with more reports than that the unenumerated tail had its still-referenced run
// sidecars deleted as orphans. Every sidecar with a matching report must survive.
- (void)testCleanupKeepsRunSidecarsBeyondFixedReportCap
{
    [self prepareStoreWithRunSidecars:@"testCleanupBeyondCap"];

    const int reportCount = 600;  // comfortably over the old 512 cap
    NSMutableArray<NSString *> *runDirs = [NSMutableArray arrayWithCapacity:reportCount];
    for (int i = 0; i < reportCount; i++) {
        NSString *runId = [[NSUUID UUID] UUIDString];
        [self writeReportWithRunId:runId];
        [self writeRunSidecar:@"System" runId:runId contents:@"system data"];
        [runDirs addObject:[[NSString stringWithUTF8String:_storeConfig.runSidecarsPath]
                               stringByAppendingPathComponent:runId]];
    }

    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *runDir in runDirs) {
        XCTAssertTrue([fm fileExistsAtPath:runDir], @"Run sidecar wrongly deleted: %@", runDir);
    }
}

- (void)testDeleteReportWithNoRunSidecarsPathDoesNotCrash
{
    [self prepareStoreWithRunSidecars:@"testDeleteNoRunSidecars"];
    _storeConfig.runSidecarsPath = NULL;
    int64_t reportID = [self writeReportWithRunId:[[NSUUID UUID] UUIDString]];
    kscrs_deleteReportWithID(reportID, &_storeConfig);
    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), 0);
}

- (void)testDeleteAllReportsWithNoRunSidecarsPathDoesNotCrash
{
    [self prepareStoreWithRunSidecars:@"testDeleteAllNoRunSidecars"];
    [self writeReportWithRunId:[[NSUUID UUID] UUIDString]];
    _storeConfig.runSidecarsPath = NULL;
    kscrs_deleteAllReports(&_storeConfig);
    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), 0);
}

#pragma mark - Run Sidecar Stitching Integration

- (KSCrashMonitorAPI)makeTestStitchMonitorAPI
{
    KSCrashMonitorAPI api = {};
    kscma_initAPI(&api);
    api.monitorId = testMonitorId;
    api.createStitchedReport = testStitchReport;
    return api;
}

- (void)testRunSidecarStitchedIntoReportOnRead
{
    [self prepareStoreWithRunSidecars:@"testStitchOnRead"];

    KSCrashMonitorAPI api = [self makeTestStitchMonitorAPI];
    kscm_addMonitor(&api);

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"TestStitchMonitor" runId:runId contents:@"hello from sidecar"];

    char *rawReport = kscrs_readReport(reportID, &_storeConfig);
    XCTAssertTrue(rawReport != NULL);

    NSData *data = [NSData dataWithBytesNoCopy:rawReport length:strlen(rawReport) freeWhenDone:YES];
    NSDictionary *decoded = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
    XCTAssertEqualObjects(decoded[@"test_stitch"], @"hello from sidecar");

    kscm_removeMonitor(&api);
}

- (void)testRunSidecarNotStitchedWhenNoMatchingSidecar
{
    [self prepareStoreWithRunSidecars:@"testNoStitchNoSidecar"];

    KSCrashMonitorAPI api = [self makeTestStitchMonitorAPI];
    kscm_addMonitor(&api);

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    // No run sidecar written

    char *rawReport = kscrs_readReport(reportID, &_storeConfig);
    XCTAssertTrue(rawReport != NULL);

    NSData *data = [NSData dataWithBytesNoCopy:rawReport length:strlen(rawReport) freeWhenDone:YES];
    NSDictionary *decoded = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
    XCTAssertNil(decoded[@"test_stitch"]);

    kscm_removeMonitor(&api);
}

- (void)testRunSidecarNotStitchedWithoutRegisteredMonitor
{
    [self prepareStoreWithRunSidecars:@"testNoStitchNoMonitor"];

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    // Write a sidecar for a monitor that isn't registered
    [self writeRunSidecar:@"UnknownMonitor" runId:runId contents:@"should be ignored"];

    char *rawReport = kscrs_readReport(reportID, &_storeConfig);
    XCTAssertTrue(rawReport != NULL);

    NSData *data = [NSData dataWithBytesNoCopy:rawReport length:strlen(rawReport) freeWhenDone:YES];
    NSDictionary *decoded = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
    XCTAssertNil(decoded[@"test_stitch"]);
}

- (void)testRunSidecarStitchedForMultipleReportsWithSameRunId
{
    [self prepareStoreWithRunSidecars:@"testStitchMultiple"];

    KSCrashMonitorAPI api = [self makeTestStitchMonitorAPI];
    kscm_addMonitor(&api);

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID1 = [self writeReportWithRunId:runId];
    int64_t reportID2 = [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"TestStitchMonitor" runId:runId contents:@"shared data"];

    // Both reports should get the same stitched data
    char *raw1 = kscrs_readReport(reportID1, &_storeConfig);
    char *raw2 = kscrs_readReport(reportID2, &_storeConfig);
    XCTAssertTrue(raw1 != NULL);
    XCTAssertTrue(raw2 != NULL);

    NSData *data1 = [NSData dataWithBytesNoCopy:raw1 length:strlen(raw1) freeWhenDone:YES];
    NSData *data2 = [NSData dataWithBytesNoCopy:raw2 length:strlen(raw2) freeWhenDone:YES];
    NSDictionary *decoded1 = [KSJSONCodec decode:data1 options:KSJSONDecodeOptionNone error:nil];
    NSDictionary *decoded2 = [KSJSONCodec decode:data2 options:KSJSONDecodeOptionNone error:nil];
    XCTAssertEqualObjects(decoded1[@"test_stitch"], @"shared data");
    XCTAssertEqualObjects(decoded2[@"test_stitch"], @"shared data");

    kscm_removeMonitor(&api);
}

- (int64_t)writeLargeReportWithRunId:(NSString *)runId reportKeyEarly:(BOOL)reportKeyEarly
{
    // Build a large report (>4 KB) to exercise orphan cleanup on oversized files.
    // When reportKeyEarly=YES, "report" appears near the start but run_id is
    // buried deep inside the report object (past any prefix window).
    // When reportKeyEarly=NO, the entire "report" section is past 2 KB.
    NSMutableString *padding = [NSMutableString stringWithCapacity:5000];
    for (int i = 0; i < 300; i++) {
        [padding appendFormat:@"\"pad_%03d\":\"x\",", i];
    }
    NSString *json;
    if (reportKeyEarly) {
        // "report" key at offset ~1, but run_id is after 4 KB of padding inside it
        json = [NSString stringWithFormat:@"{\"report\":{%@\"run_id\":\"%@\",\"id\":\"evt1\"}}", padding, runId];
        NSRange runIdRange = [json rangeOfString:@"\"run_id\":"];
        XCTAssertTrue(runIdRange.location > 2048, @"run_id must be past any 2 KB prefix window");
    } else {
        // "report" key itself is past 2 KB
        json = [NSString stringWithFormat:@"{%@\"report\":{\"run_id\":\"%@\",\"id\":\"evt1\"}}", padding, runId];
        NSRange reportRange = [json rangeOfString:@"\"report\":"];
        XCTAssertTrue(reportRange.location > 2048, @"report key must be past any 2 KB prefix window");
    }
    XCTAssertTrue(json.length > 4096, @"Report must be larger than 4 KB");
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    return kscrs_addUserReport(data.bytes, (int)data.length, &_storeConfig);
}

#pragma mark - Orphan Cleanup With Large Reports

- (void)testOrphanCleanupPreservesSidecarsForLargeReport
{
    [self prepareStoreWithRunSidecars:@"testLargeReportOrphan"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeLargeReportWithRunId:runId reportKeyEarly:NO];
    [self writeRunSidecar:@"System" runId:runId contents:@"system data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);

    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir],
                  @"Run sidecar should be preserved when report section is past 2 KB");
}

- (void)testOrphanCleanupPreservesSidecarsWhenRunIdIsDeepInsideReportSection
{
    [self prepareStoreWithRunSidecars:@"testDeepRunId"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeLargeReportWithRunId:runId reportKeyEarly:YES];
    [self writeRunSidecar:@"System" runId:runId contents:@"system data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);

    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir],
                  @"Run sidecar should be preserved when run_id is deep inside report section");
}

- (void)testOrphanCleanupDeletesOrphanButKeepsLargeReport
{
    [self prepareStoreWithRunSidecars:@"testLargeMixed"];
    NSString *activeRunId = [[NSUUID UUID] UUIDString];
    NSString *orphanRunId = [[NSUUID UUID] UUIDString];

    [self writeLargeReportWithRunId:activeRunId reportKeyEarly:YES];
    [self writeRunSidecar:@"System" runId:activeRunId contents:@"active"];
    [self writeRunSidecar:@"System" runId:orphanRunId contents:@"orphan"];

    NSString *activeDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:activeRunId];
    NSString *orphanDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:orphanRunId];

    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:activeDir],
                  @"Active large-report sidecar should be preserved");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:orphanDir],
                   @"Orphaned sidecar should still be deleted");
}

- (void)testOrphanCleanupHandlesArraysBeforeRunId
{
    [self prepareStoreWithRunSidecars:@"testArrayBeforeRunId"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    // report section has arrays and nested objects before run_id
    NSString *json = [NSString
        stringWithFormat:@"{\"report\":{\"breadcrumbs\":[1,2,3],\"nested\":{\"a\":true},\"run_id\":\"%@\"}}", runId];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    kscrs_addUserReport(data.bytes, (int)data.length, &_storeConfig);
    [self writeRunSidecar:@"System" runId:runId contents:@"data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];

    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir],
                  @"Run sidecar should be preserved when arrays precede run_id in report section");
}

- (void)testOrphanCleanupHandlesNestedReportKeyBeforeTopLevel
{
    [self prepareStoreWithRunSidecars:@"testNestedReportKey"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    // "report" appears as a nested key inside "meta" before the top-level "report"
    NSString *json =
        [NSString stringWithFormat:@"{\"meta\":{\"report\":{}},\"report\":{\"run_id\":\"%@\",\"id\":\"evt1\"}}", runId];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    kscrs_addUserReport(data.bytes, (int)data.length, &_storeConfig);
    [self writeRunSidecar:@"System" runId:runId contents:@"data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];

    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir],
                  @"Run sidecar should be preserved when nested 'report' key precedes top-level one");
}

- (void)testOrphanCleanupFallsBackOnOversizedKeyBeforeRunId
{
    [self prepareStoreWithRunSidecars:@"testOversizedKey"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    // Build a key longer than the streaming decoder's name buffer (4096/4 = 1024).
    // This forces KSJSON_ERROR_DATA_TOO_LONG and exercises the ObjC fallback.
    NSMutableString *longKey = [NSMutableString stringWithCapacity:1100];
    for (int i = 0; i < 1100; i++) {
        [longKey appendString:@"k"];
    }
    NSString *json = [NSString
        stringWithFormat:@"{\"%@\":\"value\",\"report\":{\"run_id\":\"%@\",\"id\":\"evt1\"}}", longKey, runId];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    kscrs_addUserReport(data.bytes, (int)data.length, &_storeConfig);
    [self writeRunSidecar:@"System" runId:runId contents:@"data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];

    kscrs_cleanupOrphanedRunSidecars(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir],
                  @"Run sidecar should be preserved via ObjC fallback when streaming decoder fails on oversized key");
}

@end
