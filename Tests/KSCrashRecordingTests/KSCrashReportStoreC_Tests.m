//
//  KSCrashReportStoreC_Tests.m
//
//  Created by Karl Stenerud on 2012-02-05.
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
#import "KSCrashReportStoreC+Private.h"
#import "KSCrashReportStoreC.h"

#include <inttypes.h>

#define REPORT_PREFIX @"CrashReport-KSCrashTest"
#define REPORT_CONTENTS(NUM) @"{\n    \"a\": \"" #NUM "\"\n}"

@interface KSCrashReportStoreC_Tests : FileBasedTestCase

@property(nonatomic, readwrite, copy) NSString *appName;
@property(nonatomic, readwrite, copy) NSString *reportStorePath;
@property(atomic, readwrite, assign) int64_t reportCounter;

@end

@implementation KSCrashReportStoreC_Tests {
    KSCrashReportStoreCConfiguration _storeConfig;
}

- (int64_t)getReportIDFromPath:(NSString *)path
{
    const char *filename = path.lastPathComponent.UTF8String;
    char scanFormat[100];
    snprintf(scanFormat, sizeof(scanFormat), "%s-report-%%" PRIx64 ".json", self.appName.UTF8String);

    int64_t reportID = 0;
    sscanf(filename, scanFormat, &reportID);
    return reportID;
}

- (void)setUp
{
    [super setUp];
    self.appName = @"myapp";
}

- (void)prepareReportStoreWithPathEnd:(NSString *)pathEnd
{
    [self prepareReportStoreWithPathEnd:pathEnd maxReportCount:5];
}

- (void)prepareReportStoreWithPathEnd:(NSString *)pathEnd maxReportCount:(int)maxReportCount
{
    self.reportStorePath = [self.tempPath stringByAppendingPathComponent:pathEnd];
    _storeConfig.appName = self.appName.UTF8String;
    _storeConfig.reportsPath = self.reportStorePath.UTF8String;
    _storeConfig.maxReportCount = maxReportCount;
    kscrs_initialize(&_storeConfig);
}

- (void)prepareReportStoreWithSidecarsWithPathEnd:(NSString *)pathEnd
{
    self.reportStorePath = [self.tempPath stringByAppendingPathComponent:pathEnd];
    NSString *sidecarsPath = [self.tempPath stringByAppendingPathComponent:@"Sidecars"];
    _storeConfig.appName = self.appName.UTF8String;
    _storeConfig.reportsPath = self.reportStorePath.UTF8String;
    _storeConfig.sidecarsPath = sidecarsPath.UTF8String;
    _storeConfig.maxReportCount = 5;
    kscrs_initialize(&_storeConfig);
}

- (NSArray *)getReportIDs
{
    int reportCount = kscrs_getReportCount(&_storeConfig);
    int64_t rawReportIDs[reportCount];
    reportCount = kscrs_getReportIDs(rawReportIDs, reportCount, &_storeConfig);
    NSMutableArray *reportIDs = [NSMutableArray new];
    for (int i = 0; i < reportCount; i++) {
        [reportIDs addObject:@(rawReportIDs[i])];
    }
    return reportIDs;
}

- (int64_t)writeCrashReportWithStringContents:(NSString *)contents
{
    NSData *crashData = [contents dataUsingEncoding:NSUTF8StringEncoding];
    char crashReportPath[KSCRS_MAX_PATH_LENGTH];
    kscrs_getNextCrashReport(crashReportPath, &_storeConfig);
    [crashData writeToFile:[NSString stringWithUTF8String:crashReportPath] atomically:YES];
    return [self getReportIDFromPath:[NSString stringWithUTF8String:crashReportPath]];
}

- (int64_t)writeUserReportWithStringContents:(NSString *)contents
{
    NSData *data = [contents dataUsingEncoding:NSUTF8StringEncoding];
    return kscrs_addUserReport(data.bytes, (int)data.length, &_storeConfig);
}

- (void)loadReportID:(int64_t)reportID reportString:(NSString *__autoreleasing *)reportString
{
    char *reportBytes = kscrs_readReport(reportID, &_storeConfig);

    if (reportBytes == NULL) {
        reportString = nil;
    } else {
        *reportString = [[NSString alloc] initWithData:[NSData dataWithBytesNoCopy:reportBytes
                                                                            length:strlen(reportBytes)]
                                              encoding:NSUTF8StringEncoding];
    }
}

- (void)expectHasReportCount:(int)reportCount
{
    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), reportCount);
}

