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
static CFDictionaryRef testStitchReport(CFDictionaryRef reportDict, const char *sidecarPath, KSCrashSidecarScope scope,
                                        __unused void *context)
{
    @autoreleasepool {
        if (scope != KSCrashSidecarScopeRun) {
            // The final pass reaches every registered monitor with no sidecar; nothing to add.
            CFRetain(reportDict);
            return reportDict;
        }
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

// Test helpers exposed from KSCrashC.c.
extern void kscrash_testcode_setRunID(const char *runID);

#pragma mark - Test monitors for stitch ordering

static const char *orderMonitorAId(__unused void *context) { return "OrderMonitorA"; }
static const char *orderMonitorBId(__unused void *context) { return "OrderMonitorB"; }

// Writes its sidecar's contents under a shared "ordered" key, so whichever monitor stitches last wins.
static CFDictionaryRef orderedStitchReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                           KSCrashSidecarScope scope, __unused void *context)
{
    @autoreleasepool {
        if (scope != KSCrashSidecarScopeRun) {
            // The final pass reaches every registered monitor with no sidecar; nothing to add.
            CFRetain(reportDict);
            return reportDict;
        }
        NSDictionary *decoded = (__bridge NSDictionary *)reportDict;
        if (![decoded isKindOfClass:[NSDictionary class]]) {
            return NULL;
        }
        NSString *content = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:sidecarPath]
                                                      encoding:NSUTF8StringEncoding
                                                         error:nil];
        if (content == nil) {
            return NULL;
        }
        NSMutableDictionary *dict = [decoded mutableCopy];
        dict[@"ordered"] = content;
        return (__bridge_retained CFDictionaryRef)dict;
    }
}

#pragma mark - Final-pass test monitor

static const char *finalPassMonitorId(__unused void *context) { return "FinalPassMonitor"; }

// Marks the report when the final pass reaches it; retains-and-returns for sidecar scopes.
static CFDictionaryRef finalPassStitchReport(CFDictionaryRef reportDict, const char *sidecarPath,
                                             KSCrashSidecarScope scope, __unused void *context)
{
    @autoreleasepool {
        if (scope != KSCrashSidecarScopeFinal) {
            CFRetain(reportDict);
            return reportDict;
        }
        NSDictionary *decoded = (__bridge NSDictionary *)reportDict;
        if (![decoded isKindOfClass:[NSDictionary class]]) {
            return NULL;
        }
        NSMutableDictionary *dict = [decoded mutableCopy];
        dict[@"final_pass"] = @YES;
        dict[@"final_pass_sidecar_path"] = sidecarPath == NULL ? @"null" : @"set";
        return (__bridge_retained CFDictionaryRef)dict;
    }
}

#pragma mark - Throwing test monitor

static const char *throwingMonitorId(__unused void *context) { return "ThrowingTestMonitor"; }

// Simulates a broken plugin stitcher: throws no matter the scope.
static CFDictionaryRef throwingStitchReport(__unused CFDictionaryRef reportDict, __unused const char *sidecarPath,
                                            __unused KSCrashSidecarScope scope, __unused void *context)
{
    [NSException raise:NSInternalInconsistencyException format:@"broken stitcher"];
    return NULL;
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
    kscrash_testcode_setRunID(NULL);
    [super tearDown];
}

