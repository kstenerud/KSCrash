//
//  KSCrashReportFinalizer_Tests.m
//
//  Created by Alexander Cohen on 2026-03-21.
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

#import "KSCrashConfiguration.h"
#import "KSCrashMonitor.h"
#import "KSCrashReportFields.h"
#import "KSCrashReportStore.h"
#import "KSCrashReportStoreC+Private.h"
#import "KSCrashReportStoreC.h"
#import "KSJSONCodecObjC.h"

#include <inttypes.h>

#pragma mark - Test monitor stitch callback

static const char *finalizerTestMonitorId(__unused void *context) { return "FinalizerTestMonitor"; }

static CFDictionaryRef finalizerTestStitchReport(CFDictionaryRef reportDict, const char *sidecarPath,
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
        dict[@"finalizer_test_stitch"] = sidecarContent;
        return (__bridge_retained CFDictionaryRef)dict;
    }
}

// A stitch callback that always fails (returns NULL), simulating
// a monitor that can't parse the report during finalization.
static const char *failingMonitorId(__unused void *context) { return "FailingTestMonitor"; }

static CFDictionaryRef failingStitchReport(__unused CFDictionaryRef reportDict, __unused const char *sidecarPath,
                                           __unused KSCrashSidecarScope scope, __unused void *context)
{
    return NULL;
}

// A stitch callback that has nothing to change (returns the input).
static const char *noopMonitorId(__unused void *context) { return "NoopTestMonitor"; }

static CFDictionaryRef noopStitchReport(CFDictionaryRef reportDict, __unused const char *sidecarPath,
                                        __unused KSCrashSidecarScope scope, __unused void *context)
{
    CFRetain(reportDict);
    return reportDict;
}

#pragma mark - Tests

@interface KSCrashReportFinalizer_Tests : FileBasedTestCase
@end

@implementation KSCrashReportFinalizer_Tests {
    KSCrashReportStoreCConfiguration _storeConfig;
    KSCrashMonitorAPI _testMonitorAPI;
    KSCrashMonitorAPI _failingMonitorAPI;
    KSCrashMonitorAPI _noopMonitorAPI;
}

- (void)setUp
{
    [super setUp];
    memset(&_storeConfig, 0, sizeof(_storeConfig));
    memset(&_testMonitorAPI, 0, sizeof(_testMonitorAPI));
    memset(&_failingMonitorAPI, 0, sizeof(_failingMonitorAPI));
    memset(&_noopMonitorAPI, 0, sizeof(_noopMonitorAPI));
}

- (void)tearDown
{
    kscrs_setStitchConfig(NULL);
    kscm_removeMonitor(&_testMonitorAPI);
    kscm_removeMonitor(&_failingMonitorAPI);
    kscm_removeMonitor(&_noopMonitorAPI);
    [super tearDown];
}

- (void)prepareStore:(NSString *)name
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

