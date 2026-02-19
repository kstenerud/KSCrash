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

#import "KSCrashReportStoreC+Private.h"
#import "KSCrashReportStoreC.h"

#include <inttypes.h>

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

- (void)prepareStoreWithRunSidecars:(NSString *)name
{
    NSString *reportsPath = [self.tempPath stringByAppendingPathComponent:name];
    NSString *sidecarsPath = [self.tempPath stringByAppendingPathComponent:@"Sidecars"];
    NSString *runSidecarsPath = [self.tempPath stringByAppendingPathComponent:@"RunSidecars"];
    _storeConfig.appName = "testapp";
    _storeConfig.reportsPath = reportsPath.UTF8String;
    _storeConfig.sidecarsPath = sidecarsPath.UTF8String;
    _storeConfig.runSidecarsPath = runSidecarsPath.UTF8String;
    _storeConfig.maxReportCount = 10;
    kscrs_initialize(&_storeConfig);
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

#pragma mark - kscrs_extractRunIdFromReport

- (void)testExtractRunIdFromValidReport
{
    const char *json = "{\"report\":{\"run_id\":\"abc-123\",\"id\":\"evt1\"}}";
    char buf[64];
    bool result = kscrs_extractRunIdFromReport(json, buf, sizeof(buf));
    XCTAssertTrue(result);
    XCTAssertEqual(strcmp(buf, "abc-123"), 0);
}

- (void)testExtractRunIdFromReportMissingRunId
{
    const char *json = "{\"report\":{\"id\":\"evt1\"}}";
    char buf[64];
    bool result = kscrs_extractRunIdFromReport(json, buf, sizeof(buf));
    XCTAssertFalse(result);
}

- (void)testExtractRunIdFromReportMissingReportSection
{
    const char *json = "{\"crash\":{\"error\":{}}}";
    char buf[64];
    bool result = kscrs_extractRunIdFromReport(json, buf, sizeof(buf));
    XCTAssertFalse(result);
}

- (void)testExtractRunIdFromInvalidJSON
{
    const char *json = "not json";
    char buf[64];
    bool result = kscrs_extractRunIdFromReport(json, buf, sizeof(buf));
    XCTAssertFalse(result);
}

- (void)testExtractRunIdNullReport
{
    char buf[64];
    bool result = kscrs_extractRunIdFromReport(NULL, buf, sizeof(buf));
    XCTAssertFalse(result);
}

- (void)testExtractRunIdNullBuffer
{
    const char *json = "{\"report\":{\"run_id\":\"abc\"}}";
    bool result = kscrs_extractRunIdFromReport(json, NULL, 64);
    XCTAssertFalse(result);
}

- (void)testExtractRunIdZeroBufferLength
{
    const char *json = "{\"report\":{\"run_id\":\"abc\"}}";
    char buf[64];
    bool result = kscrs_extractRunIdFromReport(json, buf, 0);
    XCTAssertFalse(result);
}

- (void)testExtractRunIdEmptyRunId
{
    const char *json = "{\"report\":{\"run_id\":\"\",\"id\":\"evt1\"}}";
    char buf[64];
    bool result = kscrs_extractRunIdFromReport(json, buf, sizeof(buf));
    XCTAssertFalse(result);
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
    [self writeReportWithRunId:@"run-1"];
    [self writeRunSidecar:@"System" runId:@"run-1" contents:@"system data"];

    kscrs_deleteAllReports(&_storeConfig);

    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), 0);
    NSString *runSidecarsDir = [NSString stringWithUTF8String:_storeConfig.runSidecarsPath];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:runSidecarsDir error:nil];
    XCTAssertEqual(contents.count, 0u);
}

#pragma mark - Run Sidecar Orphan Cleanup

- (void)testDeleteLastReportForRunCleansRunSidecars
{
    [self prepareStoreWithRunSidecars:@"testOrphanCleanup"];
    int64_t reportID = [self writeReportWithRunId:@"run-orphan"];
    [self writeRunSidecar:@"System" runId:@"run-orphan" contents:@"system data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:@"run-orphan"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);

    kscrs_deleteReportWithID(reportID, &_storeConfig);

    // Run sidecar dir should be cleaned since no reports share this run_id
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:runDir]);
}

- (void)testDeleteReportKeepsRunSidecarsWhenOtherReportsShareRunId
{
    [self prepareStoreWithRunSidecars:@"testKeepRunSidecars"];
    int64_t reportID1 = [self writeReportWithRunId:@"shared-run"];
    [self writeReportWithRunId:@"shared-run"];
    [self writeRunSidecar:@"System" runId:@"shared-run" contents:@"system data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:@"shared-run"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);

    kscrs_deleteReportWithID(reportID1, &_storeConfig);

    // Run sidecar dir should still exist — another report shares this run_id
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);
}

- (void)testDeleteReportWithNoRunSidecarsPathDoesNotCrash
{
    [self prepareStoreWithRunSidecars:@"testDeleteNoRunSidecars"];
    _storeConfig.runSidecarsPath = NULL;
    int64_t reportID = [self writeReportWithRunId:@"run-1"];
    kscrs_deleteReportWithID(reportID, &_storeConfig);
    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), 0);
}

- (void)testDeleteAllReportsWithNoRunSidecarsPathDoesNotCrash
{
    [self prepareStoreWithRunSidecars:@"testDeleteAllNoRunSidecars"];
    [self writeReportWithRunId:@"run-1"];
    _storeConfig.runSidecarsPath = NULL;
    kscrs_deleteAllReports(&_storeConfig);
    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), 0);
}

@end