- (void)prepareStoreWithRunSidecars:(NSString *)name
{
    NSString *reportsPath = [self.tempPath stringByAppendingPathComponent:name];
    NSString *sidecarsPath = [self.tempPath stringByAppendingPathComponent:@"Sidecars"];
    NSString *runSidecarsPath = [self.tempPath stringByAppendingPathComponent:@"RunSidecars"];
    NSString *runSummariesPath = [self.tempPath stringByAppendingPathComponent:@"Runs"];
    _storeConfig.appName = "testapp";
    _storeConfig.reportsPath = reportsPath.UTF8String;
    _storeConfig.reportSidecarsPath = sidecarsPath.UTF8String;
    _storeConfig.runSidecarsPath = runSidecarsPath.UTF8String;
    _storeConfig.runSummariesPath = runSummariesPath.UTF8String;
    _storeConfig.maxReportCount = 10;
    kscrs_initialize(&_storeConfig);
    kscrs_setStitchConfig(&_storeConfig);
    // Reclaim refuses to run without a current run id (pre-install safety);
    // these tests exercise a nominally installed process.
    kscrash_testcode_setRunID("11111111-aaaa-bbbb-cccc-000000000001");
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

- (NSString *)writeRunSummaryJSON:(NSString *)json named:(NSString *)filename
{
    NSString *dir = [NSString stringWithUTF8String:_storeConfig.runSummariesPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:filename];
    [json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

- (NSString *)writeSessionsFileForRunId:(NSString *)runId
{
    NSString *dir = [NSString stringWithUTF8String:_storeConfig.runSummariesPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    // Reclaim matches .sessions by filename only; contents are irrelevant here.
    NSString *path = [dir stringByAppendingPathComponent:[runId stringByAppendingPathExtension:@"sessions"]];
    [@"session bytes" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
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

- (void)testDeleteAllReportsDefersRunSidecarCleanupToReclaim
{
    [self prepareStoreWithRunSidecars:@"testDeleteAllRunSidecars"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"System" runId:runId contents:@"system data"];

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];

    kscrs_deleteAllReports(&_storeConfig);

    // Cleanup is deferred to reclaim, mirroring kscrs_deleteReportWithID.
    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), 0);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir]);

    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:runDir]);
}

- (void)testDeleteAllReportsKeepsRunDataReferencedBySummariesAndLiveRun
{
    [self prepareStoreWithRunSidecars:@"testDeleteAllKeepsSummaryData"];
    NSFileManager *fm = [NSFileManager defaultManager];

    // Three runs: one referenced only by a queued summary, one referenced only
    // by a report (about to be deleted), and the live run.
    NSString *pendingRunId = [[NSUUID UUID] UUIDString];
    [self writeRunSummaryJSON:[NSString stringWithFormat:@"{\"run_id\":\"%@\"}", pendingRunId] named:@"100.run"];
    [self writeRunSidecar:@"UserInfo" runId:pendingRunId contents:@"pending metadata"];
    NSString *pendingSessions = [self writeSessionsFileForRunId:pendingRunId];

    NSString *reportRunId = [[NSUUID UUID] UUIDString];
    [self writeReportWithRunId:reportRunId];
    [self writeRunSidecar:@"System" runId:reportRunId contents:@"report run data"];
    NSString *reportSessions = [self writeSessionsFileForRunId:reportRunId];

    NSString *liveRunId = @"11111111-aaaa-bbbb-cccc-000000000001";
    [self writeRunSidecar:@"Lifecycle" runId:liveRunId contents:@"live data"];
    NSString *liveSessions = [self writeSessionsFileForRunId:liveRunId];

    kscrs_deleteAllReports(&_storeConfig);
    kscrs_reclaimOrphanedRunData(&_storeConfig);

    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), 0);
    NSString *sidecars = [NSString stringWithUTF8String:_storeConfig.runSidecarsPath];
    // The summary's run and the live run keep their data; the deleted report
    // was the last reference to its run, so the reclaim that follows a send
    // removes that run's data.
    XCTAssertTrue([fm fileExistsAtPath:[sidecars stringByAppendingPathComponent:pendingRunId]]);
    XCTAssertTrue([fm fileExistsAtPath:pendingSessions]);
    XCTAssertTrue([fm fileExistsAtPath:[sidecars stringByAppendingPathComponent:liveRunId]]);
    XCTAssertTrue([fm fileExistsAtPath:liveSessions]);
    XCTAssertFalse([fm fileExistsAtPath:[sidecars stringByAppendingPathComponent:reportRunId]]);
    XCTAssertFalse([fm fileExistsAtPath:reportSessions]);
}

#pragma mark - Run Sidecar Orphan Cleanup