- (void)expectReports:(NSArray *)reportIDs areStrings:(NSArray *)reportStrings
{
    for (NSUInteger i = 0; i < reportIDs.count; i++) {
        int64_t reportID = [reportIDs[i] longLongValue];
        NSString *reportString = reportStrings[i];
        NSString *loadedReportString;
        [self loadReportID:reportID reportString:&loadedReportString];
        XCTAssertEqualObjects(loadedReportString, reportString);
    }
}

- (void)testReportStorePathExists
{
    [self prepareReportStoreWithPathEnd:@"somereports/blah/2/x"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:self.reportStorePath]);
}

- (void)testCrashReportCount1
{
    [self prepareReportStoreWithPathEnd:@"testCrashReportCount1"];
    [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];
    [self expectHasReportCount:1];
}

- (void)testStoresLoadsOneCrashReport
{
    [self prepareReportStoreWithPathEnd:@"testStoresLoadsOneCrashReport"];
    int64_t reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];
    [self expectReports:@[ @(reportID) ] areStrings:@[ REPORT_CONTENTS(0) ]];
}

- (void)testStoresLoadsOneUserReport
{
    [self prepareReportStoreWithPathEnd:@"testStoresLoadsOneUserReport"];
    int64_t reportID = [self writeUserReportWithStringContents:REPORT_CONTENTS(0)];
    [self expectReports:@[ @(reportID) ] areStrings:@[ REPORT_CONTENTS(0) ]];
}

- (void)testStoresLoadsMultipleReports
{
    [self prepareReportStoreWithPathEnd:@"testStoresLoadsMultipleReports"];
    NSMutableArray *reportIDs = [NSMutableArray new];
    NSArray *reportContents = @[ REPORT_CONTENTS(1), REPORT_CONTENTS(2), REPORT_CONTENTS(3), REPORT_CONTENTS(4) ];
    [reportIDs addObject:@([self writeCrashReportWithStringContents:reportContents[0]])];
    [reportIDs addObject:@([self writeUserReportWithStringContents:reportContents[1]])];
    [reportIDs addObject:@([self writeUserReportWithStringContents:reportContents[2]])];
    [reportIDs addObject:@([self writeCrashReportWithStringContents:reportContents[3]])];
    [self expectHasReportCount:4];
    [self expectReports:reportIDs areStrings:reportContents];
}

- (void)testDeleteAllReports
{
    [self prepareReportStoreWithPathEnd:@"testDeleteAllReports"];
    [self writeCrashReportWithStringContents:REPORT_CONTENTS(1)];
    [self writeUserReportWithStringContents:REPORT_CONTENTS(2)];
    [self writeUserReportWithStringContents:REPORT_CONTENTS(3)];
    [self writeCrashReportWithStringContents:REPORT_CONTENTS(4)];
    [self expectHasReportCount:4];
    kscrs_deleteAllReports(&_storeConfig);
    [self expectHasReportCount:0];
}

- (void)testPruneReports
{
    int reportStorePrunesTo = 7;
    [self prepareReportStoreWithPathEnd:@"testDeleteAllReports" maxReportCount:reportStorePrunesTo];
    int64_t prunedReportID = [self writeUserReportWithStringContents:@"u1"];
    [self writeCrashReportWithStringContents:REPORT_CONTENTS(c1)];
    [self writeUserReportWithStringContents:REPORT_CONTENTS(u2)];
    [self writeCrashReportWithStringContents:REPORT_CONTENTS(c2)];
    [self writeCrashReportWithStringContents:REPORT_CONTENTS(c3)];
    [self writeUserReportWithStringContents:REPORT_CONTENTS(u3)];
    [self writeCrashReportWithStringContents:REPORT_CONTENTS(c4)];
    [self writeCrashReportWithStringContents:REPORT_CONTENTS(c5)];
    [self expectHasReportCount:8];
    // Calls kscrs_initialize() again, which prunes the reports.
    [self prepareReportStoreWithPathEnd:@"testDeleteAllReports" maxReportCount:reportStorePrunesTo];
    [self expectHasReportCount:reportStorePrunesTo];
    NSArray *reportIDs = [self getReportIDs];
    XCTAssertFalse([reportIDs containsObject:@(prunedReportID)]);
}

- (void)testNextReportIDWhenEmpty
{
    [self prepareReportStoreWithPathEnd:@"testNextReportIDWhenEmpty"];
    [self expectHasReportCount:0];
    int64_t reportID;
    int count = kscrs_getReportIDs(&reportID, 1, &_storeConfig);
    XCTAssertEqual(count, 0);
}