- (void)writeReportSidecar:(NSString *)monitorId reportID:(int64_t)reportID contents:(NSString *)contents
{
    NSString *monDir =
        [[NSString stringWithUTF8String:_storeConfig.reportSidecarsPath] stringByAppendingPathComponent:monitorId];
    [[NSFileManager defaultManager] createDirectoryAtPath:monDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *path = [monDir
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%016llx.ksscr", (unsigned long long)reportID]];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (NSString *)reportPathForID:(int64_t)reportID
{
    return [NSString stringWithFormat:@"%s/%s-report-%016llx.json", _storeConfig.reportsPath, _storeConfig.appName,
                                      (unsigned long long)reportID];
}

- (NSDictionary *)readReportJSON:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    return [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
}

- (void)registerTestMonitor
{
    kscma_initAPI(&_testMonitorAPI);
    _testMonitorAPI.monitorId = finalizerTestMonitorId;
    _testMonitorAPI.createStitchedReport = finalizerTestStitchReport;
    kscm_addMonitor(&_testMonitorAPI);
}

#pragma mark - Null / Invalid Input

- (void)testFinalizeNullPathReturnsFalse
{
    XCTAssertFalse(kscrs_finalizeReport(NULL, 12345));
}

- (void)testFinalizeEmptyPathReturnsFalse
{
    XCTAssertFalse(kscrs_finalizeReport("", 12345));
}

- (void)testFinalizeZeroReportIDReturnsFalse
{
    XCTAssertFalse(kscrs_finalizeReport("/tmp/fake.json", 0));
}

- (void)testFinalizeNonexistentReportReturnsFalse
{
    [self prepareStore:@"testNonexistent"];
    XCTAssertFalse(kscrs_finalizeReport("/tmp/nonexistent.json", 12345));
}

#pragma mark - Basic Finalization

- (void)testFinalizeAddsFinalizedFlag
{
    [self prepareStore:@"testFinalizeFlag"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    NSString *path = [self reportPathForID:reportID];

    bool result = kscrs_finalizeReport(path.UTF8String, reportID);
    XCTAssertTrue(result);

    NSDictionary *report = [self readReportJSON:path];
    XCTAssertNotNil(report);
    XCTAssertEqualObjects(report[@"report"][@"finalized"], @YES);
}

- (void)testFinalizePreservesReportContent
{
    [self prepareStore:@"testPreserveContent"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    NSString *path = [self reportPathForID:reportID];

    kscrs_finalizeReport(path.UTF8String, reportID);

    NSDictionary *report = [self readReportJSON:path];
    XCTAssertEqualObjects(report[@"report"][@"run_id"], runId);
    XCTAssertEqualObjects(report[@"report"][@"id"], @"evt1");
}

#pragma mark - Stitching Integration

- (void)testFinalizeStitchesRunSidecars
{
    [self prepareStore:@"testStitchRunSidecars"];
    [self registerTestMonitor];

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"FinalizerTestMonitor" runId:runId contents:@"stitched_run_data"];
    NSString *path = [self reportPathForID:reportID];

    bool result = kscrs_finalizeReport(path.UTF8String, reportID);
    XCTAssertTrue(result);

    NSDictionary *report = [self readReportJSON:path];
    XCTAssertEqualObjects(report[@"finalizer_test_stitch"], @"stitched_run_data");
    XCTAssertEqualObjects(report[@"report"][@"finalized"], @YES);
}

- (void)testFinalizeStitchesReportSidecars
{
    [self prepareStore:@"testStitchReportSidecars"];
    [self registerTestMonitor];

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeReportSidecar:@"FinalizerTestMonitor" reportID:reportID contents:@"stitched_report_data"];
    NSString *path = [self reportPathForID:reportID];

    bool result = kscrs_finalizeReport(path.UTF8String, reportID);
    XCTAssertTrue(result);

    NSDictionary *report = [self readReportJSON:path];
    XCTAssertEqualObjects(report[@"finalizer_test_stitch"], @"stitched_report_data");
}

- (void)testConstructingReportStoreDoesNotHijackStitchConfig
{
    // Regression: prior to the fix, KSCrashReportStore.init called
    // kscrs_initialize, which had the side effect of replacing the global
    // stitch config with the Store's config. Constructing a Store after
    // install made finalize/read look up sidecars in the Store's paths
    // instead of the install's. This test pins the new contract: only
    // kscrs_setStitchConfig sets the stitch config; constructing a Store
    // does not.
    [self prepareStore:@"testHijackA"];  // sets stitch config to _storeConfig (paths under testHijackA)
    [self registerTestMonitor];

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeReportSidecar:@"FinalizerTestMonitor" reportID:reportID contents:@"data_from_store_A"];
    NSString *path = [self reportPathForID:reportID];

    // Construct an unrelated KSCrashReportStore with a different reports path.
    // Its init calls kscrs_initialize on its own config; we expect the stitch
    // config (set above by prepareStore) to remain unchanged.
    KSCrashReportStoreConfiguration *otherConfig = [KSCrashReportStoreConfiguration new];
    otherConfig.appName = @"otherapp";
    otherConfig.reportsPath = [self.tempPath stringByAppendingPathComponent:@"testHijackB"];
    KSCrashReportStore *otherStore = [KSCrashReportStore storeWithConfiguration:otherConfig error:nil];
    XCTAssertNotNil(otherStore);

    // If construction had hijacked the stitch config, finalize would now look
    // for sidecars under testHijackB's paths and fail to find the one written
    // under testHijackA. With the fix, the stitch config still points at
    // testHijackA and the sidecar is found.
    bool result = kscrs_finalizeReport(path.UTF8String, reportID);
    XCTAssertTrue(result);

    NSDictionary *report = [self readReportJSON:path];
    XCTAssertEqualObjects(report[@"finalizer_test_stitch"], @"data_from_store_A");
}

#pragma mark - Sidecar Cleanup

- (void)testFinalizeDeletesPerReportSidecars
{
    // Sidecars are intentionally preserved after finalization to avoid
    // I/O during recovery and to allow re-stitching if needed. They are
    // cleaned up later when the report itself is deleted after consumption.
    [self prepareStore:@"testDeleteSidecars"];
    [self registerTestMonitor];

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeReportSidecar:@"FinalizerTestMonitor" reportID:reportID contents:@"data"];
    NSString *path = [self reportPathForID:reportID];

    NSString *sidecarPath = [NSString stringWithFormat:@"%s/FinalizerTestMonitor/%016llx.ksscr",
                                                       _storeConfig.reportSidecarsPath, (unsigned long long)reportID];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:sidecarPath]);

    kscrs_finalizeReport(path.UTF8String, reportID);

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:sidecarPath]);
}