// The tests in this group leave runSidecarRetentionSeconds at 0 (the setUp memset), which
// means delete-on-sight; they double as coverage for the zero-retention behavior. The
// retention-window tests further down set it explicitly.

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
    kscrs_reclaimOrphanedRunData(&_storeConfig);
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
    kscrs_reclaimOrphanedRunData(&_storeConfig);
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
    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:activeDir]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:orphanDir]);
}

// Regression: a leftover ".json.tmp" (atomic-write remnant) or ".old" (recrash
// backup) parses to a report id via the permissive filename scan, but its
// canonical .json may be gone. Reclamation must skip such artifacts, not treat
// the missing canonical report as a read failure and abort, so genuine orphans
// are still cleaned.
- (void)testCleanupIgnoresLeftoverReportArtifacts
{
    [self prepareStoreWithRunSidecars:@"testReclaimArtifacts"];
    NSString *activeRunId = [[NSUUID UUID] UUIDString];
    NSString *orphanRunId = [[NSUUID UUID] UUIDString];

    [self writeReportWithRunId:activeRunId];
    [self writeRunSidecar:@"System" runId:activeRunId contents:@"active data"];
    [self writeRunSidecar:@"System" runId:orphanRunId contents:@"orphan data"];

    // Artifacts whose canonical testapp-report-<id>.json does not exist.
    NSString *reportsDir = [NSString stringWithUTF8String:_storeConfig.reportsPath];
    for (NSString *name in @[ @"testapp-report-00000000deadbeef.json.tmp", @"testapp-report-00000000deadbee0.old" ]) {
        NSString *path = [reportsDir stringByAppendingPathComponent:name];
        XCTAssertTrue([@"leftover" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    }

    NSString *activeDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:activeRunId];
    NSString *orphanDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:orphanRunId];

    kscrs_reclaimOrphanedRunData(&_storeConfig);

    // Reclamation ran to completion despite the artifacts: orphan gone, active kept.
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:orphanDir]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:activeDir]);
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

    kscrs_reclaimOrphanedRunData(&_storeConfig);

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *runDir in runDirs) {
        XCTAssertTrue([fm fileExistsAtPath:runDir], @"Run sidecar wrongly deleted: %@", runDir);
    }
}

#pragma mark - Shared constants

- (void)testUserInfoSidecarFilenameComposesFromItsParts
{
    // Swift reads the composed filename constant while C composes the path
    // from the id and extension; this is the lockstep guarantee.
    NSString *composed = [NSString stringWithFormat:@"%s.%s", KSCRS_MONITOR_ID_USERINFO, KSCRS_RUN_SIDECAR_EXTENSION];
    XCTAssertEqualObjects(@KSCRS_USERINFO_RUN_SIDECAR_FILENAME, composed);
}

#pragma mark - Reclaim guards

- (void)testReclaimNoOpsBeforeInstall
{
    [self prepareStoreWithRunSidecars:@"testPreInstallReclaim"];
    NSString *orphanRunId = [[NSUUID UUID] UUIDString];
    [self writeRunSidecar:@"UserInfo" runId:orphanRunId contents:@"orphan"];
    NSString *orphanSessions = [self writeSessionsFileForRunId:orphanRunId];
    NSString *orphanDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:orphanRunId];

    // Pre-install (no current run id) the previous run's data is not yet
    // referenced by anything; reclaim must not touch it.
    kscrash_testcode_setRunID(NULL);
    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:orphanDir]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:orphanSessions]);

    kscrash_testcode_setRunID("11111111-aaaa-bbbb-cccc-000000000001");
    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:orphanDir]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:orphanSessions]);
}

- (void)testReclaimDeletesTruncatedSummaryAndProceeds
{
    [self prepareStoreWithRunSidecars:@"testTruncatedSummary"];
    NSString *orphanRunId = [[NSUUID UUID] UUIDString];
    [self writeRunSidecar:@"UserInfo" runId:orphanRunId contents:@"orphan"];
    NSString *orphanDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:orphanRunId];
    // A truncated summary (crash mid-persist): deterministic garbage in a
    // single-process store, so it must not block the pass.
    NSString *garbagePath = [self writeRunSummaryJSON:@"{\"run_id\": \"12345678-aaaa" named:@"400.run"];

    kscrs_reclaimOrphanedRunData(&_storeConfig);

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:orphanDir]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:garbagePath]);
}