- (void)testNextReportIDWithOneReport
{
    [self prepareReportStoreWithPathEnd:@"testNextReportIDWithOneReport"];
    int64_t writtenID = [self writeUserReportWithStringContents:REPORT_CONTENTS(0)];
    int64_t reportID;
    int count = kscrs_getReportIDs(&reportID, 1, &_storeConfig);
    XCTAssertEqual(count, 1);
    XCTAssertEqual(reportID, writtenID);
}

- (void)testGetReportIDsReturnsSorted
{
    [self prepareReportStoreWithPathEnd:@"testGetReportIDsReturnsSorted"];
    int64_t id1 = [self writeUserReportWithStringContents:REPORT_CONTENTS(1)];
    int64_t id2 = [self writeUserReportWithStringContents:REPORT_CONTENTS(2)];
    int64_t id3 = [self writeUserReportWithStringContents:REPORT_CONTENTS(3)];

    NSArray *reportIDs = [self getReportIDs];
    XCTAssertEqual(reportIDs.count, 3u);
    // IDs should be sorted ascending
    XCTAssertLessThan([reportIDs[0] longLongValue], [reportIDs[1] longLongValue]);
    XCTAssertLessThan([reportIDs[1] longLongValue], [reportIDs[2] longLongValue]);
    // All written IDs should be present
    NSSet *expected = [NSSet setWithArray:@[ @(id1), @(id2), @(id3) ]];
    NSSet *actual = [NSSet setWithArray:reportIDs];
    XCTAssertEqualObjects(expected, actual);
}

- (void)testGetReportIDsAfterDeletion
{
    [self prepareReportStoreWithPathEnd:@"testGetReportIDsAfterDeletion"];
    int64_t id1 = [self writeUserReportWithStringContents:REPORT_CONTENTS(1)];
    int64_t id2 = [self writeUserReportWithStringContents:REPORT_CONTENTS(2)];
    int64_t id3 = [self writeUserReportWithStringContents:REPORT_CONTENTS(3)];

    NSArray *reportIDs = [self getReportIDs];
    XCTAssertEqual(reportIDs.count, 3u);

    kscrs_deleteReportWithID(id1, &_storeConfig);
    reportIDs = [self getReportIDs];
    XCTAssertEqual(reportIDs.count, 2u);
    NSSet *expected = [NSSet setWithArray:@[ @(id2), @(id3) ]];
    NSSet *actual = [NSSet setWithArray:reportIDs];
    XCTAssertEqualObjects(expected, actual);
}

- (void)testNextReportIDAfterDeleteAll
{
    [self prepareReportStoreWithPathEnd:@"testNextReportIDAfterDeleteAll"];
    [self writeUserReportWithStringContents:REPORT_CONTENTS(1)];
    [self writeUserReportWithStringContents:REPORT_CONTENTS(2)];
    kscrs_deleteAllReports(&_storeConfig);
    int64_t reportID = -1;
    int count = kscrs_getReportIDs(&reportID, 1, &_storeConfig);
    XCTAssertEqual(count, 0);
}

- (void)testStoresLoadsWithUnicodeAppName
{
    self.appName = @"ЙогуртЙод";
    [self prepareReportStoreWithPathEnd:@"testStoresLoadsWithUnicodeAppName"];
    int64_t reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];
    [self expectReports:@[ @(reportID) ] areStrings:@[ REPORT_CONTENTS(0) ]];
}

#pragma mark - Sidecar Tests

- (void)testSidecarsDirectoryCreatedOnInitialize
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarsDir"];
    BOOL isDir = NO;
    BOOL exists =
        [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:_storeConfig.sidecarsPath]
                                             isDirectory:&isDir];
    XCTAssertTrue(exists);
    XCTAssertTrue(isDir);
}

- (void)testGetSidecarPath
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGetSidecarPath"];
    int64_t reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];

    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getSidecarFilePathForReport("TestMonitor", reportID, pathBuffer, sizeof(pathBuffer), &_storeConfig);
    XCTAssertTrue(result);

    NSString *path = [NSString stringWithUTF8String:pathBuffer];
    XCTAssertTrue([path containsString:@"Sidecars/TestMonitor/"]);
    XCTAssertTrue([path hasSuffix:@".ksscr"]);
}

- (void)testGetSidecarPathCreatesMonitorSubdirectory
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarSubdir"];

    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    kscrs_getSidecarFilePathForReport("MyMonitor", 12345, pathBuffer, sizeof(pathBuffer), &_storeConfig);

    NSString *monitorDir = [NSString stringWithFormat:@"%s/MyMonitor", _storeConfig.sidecarsPath];
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:monitorDir isDirectory:&isDir];
    XCTAssertTrue(exists);
    XCTAssertTrue(isDir);
}