- (void)testFinalizeKeepsRunSidecars
{
    [self prepareStore:@"testKeepsRunSidecars"];
    [self registerTestMonitor];

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"FinalizerTestMonitor" runId:runId contents:@"run data"];
    NSString *path = [self reportPathForID:reportID];

    kscrs_finalizeReport(path.UTF8String, reportID);

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);
}

#pragma mark - Skip Stitching on Read

- (void)testFinalizedReportSkipsStitchingOnRead
{
    [self prepareStore:@"testSkipStitching"];
    [self registerTestMonitor];

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"FinalizerTestMonitor" runId:runId contents:@"original_data"];
    NSString *path = [self reportPathForID:reportID];

    // Finalize — stitches "original_data"
    kscrs_finalizeReport(path.UTF8String, reportID);

    // Write a new sidecar with different data
    [self writeRunSidecar:@"FinalizerTestMonitor" runId:runId contents:@"new_data"];

    // Read via the normal path — should see "original_data" (skip re-stitching)
    char *rawReport = kscrs_readReport(reportID, &_storeConfig);
    XCTAssertTrue(rawReport != NULL);

    NSData *data = [NSData dataWithBytesNoCopy:rawReport length:strlen(rawReport) freeWhenDone:YES];
    NSDictionary *decoded = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
    XCTAssertEqualObjects(decoded[@"finalizer_test_stitch"], @"original_data");
}

#pragma mark - Pre-Finalized Reports

- (void)testPreFinalizedUserReportSkipsStitchingOnRead
{
    [self prepareStore:@"testPreFinalized"];
    [self registerTestMonitor];

    NSString *runId = [[NSUUID UUID] UUIDString];

    // Write a report that is already finalized in the JSON body,
    // as MetricKit does to prevent stitch contamination.
    NSString *json = [NSString stringWithFormat:@"{\"report\":{\"run_id\":\"%@\",\"id\":\"mk1\",\"finalized\":true},"
                                                @"\"system\":{\"os_version\":\"original\"}}",
                                                runId];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    int64_t reportID = kscrs_addUserReport(data.bytes, (int)data.length, &_storeConfig);
    XCTAssertTrue(reportID > 0);

    // Plant a run sidecar that would overwrite system.os_version if stitching ran
    [self writeRunSidecar:@"FinalizerTestMonitor" runId:runId contents:@"contaminated"];

    // Read via normal path — must return the report as-is
    char *rawReport = kscrs_readReport(reportID, &_storeConfig);
    XCTAssertTrue(rawReport != NULL);

    NSData *readData = [NSData dataWithBytesNoCopy:rawReport length:strlen(rawReport) freeWhenDone:YES];
    NSDictionary *decoded = [KSJSONCodec decode:readData options:KSJSONDecodeOptionNone error:nil];

    // Stitch data must NOT be present
    XCTAssertNil(decoded[@"finalizer_test_stitch"]);
    // Original data must be preserved
    XCTAssertEqualObjects(decoded[@"system"][@"os_version"], @"original");
}