- (void)testReclaimDeletesEmptySummaryAndProceeds
{
    [self prepareStoreWithRunSidecars:@"testEmptySummary"];
    NSString *orphanRunId = [[NSUUID UUID] UUIDString];
    [self writeRunSidecar:@"UserInfo" runId:orphanRunId contents:@"orphan"];
    NSString *orphanDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:orphanRunId];
    // A 0-byte summary (crash between O_TRUNC and the write): permanently
    // malformed and deleted so it can never jam reclamation.
    NSString *garbagePath = [self writeRunSummaryJSON:@"" named:@"500.run"];

    kscrs_reclaimOrphanedRunData(&_storeConfig);

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:orphanDir]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:garbagePath]);
}

#pragma mark - Reclaim with pending summaries

- (void)testReclaimKeepsRunDataWhileSummaryPending
{
    [self prepareStoreWithRunSidecars:@"testSummaryRetention"];
    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeRunSidecar:@"UserInfo" runId:runId contents:@"user data"];
    NSString *sessionsPath = [self writeSessionsFileForRunId:runId];
    NSString *summaryPath = [self writeRunSummaryJSON:[NSString stringWithFormat:@"{\"run_id\":\"%@\"}", runId]
                                                named:@"100.run"];
    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    NSFileManager *fm = [NSFileManager defaultManager];

    // No report references the run: the pending summary alone must keep both
    // the run sidecars (metadata stitch) and the .sessions (record merge).
    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertTrue([fm fileExistsAtPath:runDir]);
    XCTAssertTrue([fm fileExistsAtPath:sessionsPath]);

    // Summary delivered: nothing references the run any more.
    [fm removeItemAtPath:summaryPath error:nil];
    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertFalse([fm fileExistsAtPath:runDir]);
    XCTAssertFalse([fm fileExistsAtPath:sessionsPath]);
}

- (void)testReclaimAbortsWhenASummaryCannotBeRead
{
    [self prepareStoreWithRunSidecars:@"testUnreadableSummary"];
    NSString *orphanRunId = [[NSUUID UUID] UUIDString];
    [self writeRunSidecar:@"UserInfo" runId:orphanRunId contents:@"orphan"];
    NSString *orphanSessions = [self writeSessionsFileForRunId:orphanRunId];
    NSString *pendingRunId = [[NSUUID UUID] UUIDString];
    NSString *summaryPath = [self writeRunSummaryJSON:[NSString stringWithFormat:@"{\"run_id\":\"%@\"}", pendingRunId]
                                                named:@"200.run"];
    NSString *orphanDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:orphanRunId];
    NSFileManager *fm = [NSFileManager defaultManager];

    // An unreadable queued summary may be mid-write; the whole pass must be
    // skipped rather than treating its run as unreferenced.
    [fm setAttributes:@{ NSFilePosixPermissions : @0 } ofItemAtPath:summaryPath error:nil];
    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertTrue([fm fileExistsAtPath:orphanDir]);
    XCTAssertTrue([fm fileExistsAtPath:orphanSessions]);

    // Readable again: the pass proceeds, reclaiming only the true orphan.
    [fm setAttributes:@{ NSFilePosixPermissions : @0644 } ofItemAtPath:summaryPath error:nil];
    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertFalse([fm fileExistsAtPath:orphanDir]);
    XCTAssertFalse([fm fileExistsAtPath:orphanSessions]);
    XCTAssertTrue([fm fileExistsAtPath:summaryPath]);
}