- (void)testGetSidecarPathNullMonitorId
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarNull"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getSidecarFilePathForReport(NULL, 1, pathBuffer, sizeof(pathBuffer), &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetSidecarPathNullPathBuffer
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarNullBuf"];
    bool result = kscrs_getSidecarFilePathForReport("Mon", 1, NULL, 100, &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetSidecarPathZeroBufferLength
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarZeroBuf"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getSidecarFilePathForReport("Mon", 1, pathBuffer, 0, &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetSidecarPathBufferTooSmall
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarSmallBuf"];
    char pathBuffer[5];
    bool result = kscrs_getSidecarFilePathForReport("TestMonitor", 1, pathBuffer, sizeof(pathBuffer), &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetSidecarPathNullSidecarsPath
{
    [self prepareReportStoreWithPathEnd:@"testSidecarNoPath"];
    // _storeConfig.sidecarsPath is NULL
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getSidecarFilePathForReport("Mon", 1, pathBuffer, sizeof(pathBuffer), &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testDeleteReportAlsoDeletesSidecars
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testDeleteSidecars"];
    int64_t reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];

    // Create a sidecar file for this report
    char sidecarPath[KSCRS_MAX_PATH_LENGTH];
    kscrs_getSidecarFilePathForReport("TestMonitor", reportID, sidecarPath, sizeof(sidecarPath), &_storeConfig);
    [@"sidecar data" writeToFile:[NSString stringWithUTF8String:sidecarPath]
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:sidecarPath]]);

    // Delete the report
    kscrs_deleteReportWithID(reportID, &_storeConfig);

    // Sidecar should be gone
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:sidecarPath]]);
}

- (void)testDeleteReportDeletesSidecarsFromMultipleMonitors
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testDeleteMultiSidecars"];
    int64_t reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];

    // Create sidecars from two different monitors
    char sidecarPath1[KSCRS_MAX_PATH_LENGTH];
    char sidecarPath2[KSCRS_MAX_PATH_LENGTH];
    kscrs_getSidecarFilePathForReport("Monitor1", reportID, sidecarPath1, sizeof(sidecarPath1), &_storeConfig);
    kscrs_getSidecarFilePathForReport("Monitor2", reportID, sidecarPath2, sizeof(sidecarPath2), &_storeConfig);

    [@"data1" writeToFile:[NSString stringWithUTF8String:sidecarPath1]
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:nil];
    [@"data2" writeToFile:[NSString stringWithUTF8String:sidecarPath2]
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:nil];

    kscrs_deleteReportWithID(reportID, &_storeConfig);

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:sidecarPath1]]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:sidecarPath2]]);
}

- (void)testDeleteAllReportsAlsoDeletesSidecars
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testDeleteAllSidecars"];
    int64_t reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];

    char sidecarPath[KSCRS_MAX_PATH_LENGTH];
    kscrs_getSidecarFilePathForReport("TestMonitor", reportID, sidecarPath, sizeof(sidecarPath), &_storeConfig);
    [@"sidecar data" writeToFile:[NSString stringWithUTF8String:sidecarPath]
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];

    kscrs_deleteAllReports(&_storeConfig);

    [self expectHasReportCount:0];
    // The sidecars directory itself should exist but be empty
    NSString *sidecarsDir = [NSString stringWithUTF8String:_storeConfig.sidecarsPath];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:sidecarsDir error:nil];
    XCTAssertEqual(contents.count, 0u);
}

- (void)testGetSidecarPathConsistentForSameInput
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarConsistent"];
    char path1[KSCRS_MAX_PATH_LENGTH];
    char path2[KSCRS_MAX_PATH_LENGTH];
    kscrs_getSidecarFilePathForReport("Mon", 42, path1, sizeof(path1), &_storeConfig);
    kscrs_getSidecarFilePathForReport("Mon", 42, path2, sizeof(path2), &_storeConfig);
    XCTAssertEqual(strcmp(path1, path2), 0);
}

- (void)testGetSidecarPathDiffersForDifferentMonitors
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarDiffMon"];
    char path1[KSCRS_MAX_PATH_LENGTH];
    char path2[KSCRS_MAX_PATH_LENGTH];
    kscrs_getSidecarFilePathForReport("Mon1", 42, path1, sizeof(path1), &_storeConfig);
    kscrs_getSidecarFilePathForReport("Mon2", 42, path2, sizeof(path2), &_storeConfig);
    XCTAssertNotEqual(strcmp(path1, path2), 0);
}