- (void)testNonFinalizedUserReportIsStitchedOnRead
{
    [self prepareStore:@"testNonFinalized"];
    [self registerTestMonitor];

    NSString *runId = [[NSUUID UUID] UUIDString];

    // Write a report WITHOUT the finalized flag
    NSString *json = [NSString
        stringWithFormat:@"{\"report\":{\"run_id\":\"%@\",\"id\":\"mk2\"},\"system\":{\"os_version\":\"original\"}}",
                         runId];
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    int64_t reportID = kscrs_addUserReport(data.bytes, (int)data.length, &_storeConfig);
    XCTAssertTrue(reportID > 0);

    // Plant a run sidecar
    [self writeRunSidecar:@"FinalizerTestMonitor" runId:runId contents:@"hydrated"];

    // Read via normal path — stitch must run
    char *rawReport = kscrs_readReport(reportID, &_storeConfig);
    XCTAssertTrue(rawReport != NULL);

    NSData *readData = [NSData dataWithBytesNoCopy:rawReport length:strlen(rawReport) freeWhenDone:YES];
    NSDictionary *decoded = [KSJSONCodec decode:readData options:KSJSONDecodeOptionNone error:nil];

    // Stitch data must be present
    XCTAssertEqualObjects(decoded[@"finalizer_test_stitch"], @"hydrated");
}

#pragma mark - Idempotency

- (void)testFinalizeAlreadyFinalizedReport
{
    [self prepareStore:@"testDoubleFinalize"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    NSString *path = [self reportPathForID:reportID];

    XCTAssertTrue(kscrs_finalizeReport(path.UTF8String, reportID));
    // Second finalization should still succeed
    XCTAssertTrue(kscrs_finalizeReport(path.UTF8String, reportID));

    NSDictionary *report = [self readReportJSON:path];
    XCTAssertEqualObjects(report[@"report"][@"finalized"], @YES);
}

#pragma mark - Stitch Failure

- (void)testFinalizeSkippedWhenStitchFails
{
    [self prepareStore:@"testStitchFailure"];

    // Register a monitor whose stitch callback always returns NULL
    kscma_initAPI(&_failingMonitorAPI);
    _failingMonitorAPI.monitorId = failingMonitorId;
    _failingMonitorAPI.createStitchedReport = failingStitchReport;
    kscm_addMonitor(&_failingMonitorAPI);

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeReportSidecar:@"FailingTestMonitor" reportID:reportID contents:@"data"];
    NSString *path = [self reportPathForID:reportID];

    // Finalization should fail because the stitch callback returned NULL
    bool result = kscrs_finalizeReport(path.UTF8String, reportID);
    XCTAssertFalse(result);

    // The report on disk should NOT have a finalized flag
    NSDictionary *report2 = [self readReportJSON:path];
    XCTAssertNil(report2[@"report"][@"finalized"]);
}

- (void)testFinalizeSucceedsWithNoopSidecar
{
    [self prepareStore:@"testNoopSidecar"];

    // Register a monitor whose stitch callback returns the report unchanged
    kscma_initAPI(&_noopMonitorAPI);
    _noopMonitorAPI.monitorId = noopMonitorId;
    _noopMonitorAPI.createStitchedReport = noopStitchReport;
    kscm_addMonitor(&_noopMonitorAPI);

    NSString *runId = [[NSUUID UUID] UUIDString];
    int64_t reportID = [self writeReportWithRunId:runId];
    [self writeReportSidecar:@"NoopTestMonitor" reportID:reportID contents:@"data"];
    NSString *path = [self reportPathForID:reportID];

    // Finalization should succeed — the no-op callback returned a copy, not NULL
    bool result = kscrs_finalizeReport(path.UTF8String, reportID);
    XCTAssertTrue(result);

    NSDictionary *report = [self readReportJSON:path];
    XCTAssertEqualObjects(report[@"report"][@"finalized"], @YES);
}

@end