- (void)testReclaimProceedsPastSummaryWithoutRunId
{
    [self prepareStoreWithRunSidecars:@"testMalformedSummary"];
    NSString *orphanRunId = [[NSUUID UUID] UUIDString];
    [self writeRunSidecar:@"UserInfo" runId:orphanRunId contents:@"orphan"];
    NSString *orphanDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:orphanRunId];
    // Decodes fine but references nothing: permanently malformed, must not
    // block reclamation forever.
    [self writeRunSummaryJSON:@"{\"not_run_id\":1}" named:@"300.run"];

    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:orphanDir]);
}

#pragma mark - Run Sidecar Retention Window

- (void)setModificationDate:(NSDate *)date forRunSidecarDirWithRunID:(NSString *)runId
{
    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate : date }
                                                   ofItemAtPath:runDir
                                                          error:&error],
                  @"%@", error);
}

- (void)testOrphanCleanupKeepsYoungUnreferencedRunSidecarDir
{
    [self prepareStoreWithRunSidecars:@"testRetentionYoung"];
    _storeConfig.runSidecarRetentionSeconds = KSCRS_DEFAULT_RUN_SIDECAR_RETENTION_SECONDS;
    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeRunSidecar:@"System" runId:runId contents:@"system data"];

    kscrs_reclaimOrphanedRunData(&_storeConfig);

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir],
                  @"An unreferenced dir inside the retention window must survive");
}

- (void)testOrphanCleanupDeletesAgedUnreferencedRunSidecarDir
{
    [self prepareStoreWithRunSidecars:@"testRetentionAged"];
    _storeConfig.runSidecarRetentionSeconds = KSCRS_DEFAULT_RUN_SIDECAR_RETENTION_SECONDS;
    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeRunSidecar:@"System" runId:runId contents:@"system data"];
    [self setModificationDate:[NSDate dateWithTimeIntervalSinceNow:-31.0 * 24.0 * 60.0 * 60.0]
        forRunSidecarDirWithRunID:runId];

    kscrs_reclaimOrphanedRunData(&_storeConfig);

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:runDir],
                   @"An unreferenced dir past the retention window must be deleted");
}

- (void)testOrphanCleanupKeepsAgedReferencedRunSidecarDir
{
    [self prepareStoreWithRunSidecars:@"testRetentionReferenced"];
    _storeConfig.runSidecarRetentionSeconds = KSCRS_DEFAULT_RUN_SIDECAR_RETENTION_SECONDS;
    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeReportWithRunId:runId];
    [self writeRunSidecar:@"System" runId:runId contents:@"system data"];
    [self setModificationDate:[NSDate dateWithTimeIntervalSinceNow:-31.0 * 24.0 * 60.0 * 60.0]
        forRunSidecarDirWithRunID:runId];

    kscrs_reclaimOrphanedRunData(&_storeConfig);

    NSString *runDir =
        [[NSString stringWithUTF8String:_storeConfig.runSidecarsPath] stringByAppendingPathComponent:runId];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir],
                  @"A referenced dir is kept regardless of age");
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

- (void)testThrowingStitchCallbackIsContainedAndDoesNotPoisonTheStore
{
    [self prepareStoreWithRunSidecars:@"testThrowingStitch"];

    KSCrashMonitorAPI api = {};
    kscma_initAPI(&api);
    api.monitorId = throwingMonitorId;
    api.createStitchedReport = throwingStitchReport;
    kscm_addMonitor(&api);

    int64_t reportID = [self writeReportWithRunId:[[NSUUID UUID] UUIDString]];

    // The read survives the throw (final pass reaches the broken monitor) and the report
    // comes back unstitched rather than lost.
    char *rawReport = kscrs_readReport(reportID, &_storeConfig);
    XCTAssertTrue(rawReport != NULL);
    free(rawReport);

    // Finalization reports the failure instead of wedging.
    NSString *path = [NSString
        stringWithFormat:@"%s/testapp-report-%016llx.json", _storeConfig.reportsPath, (unsigned long long)reportID];
    XCTAssertFalse(kscrs_finalizeReport(path.UTF8String, reportID));

    kscm_removeMonitor(&api);

    // The regression this pins: an exception unwinding through the walk used to leave the
    // store mutex locked, so this next call deadlocked forever.
    kscrs_setStitchConfig(&_storeConfig);
}