- (void)testGetSidecarPathDiffersForDifferentReports
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarDiffReport"];
    char path1[KSCRS_MAX_PATH_LENGTH];
    char path2[KSCRS_MAX_PATH_LENGTH];
    kscrs_getSidecarFilePathForReport("Mon", 1, path1, sizeof(path1), &_storeConfig);
    kscrs_getSidecarFilePathForReport("Mon", 2, path2, sizeof(path2), &_storeConfig);
    XCTAssertNotEqual(strcmp(path1, path2), 0);
}

- (void)testDeleteReportWithNoSidecarsPathDoesNotCrash
{
    [self prepareReportStoreWithPathEnd:@"testDeleteNoSidecars"];
    int64_t reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];
    // sidecarsPath is NULL — should not crash
    kscrs_deleteReportWithID(reportID, &_storeConfig);
    [self expectHasReportCount:0];
}

- (void)testDeleteAllReportsWithNoSidecarsPathDoesNotCrash
{
    [self prepareReportStoreWithPathEnd:@"testDeleteAllNoSidecars"];
    [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];
    // sidecarsPath is NULL — should not crash
    kscrs_deleteAllReports(&_storeConfig);
    [self expectHasReportCount:0];
}

#pragma mark - Generic Sidecar File Path Tests (kscrs_getSidecarFilePath)

- (void)testGetSidecarFilePathReturnsValidPath
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarPath"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result =
        kscrs_getSidecarFilePath("TestMonitor", "myfile", "txt", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertTrue(result);
    XCTAssertTrue(strlen(pathBuffer) > 0);
    XCTAssertTrue(strstr(pathBuffer, "TestMonitor") != NULL, @"Path should contain monitor ID");
    XCTAssertTrue(strstr(pathBuffer, "myfile.txt") != NULL, @"Path should contain filename with extension");
}

- (void)testGetSidecarFilePathCreatesMonitorDirectory
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarDir"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    kscrs_getSidecarFilePath("NewMonitor", "test", "dat", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    // Extract directory from path and verify it exists
    NSString *path = [NSString stringWithUTF8String:pathBuffer];
    NSString *directory = [path stringByDeletingLastPathComponent];
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDir];
    XCTAssertTrue(exists && isDir, @"Monitor directory should be created");
}

- (void)testGetSidecarFilePathWithDifferentExtensions
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarExt"];
    char path1[KSCRS_MAX_PATH_LENGTH];
    char path2[KSCRS_MAX_PATH_LENGTH];

    kscrs_getSidecarFilePath("Mon", "file", "json", path1, sizeof(path1), &_storeConfig);
    kscrs_getSidecarFilePath("Mon", "file", "bin", path2, sizeof(path2), &_storeConfig);

    XCTAssertTrue(strstr(path1, ".json") != NULL);
    XCTAssertTrue(strstr(path2, ".bin") != NULL);
    XCTAssertNotEqual(strcmp(path1, path2), 0, @"Different extensions should produce different paths");
}

- (void)testGetSidecarFilePathWithDifferentNames
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarName"];
    char path1[KSCRS_MAX_PATH_LENGTH];
    char path2[KSCRS_MAX_PATH_LENGTH];

    kscrs_getSidecarFilePath("Mon", "alpha", "txt", path1, sizeof(path1), &_storeConfig);
    kscrs_getSidecarFilePath("Mon", "beta", "txt", path2, sizeof(path2), &_storeConfig);

    XCTAssertNotEqual(strcmp(path1, path2), 0, @"Different names should produce different paths");
}

- (void)testGetSidecarFilePathWithNullMonitorId
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarNullMon"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getSidecarFilePath(NULL, "file", "txt", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithNullName
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarNullName"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getSidecarFilePath("Mon", NULL, "txt", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithNullExtension
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarNullExt"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getSidecarFilePath("Mon", "file", NULL, pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithNullBuffer
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarNullBuf"];
    bool result = kscrs_getSidecarFilePath("Mon", "file", "txt", NULL, 100, &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithZeroBufferLength
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarZeroBuf"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getSidecarFilePath("Mon", "file", "txt", pathBuffer, 0, &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithNoSidecarsPath
{
    [self prepareReportStoreWithPathEnd:@"testGenericSidecarNoPath"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getSidecarFilePath("Mon", "file", "txt", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertFalse(result, @"Should fail when sidecarsPath is NULL");
}

- (void)testGetSidecarFilePathHexHashName
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarHash"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    // Simulate how MetricKit uses it with hex hash as name
    bool result =
        kscrs_getSidecarFilePath("MetricKit", "0123456789abcdef", "stacksym", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertTrue(result);
    XCTAssertTrue(strstr(pathBuffer, "MetricKit") != NULL);
    XCTAssertTrue(strstr(pathBuffer, "0123456789abcdef.stacksym") != NULL);
}

@end