- (void)testFinalPassReachesRegisteredMonitorsWithNoSidecar
{
    [self prepareStoreWithRunSidecars:@"testFinalPass"];

    KSCrashMonitorAPI api = {};
    kscma_initAPI(&api);
    api.monitorId = finalPassMonitorId;
    api.createStitchedReport = finalPassStitchReport;
    kscm_addMonitor(&api);

    // No sidecars anywhere: the final pass alone must reach the monitor.
    int64_t reportID = [self writeReportWithRunId:[[NSUUID UUID] UUIDString]];
    char *rawReport = kscrs_readReport(reportID, &_storeConfig);
    XCTAssertTrue(rawReport != NULL);

    NSData *data = [NSData dataWithBytesNoCopy:rawReport length:strlen(rawReport) freeWhenDone:YES];
    NSDictionary *decoded = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
    XCTAssertEqualObjects(decoded[@"final_pass"], @YES, @"the final pass must run on read");
    XCTAssertEqualObjects(decoded[@"final_pass_sidecar_path"], @"null", @"the final pass has no sidecar file");

    kscm_removeMonitor(&api);
}

- (void)testRunSidecarStitchAppliesInPriorityOrder
{
    [self prepareStoreWithRunSidecars:@"testStitchPriorityOrder"];

    KSCrashMonitorAPI apiA = {};
    kscma_initAPI(&apiA);
    apiA.monitorId = orderMonitorAId;
    apiA.createStitchedReport = orderedStitchReport;
    KSCrashMonitorAPI apiB = {};
    kscma_initAPI(&apiB);
    apiB.monitorId = orderMonitorBId;
    apiB.createStitchedReport = orderedStitchReport;

    NSString *runId = [[NSUUID UUID] UUIDString];
    [self writeRunSidecar:@"OrderMonitorA" runId:runId contents:@"from-A"];
    [self writeRunSidecar:@"OrderMonitorB" runId:runId contents:@"from-B"];

    // Higher priority stitches last and wins the shared key: B wins here.
    apiA.priority = 0;
    apiB.priority = 10;
    kscm_addMonitor(&apiA);
    kscm_addMonitor(&apiB);
    int64_t reportID = [self writeReportWithRunId:runId];
    char *raw = kscrs_readReport(reportID, &_storeConfig);
    NSData *data = [NSData dataWithBytesNoCopy:raw length:strlen(raw) freeWhenDone:YES];
    NSDictionary *decoded = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
    XCTAssertEqualObjects(decoded[@"ordered"], @"from-B");
    kscm_removeMonitor(&apiA);
    kscm_removeMonitor(&apiB);

    // Flip the priorities: A now wins, proving the order follows priority, not registration or the
    // directory listing.
    apiA.priority = 10;
    apiB.priority = 0;
    kscm_addMonitor(&apiA);
    kscm_addMonitor(&apiB);
    int64_t reportID2 = [self writeReportWithRunId:runId];
    char *raw2 = kscrs_readReport(reportID2, &_storeConfig);
    NSData *data2 = [NSData dataWithBytesNoCopy:raw2 length:strlen(raw2) freeWhenDone:YES];
    NSDictionary *decoded2 = [KSJSONCodec decode:data2 options:KSJSONDecodeOptionNone error:nil];
    XCTAssertEqualObjects(decoded2[@"ordered"], @"from-A");
    kscm_removeMonitor(&apiA);
    kscm_removeMonitor(&apiB);
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

    kscrs_reclaimOrphanedRunData(&_storeConfig);
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

    kscrs_reclaimOrphanedRunData(&_storeConfig);
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

    kscrs_reclaimOrphanedRunData(&_storeConfig);
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

    kscrs_reclaimOrphanedRunData(&_storeConfig);
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

    kscrs_reclaimOrphanedRunData(&_storeConfig);
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

    kscrs_reclaimOrphanedRunData(&_storeConfig);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:runDir],
                  @"Run sidecar should be preserved via ObjC fallback when streaming decoder fails on oversized key");
}

@end
