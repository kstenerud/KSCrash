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
#import "KSID.h"

#include <inttypes.h>

#define REPORT_PREFIX @"CrashReport-KSCrashTest"
#define REPORT_CONTENTS(NUM) @"{\n    \"a\": \"" #NUM "\"\n}"

@interface KSCrashReportStoreC_Tests : FileBasedTestCase

@property(nonatomic, readwrite, copy) NSString *reportStorePath;

@end

@implementation KSCrashReportStoreC_Tests {
    KSCrashReportStoreCConfiguration _storeConfig;
}

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    kscrs_setStitchConfig(NULL);
    [super tearDown];
}

- (void)prepareReportStoreWithPathEnd:(NSString *)pathEnd
{
    [self prepareReportStoreWithPathEnd:pathEnd maxReportCount:5];
}

- (void)prepareReportStoreWithPathEnd:(NSString *)pathEnd maxReportCount:(int)maxReportCount
{
    self.reportStorePath = [self.tempPath stringByAppendingPathComponent:pathEnd];
    _storeConfig.reportsPath = self.reportStorePath.UTF8String;
    _storeConfig.maxReportCount = maxReportCount;
    kscrs_initialize(&_storeConfig);
    kscrs_setStitchConfig(&_storeConfig);
}

- (void)prepareReportStoreWithSidecarsWithPathEnd:(NSString *)pathEnd
{
    self.reportStorePath = [self.tempPath stringByAppendingPathComponent:pathEnd];
    NSString *sidecarsPath = [self.tempPath stringByAppendingPathComponent:@"Sidecars"];
    _storeConfig.reportsPath = self.reportStorePath.UTF8String;
    _storeConfig.reportSidecarsPath = sidecarsPath.UTF8String;
    _storeConfig.maxReportCount = 5;
    kscrs_initialize(&_storeConfig);
    kscrs_setStitchConfig(&_storeConfig);
}

/** The store's report ids in name order (oldest first), read from the
 *  directory the way the Swift store reads it. */
- (NSArray<NSString *> *)getReportIDs
{
    // A comparator block, not @selector(compare:): under Mac Catalyst both
    // UIKit and AppKit expose compare: with mismatched types, and the strict
    // selector match is a compile error there.
    NSArray<NSString *> *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.reportStorePath
                                                                                      error:nil]
        sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [a compare:b];
        }];
    NSMutableArray *reportIDs = [NSMutableArray new];
    NSString *suffix = @"." KSCRS_REPORT_FILENAME_EXTENSION;
    for (NSString *name in names) {
        NSUInteger expected = KSCRS_REPORT_NAME_DIGITS + 1 + KSCRS_REPORT_ID_LENGTH + suffix.length;
        if (name.length != expected || ![name hasSuffix:suffix]) {
            continue;
        }
        NSString *reportID =
            [name substringWithRange:NSMakeRange(KSCRS_REPORT_NAME_DIGITS + 1, KSCRS_REPORT_ID_LENGTH)];
        if (ksid_isValid(reportID.UTF8String)) {
            [reportIDs addObject:reportID];
        }
    }
    return reportIDs;
}

/** Writes `contents` the way the crash handler does: a minted id names the file and nothing is injected. */
- (NSString *)writeCrashReportWithStringContents:(NSString *)contents
{
    NSData *crashData = [contents dataUsingEncoding:NSUTF8StringEncoding];
    char reportID[KSID_SIZE];
    ksid_generate(reportID);
    char crashReportPath[KSCRS_MAX_PATH_LENGTH];
    kscrs_getNextCrashReport(reportID, crashReportPath, &_storeConfig);
    [crashData writeToFile:[NSString stringWithUTF8String:crashReportPath] atomically:YES];
    return @(reportID);
}

- (NSString *)writeUserReportWithStringContents:(NSString *)contents
{
    NSData *data = [contents dataUsingEncoding:NSUTF8StringEncoding];
    char reportID[KSID_SIZE];
    XCTAssertTrue(kscrs_addUserReport(data.bytes, (int)data.length, &_storeConfig, reportID));
    return @(reportID);
}

- (void)loadReportID:(NSString *)reportID reportString:(NSString *__autoreleasing *)reportString
{
    char *reportBytes = kscrs_readReport(reportID.UTF8String, &_storeConfig, NULL);
    if (reportBytes == NULL) {
        *reportString = nil;
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

/** The stored reports, compared as JSON. A user report without a report.id
 *  had one injected by the store, so that key is ignored when the fixture
 *  did not carry a report section. */
- (void)expectReports:(NSArray<NSString *> *)reportIDs areStrings:(NSArray *)reportStrings
{
    for (NSUInteger i = 0; i < reportIDs.count; i++) {
        NSString *loadedReportString;
        [self loadReportID:reportIDs[i] reportString:&loadedReportString];
        NSMutableDictionary *loaded =
            [[NSJSONSerialization JSONObjectWithData:[loadedReportString dataUsingEncoding:NSUTF8StringEncoding]
                                             options:0
                                               error:nil] mutableCopy];
        NSDictionary *expected =
            [NSJSONSerialization JSONObjectWithData:[reportStrings[i] dataUsingEncoding:NSUTF8StringEncoding]
                                            options:0
                                              error:nil];
        if (expected[@"report"] == nil) {
            [loaded removeObjectForKey:@"report"];
        }
        XCTAssertEqualObjects(loaded, expected);
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
    NSString *reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];
    [self expectReports:@[ reportID ] areStrings:@[ REPORT_CONTENTS(0) ]];
}

- (void)testStoresLoadsOneUserReport
{
    [self prepareReportStoreWithPathEnd:@"testStoresLoadsOneUserReport"];
    NSString *reportID = [self writeUserReportWithStringContents:REPORT_CONTENTS(0)];
    [self expectReports:@[ reportID ] areStrings:@[ REPORT_CONTENTS(0) ]];
}

- (void)testStoresLoadsMultipleReports
{
    [self prepareReportStoreWithPathEnd:@"testStoresLoadsMultipleReports"];
    NSMutableArray *reportIDs = [NSMutableArray new];
    NSArray *reportContents = @[ REPORT_CONTENTS(1), REPORT_CONTENTS(2), REPORT_CONTENTS(3), REPORT_CONTENTS(4) ];
    [reportIDs addObject:[self writeCrashReportWithStringContents:reportContents[0]]];
    [reportIDs addObject:[self writeUserReportWithStringContents:reportContents[1]]];
    [reportIDs addObject:[self writeUserReportWithStringContents:reportContents[2]]];
    [reportIDs addObject:[self writeCrashReportWithStringContents:reportContents[3]]];
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
    NSString *prunedReportID = [self writeUserReportWithStringContents:@"u1"];
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
    XCTAssertFalse([reportIDs containsObject:prunedReportID]);
}

- (void)testGetReportIDsWhenEmpty
{
    [self prepareReportStoreWithPathEnd:@"testGetReportIDsWhenEmpty"];
    [self expectHasReportCount:0];
    XCTAssertEqualObjects([self getReportIDs], @[]);
}

// Names carry the write time, and within a process they are strictly
// increasing even when the clock repeats, so write order is sort order.
- (void)testCrashReportNamesIncreaseWithinAProcess
{
    [self prepareReportStoreWithPathEnd:@"testCrashReportNamesIncrease"];
    char first[KSCRS_MAX_PATH_LENGTH];
    char second[KSCRS_MAX_PATH_LENGTH];
    kscrs_getNextCrashReport("4C1B2F3E-0000-4000-8000-000000000001", first, &_storeConfig);
    kscrs_getNextCrashReport("4C1B2F3E-0000-4000-8000-000000000002", second, &_storeConfig);
    XCTAssertLessThan(strcmp(first, second), 0);
    NSString *name = [[NSString stringWithUTF8String:first] lastPathComponent];
    XCTAssertTrue([name hasSuffix:@"-4C1B2F3E-0000-4000-8000-000000000001.json"]);
    XCTAssertEqual([name rangeOfString:@"-"].location, 20u, @"twenty decimal digits of wall-clock nanoseconds");
}

- (void)testGetReportIDsWithOneReport
{
    [self prepareReportStoreWithPathEnd:@"testGetReportIDsWithOneReport"];
    NSString *writtenID = [self writeUserReportWithStringContents:REPORT_CONTENTS(0)];
    [self expectHasReportCount:1];
    XCTAssertEqualObjects([self getReportIDs], @[ writtenID ]);
}

- (void)testGetReportIDsReturnsOldestFirst
{
    [self prepareReportStoreWithPathEnd:@"testGetReportIDsReturnsOldestFirst"];
    NSString *id1 = [self writeUserReportWithStringContents:REPORT_CONTENTS(1)];
    NSString *id2 = [self writeCrashReportWithStringContents:REPORT_CONTENTS(2)];
    NSString *id3 = [self writeUserReportWithStringContents:REPORT_CONTENTS(3)];
    XCTAssertEqualObjects([self getReportIDs], (@[ id1, id2, id3 ]));
}

- (void)testFilesThatAreNotReportsAreNotListed
{
    [self prepareReportStoreWithPathEnd:@"testNotReports"];
    NSString *only = [self writeUserReportWithStringContents:REPORT_CONTENTS(1)];
    for (NSString *name in @[
             @"notes.txt", @"00000000000000000001-nope.json", @"1-4C1B2F3E-0000-4000-8000-000000000001.json",
             @"00000000000000000001-4c1b2f3e-0000-4000-8000-000000000001.json",
             @"00000000000000000001-4C1B2F3E-0000-4000-8000-000000000001.json.tmp"
         ]) {
        [[NSData data] writeToFile:[self.reportStorePath stringByAppendingPathComponent:name] atomically:YES];
    }
    XCTAssertEqualObjects([self getReportIDs], @[ only ]);
    [self expectHasReportCount:1];
}

- (void)testGetReportIDsAfterDeletion
{
    [self prepareReportStoreWithPathEnd:@"testGetReportIDsAfterDeletion"];
    NSString *id1 = [self writeUserReportWithStringContents:REPORT_CONTENTS(1)];
    NSString *id2 = [self writeUserReportWithStringContents:REPORT_CONTENTS(2)];
    NSString *id3 = [self writeUserReportWithStringContents:REPORT_CONTENTS(3)];
    XCTAssertEqual([self getReportIDs].count, 3u);
    kscrs_deleteReportWithID(id1.UTF8String, &_storeConfig);
    XCTAssertEqualObjects([self getReportIDs], (@[ id2, id3 ]));
}

- (void)testGetReportIDsAfterDeleteAll
{
    [self prepareReportStoreWithPathEnd:@"testGetReportIDsAfterDeleteAll"];
    [self writeUserReportWithStringContents:REPORT_CONTENTS(1)];
    [self writeUserReportWithStringContents:REPORT_CONTENTS(2)];
    kscrs_deleteAllReports(&_storeConfig);
    [self expectHasReportCount:0];
    XCTAssertEqualObjects([self getReportIDs], @[]);
}

- (void)testAddUserReportKeepsAValidIDAndMintsOneOtherwise
{
    [self prepareReportStoreWithPathEnd:@"testAddUserReportIDs"];
    NSString *kept =
        [self writeUserReportWithStringContents:@"{\"report\":{\"id\":\"4C1B2F3E-0000-4000-8000-000000000009\"}}"];
    XCTAssertEqualObjects(kept, @"4C1B2F3E-0000-4000-8000-000000000009");
    NSString *minted = [self writeUserReportWithStringContents:@"{\"report\":{\"id\":\"evt1\"},\"a\":1}"];
    XCTAssertTrue(ksid_isValid(minted.UTF8String));
    NSString *loaded;
    [self loadReportID:minted reportString:&loaded];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[loaded dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:0
                                                           error:nil];
    XCTAssertEqualObjects(json[@"report"][@"id"], minted, @"the minted id is written into the payload");
    XCTAssertEqualObjects(json[@"a"], @1);
}

- (void)testAddUserReportWithTheSameIDOverwrites
{
    [self prepareReportStoreWithPathEnd:@"testAddUserReportSameID"];
    NSString *json = @"{\"report\":{\"id\":\"4C1B2F3E-0000-4000-8000-00000000000A\"},\"v\":1}";
    NSString *first = [self writeUserReportWithStringContents:json];
    NSString *again = [self
        writeUserReportWithStringContents:@"{\"report\":{\"id\":\"4C1B2F3E-0000-4000-8000-00000000000A\"},\"v\":2}"];
    XCTAssertEqualObjects(first, again);
    XCTAssertEqual((int)[self getReportIDs].count, 1, @"one id is one file");

    NSString *loaded;
    [self loadReportID:first reportString:&loaded];
    XCTAssertTrue([loaded containsString:@"\"v\": 2"] || [loaded containsString:@"\"v\":2"],
                  @"the re-add replaced the payload");
}

- (void)testStoresLoadsWithUnicodePath
{
    [self prepareReportStoreWithPathEnd:@"ЙогуртЙод"];
    NSString *reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];
    [self expectReports:@[ reportID ] areStrings:@[ REPORT_CONTENTS(0) ]];
}

#pragma mark - Sidecar Tests

- (void)testSidecarsDirectoryCreatedOnInitialize
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarsDir"];
    BOOL isDir = NO;
    BOOL exists =
        [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:_storeConfig.reportSidecarsPath]
                                             isDirectory:&isDir];
    XCTAssertTrue(exists);
    XCTAssertTrue(isDir);
}

- (void)testGetSidecarPath
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGetSidecarPath"];
    NSString *reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];

    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getReportSidecarFilePathForReport("TestMonitor", reportID.UTF8String, pathBuffer,
                                                          sizeof(pathBuffer), &_storeConfig);
    XCTAssertTrue(result);

    NSString *path = [NSString stringWithUTF8String:pathBuffer];
    XCTAssertTrue([path containsString:@"Sidecars/TestMonitor/"]);
    XCTAssertTrue([path hasSuffix:@".ksscr"]);
}

- (void)testGetSidecarPathCreatesMonitorSubdirectory
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarSubdir"];

    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    kscrs_getReportSidecarFilePathForReport("MyMonitor", "4C1B2F3E-0000-4000-8000-000000012345", pathBuffer,
                                            sizeof(pathBuffer), &_storeConfig);

    NSString *monitorDir = [NSString stringWithFormat:@"%s/MyMonitor", _storeConfig.reportSidecarsPath];
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:monitorDir isDirectory:&isDir];
    XCTAssertTrue(exists);
    XCTAssertTrue(isDir);
}

- (void)testGetSidecarPathNullMonitorId
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarNull"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getReportSidecarFilePathForReport(NULL, "4C1B2F3E-0000-4000-8000-000000000001", pathBuffer,
                                                          sizeof(pathBuffer), &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetSidecarPathNullPathBuffer
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarNullBuf"];
    bool result = kscrs_getReportSidecarFilePathForReport("Mon", "4C1B2F3E-0000-4000-8000-000000000001", NULL, 100,
                                                          &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetSidecarPathZeroBufferLength
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarZeroBuf"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getReportSidecarFilePathForReport("Mon", "4C1B2F3E-0000-4000-8000-000000000001", pathBuffer, 0,
                                                          &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetSidecarPathBufferTooSmall
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarSmallBuf"];
    char pathBuffer[5];
    bool result = kscrs_getReportSidecarFilePathForReport("TestMonitor", "4C1B2F3E-0000-4000-8000-000000000001",
                                                          pathBuffer, sizeof(pathBuffer), &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testGetSidecarPathNullSidecarsPath
{
    [self prepareReportStoreWithPathEnd:@"testSidecarNoPath"];
    // _storeConfig.reportSidecarsPath is NULL
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getReportSidecarFilePathForReport("Mon", "4C1B2F3E-0000-4000-8000-000000000001", pathBuffer,
                                                          sizeof(pathBuffer), &_storeConfig);
    XCTAssertFalse(result);
}

- (void)testDeleteReportAlsoDeletesSidecars
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testDeleteSidecars"];
    NSString *reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];

    // Create a sidecar file for this report
    char sidecarPath[KSCRS_MAX_PATH_LENGTH];
    kscrs_getReportSidecarFilePathForReport("TestMonitor", reportID.UTF8String, sidecarPath, sizeof(sidecarPath),
                                            &_storeConfig);
    [@"sidecar data" writeToFile:[NSString stringWithUTF8String:sidecarPath]
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:sidecarPath]]);

    // Delete the report
    kscrs_deleteReportWithID(reportID.UTF8String, &_storeConfig);

    // Sidecar should be gone
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:sidecarPath]]);
}

- (void)testDeleteReportDeletesSidecarsFromMultipleMonitors
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testDeleteMultiSidecars"];
    NSString *reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];

    // Create sidecars from two different monitors
    char sidecarPath1[KSCRS_MAX_PATH_LENGTH];
    char sidecarPath2[KSCRS_MAX_PATH_LENGTH];
    kscrs_getReportSidecarFilePathForReport("Monitor1", reportID.UTF8String, sidecarPath1, sizeof(sidecarPath1),
                                            &_storeConfig);
    kscrs_getReportSidecarFilePathForReport("Monitor2", reportID.UTF8String, sidecarPath2, sizeof(sidecarPath2),
                                            &_storeConfig);

    [@"data1" writeToFile:[NSString stringWithUTF8String:sidecarPath1]
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:nil];
    [@"data2" writeToFile:[NSString stringWithUTF8String:sidecarPath2]
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:nil];

    kscrs_deleteReportWithID(reportID.UTF8String, &_storeConfig);

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:sidecarPath1]]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithUTF8String:sidecarPath2]]);
}

- (void)testDeleteAllReportsAlsoDeletesSidecars
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testDeleteAllSidecars"];
    NSString *reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];

    char sidecarPath[KSCRS_MAX_PATH_LENGTH];
    kscrs_getReportSidecarFilePathForReport("TestMonitor", reportID.UTF8String, sidecarPath, sizeof(sidecarPath),
                                            &_storeConfig);
    [@"sidecar data" writeToFile:[NSString stringWithUTF8String:sidecarPath]
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil];

    kscrs_deleteAllReports(&_storeConfig);

    [self expectHasReportCount:0];
    // The sidecars directory itself should exist but be empty
    NSString *sidecarsDir = [NSString stringWithUTF8String:_storeConfig.reportSidecarsPath];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:sidecarsDir error:nil];
    XCTAssertEqual(contents.count, 0u);
}

- (void)testGetSidecarPathConsistentForSameInput
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarConsistent"];
    char path1[KSCRS_MAX_PATH_LENGTH];
    char path2[KSCRS_MAX_PATH_LENGTH];
    kscrs_getReportSidecarFilePathForReport("Mon", "4C1B2F3E-0000-4000-8000-000000000042", path1, sizeof(path1),
                                            &_storeConfig);
    kscrs_getReportSidecarFilePathForReport("Mon", "4C1B2F3E-0000-4000-8000-000000000042", path2, sizeof(path2),
                                            &_storeConfig);
    XCTAssertEqual(strcmp(path1, path2), 0);
}

- (void)testGetSidecarPathDiffersForDifferentMonitors
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarDiffMon"];
    char path1[KSCRS_MAX_PATH_LENGTH];
    char path2[KSCRS_MAX_PATH_LENGTH];
    kscrs_getReportSidecarFilePathForReport("Mon1", "4C1B2F3E-0000-4000-8000-000000000042", path1, sizeof(path1),
                                            &_storeConfig);
    kscrs_getReportSidecarFilePathForReport("Mon2", "4C1B2F3E-0000-4000-8000-000000000042", path2, sizeof(path2),
                                            &_storeConfig);
    XCTAssertNotEqual(strcmp(path1, path2), 0);
}

- (void)testGetSidecarPathDiffersForDifferentReports
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testSidecarDiffReport"];
    char path1[KSCRS_MAX_PATH_LENGTH];
    char path2[KSCRS_MAX_PATH_LENGTH];
    kscrs_getReportSidecarFilePathForReport("Mon", "4C1B2F3E-0000-4000-8000-000000000001", path1, sizeof(path1),
                                            &_storeConfig);
    kscrs_getReportSidecarFilePathForReport("Mon", "4C1B2F3E-0000-4000-8000-000000000002", path2, sizeof(path2),
                                            &_storeConfig);
    XCTAssertNotEqual(strcmp(path1, path2), 0);
}

- (void)testDeleteReportWithNoSidecarsPathDoesNotCrash
{
    [self prepareReportStoreWithPathEnd:@"testDeleteNoSidecars"];
    NSString *reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];
    // sidecarsPath is NULL — should not crash
    kscrs_deleteReportWithID(reportID.UTF8String, &_storeConfig);
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

#pragma mark - Generic Sidecar File Path Tests (kscrs_getReportSidecarFilePath)

- (void)testGetSidecarFilePathReturnsValidPath
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarPath"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result =
        kscrs_getReportSidecarFilePath("TestMonitor", "myfile", "txt", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertTrue(result);
    XCTAssertTrue(strlen(pathBuffer) > 0);
    XCTAssertTrue(strstr(pathBuffer, "TestMonitor") != NULL, @"Path should contain monitor ID");
    XCTAssertTrue(strstr(pathBuffer, "myfile.txt") != NULL, @"Path should contain filename with extension");
}

- (void)testGetSidecarFilePathCreatesMonitorDirectory
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarDir"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    kscrs_getReportSidecarFilePath("NewMonitor", "test", "dat", pathBuffer, sizeof(pathBuffer), &_storeConfig);

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

    kscrs_getReportSidecarFilePath("Mon", "file", "json", path1, sizeof(path1), &_storeConfig);
    kscrs_getReportSidecarFilePath("Mon", "file", "bin", path2, sizeof(path2), &_storeConfig);

    XCTAssertTrue(strstr(path1, ".json") != NULL);
    XCTAssertTrue(strstr(path2, ".bin") != NULL);
    XCTAssertNotEqual(strcmp(path1, path2), 0, @"Different extensions should produce different paths");
}

- (void)testGetSidecarFilePathWithDifferentNames
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarName"];
    char path1[KSCRS_MAX_PATH_LENGTH];
    char path2[KSCRS_MAX_PATH_LENGTH];

    kscrs_getReportSidecarFilePath("Mon", "alpha", "txt", path1, sizeof(path1), &_storeConfig);
    kscrs_getReportSidecarFilePath("Mon", "beta", "txt", path2, sizeof(path2), &_storeConfig);

    XCTAssertNotEqual(strcmp(path1, path2), 0, @"Different names should produce different paths");
}

- (void)testGetSidecarFilePathWithNullMonitorId
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarNullMon"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getReportSidecarFilePath(NULL, "file", "txt", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithNullName
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarNullName"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getReportSidecarFilePath("Mon", NULL, "txt", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithNullExtension
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarNullExt"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getReportSidecarFilePath("Mon", "file", NULL, pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithNullBuffer
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarNullBuf"];
    bool result = kscrs_getReportSidecarFilePath("Mon", "file", "txt", NULL, 100, &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithZeroBufferLength
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarZeroBuf"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getReportSidecarFilePath("Mon", "file", "txt", pathBuffer, 0, &_storeConfig);

    XCTAssertFalse(result);
}

- (void)testGetSidecarFilePathWithNoSidecarsPath
{
    [self prepareReportStoreWithPathEnd:@"testGenericSidecarNoPath"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    bool result = kscrs_getReportSidecarFilePath("Mon", "file", "txt", pathBuffer, sizeof(pathBuffer), &_storeConfig);

    XCTAssertFalse(result, @"Should fail when sidecarsPath is NULL");
}

- (void)testGetSidecarFilePathHexHashName
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testGenericSidecarHash"];
    char pathBuffer[KSCRS_MAX_PATH_LENGTH];
    // Simulate how MetricKit uses it with hex hash as name
    bool result = kscrs_getReportSidecarFilePath("MetricKit", "0123456789abcdef", "stacksym", pathBuffer,
                                                 sizeof(pathBuffer), &_storeConfig);

    XCTAssertTrue(result);
    XCTAssertTrue(strstr(pathBuffer, "MetricKit") != NULL);
    XCTAssertTrue(strstr(pathBuffer, "0123456789abcdef.stacksym") != NULL);
}

#pragma mark - Malformed Report Section

- (void)testReadReportStatusOKForAReport
{
    [self prepareReportStoreWithPathEnd:@"testReadStatusOK"];
    NSString *reportID = [self writeUserReportWithStringContents:REPORT_CONTENTS(0)];

    KSCrashReportReadStatus status = KSCrashReportReadStatusUnreadable;
    char *report = kscrs_readReport(reportID.UTF8String, &_storeConfig, &status);
    XCTAssertTrue(report != NULL);
    XCTAssertEqual(status, KSCrashReportReadStatusOK);
    free(report);
}

- (void)testReadReportStatusUnreadableForAMissingReport
{
    [self prepareReportStoreWithPathEnd:@"testReadStatusUnreadable"];

    KSCrashReportReadStatus status = KSCrashReportReadStatusOK;
    char *report = kscrs_readReport("4C1B2F3E-0000-4000-8000-000000012345", &_storeConfig, &status);
    XCTAssertTrue(report == NULL);
    XCTAssertEqual(status, KSCrashReportReadStatusUnreadable);
}

- (void)testReadReportStatusUndecodableForANonObjectReport
{
    [self prepareReportStoreWithPathEnd:@"testReadStatusUndecodable"];
    NSString *arrayID = [self writeUserReportWithStringContents:@"[1,2]"];
    NSString *emptyID = [self writeUserReportWithStringContents:@""];

    KSCrashReportReadStatus status = KSCrashReportReadStatusOK;
    XCTAssertTrue(kscrs_readReport(arrayID.UTF8String, &_storeConfig, &status) == NULL);
    XCTAssertEqual(status, KSCrashReportReadStatusUndecodable);

    status = KSCrashReportReadStatusOK;
    XCTAssertTrue(kscrs_readReport(emptyID.UTF8String, &_storeConfig, &status) == NULL);
    XCTAssertEqual(status, KSCrashReportReadStatusUndecodable);

    // A status of NULL is allowed.
    XCTAssertTrue(kscrs_readReport(arrayID.UTF8String, &_storeConfig, NULL) == NULL);
}

- (void)testCopyReportRunIDAnswersFromTheReportFile
{
    [self prepareReportStoreWithPathEnd:@"testCopyRunID"];
    NSString *reportID =
        [self writeUserReportWithStringContents:@"{\"report\":{\"run_id\":\"0155A1E2-D4C3-4B6A-9C8D-1234567890AB\"}}"];

    char *runID = kscrs_copyReportRunID(reportID.UTF8String, &_storeConfig);
    XCTAssertTrue(runID != NULL);
    XCTAssertEqual(strcmp(runID, "0155A1E2-D4C3-4B6A-9C8D-1234567890AB"), 0);
    free(runID);

    // Absent, non-UUID, and missing are all "no run".
    NSString *noRunID = [self writeUserReportWithStringContents:@"{\"report\":{}}"];
    XCTAssertTrue(kscrs_copyReportRunID(noRunID.UTF8String, &_storeConfig) == NULL);
    NSString *badRunID = [self writeUserReportWithStringContents:@"{\"report\":{\"run_id\":\"RUN-A\"}}"];
    XCTAssertTrue(kscrs_copyReportRunID(badRunID.UTF8String, &_storeConfig) == NULL);
    XCTAssertTrue(kscrs_copyReportRunID("4C1B2F3E-0000-4000-8000-000000012345", &_storeConfig) == NULL);
}

- (void)testCopyReportRunIDSurvivesATornReport
{
    [self prepareReportStoreWithPathEnd:@"testCopyRunIDTorn"];
    // Torn mid-write: the extraction stops at run_id, before the tear.
    NSString *reportID =
        [self writeUserReportWithStringContents:
                  @"{\"report\":{\"run_id\":\"0155A1E2-D4C3-4B6A-9C8D-1234567890AB\"},\"crash\":{\"threads\":"];

    char *runID = kscrs_copyReportRunID(reportID.UTF8String, &_storeConfig);
    XCTAssertTrue(runID != NULL);
    XCTAssertEqual(strcmp(runID, "0155A1E2-D4C3-4B6A-9C8D-1234567890AB"), 0);
    free(runID);
}

- (void)testGetReportCountReturnsMinusOneWhenTheDirectoryCannotBeEnumerated
{
    [self prepareReportStoreWithPathEnd:@"testEnumFailure"];
    // Replace the reports directory with a plain file: opendir now fails with
    // ENOTDIR, the not-ENOENT case the -1 contract covers.
    NSString *path = self.reportStorePath;
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:NULL]);
    XCTAssertTrue([[NSData data] writeToFile:path atomically:YES]);

    XCTAssertEqual(kscrs_getReportCount(&_storeConfig), -1);
}

- (void)testDeleteReportKeepsSidecarsWhileTheReportFileRemains
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testDeleteKeepsSidecars"];
    NSString *reportID = [self writeUserReportWithStringContents:REPORT_CONTENTS(0)];
    char sidecarPath[KSCRS_MAX_PATH_LENGTH];
    XCTAssertTrue(kscrs_getReportSidecarFilePathForReport("TestMonitor", reportID.UTF8String, sidecarPath,
                                                          sizeof(sidecarPath), &_storeConfig));
    XCTAssertTrue([@"data" writeToFile:@(sidecarPath) atomically:YES encoding:NSUTF8StringEncoding error:nil]);

    // An undeletable report file will be re-sent, and that delivery needs
    // the sidecars for the on-read stitch.
    NSFileManager *fm = NSFileManager.defaultManager;
    XCTAssertTrue([fm setAttributes:@{ NSFilePosixPermissions : @(0555) } ofItemAtPath:self.reportStorePath error:nil]);
    XCTAssertFalse(kscrs_deleteReportWithID(reportID.UTF8String, &_storeConfig));
    XCTAssertTrue([fm setAttributes:@{ NSFilePosixPermissions : @(0755) } ofItemAtPath:self.reportStorePath error:nil]);
    XCTAssertTrue([fm fileExistsAtPath:@(sidecarPath)]);

    XCTAssertTrue(kscrs_deleteReportWithID(reportID.UTF8String, &_storeConfig));
    XCTAssertFalse([fm fileExistsAtPath:@(sidecarPath)]);
}

- (void)testDeleteMissingReportStillDeletesItsSidecars
{
    [self prepareReportStoreWithSidecarsWithPathEnd:@"testDeleteMissingCleansSidecars"];
    char sidecarPath[KSCRS_MAX_PATH_LENGTH];
    XCTAssertTrue(kscrs_getReportSidecarFilePathForReport("TestMonitor", "4C1B2F3E-0000-4000-8000-000000424242",
                                                          sidecarPath, sizeof(sidecarPath), &_storeConfig));
    XCTAssertTrue([@"data" writeToFile:@(sidecarPath) atomically:YES encoding:NSUTF8StringEncoding error:nil]);

    // The report file is already gone, so its sidecars are orphans: nothing
    // else sweeps per-report sidecars, so the delete removes them.
    XCTAssertFalse(kscrs_deleteReportWithID("4C1B2F3E-0000-4000-8000-000000424242", &_storeConfig));
    XCTAssertFalse([NSFileManager.defaultManager fileExistsAtPath:@(sidecarPath)]);
}

- (void)testDeleteReportWithIDReturnsWhetherTheFileWasRemoved
{
    [self prepareReportStoreWithPathEnd:@"testDeleteResult"];
    NSString *reportID = [self writeUserReportWithStringContents:REPORT_CONTENTS(0)];

    XCTAssertTrue(kscrs_deleteReportWithID(reportID.UTF8String, &_storeConfig));
    XCTAssertFalse(kscrs_deleteReportWithID(reportID.UTF8String, &_storeConfig), @"Already deleted");
    XCTAssertFalse(kscrs_deleteReportWithID("4C1B2F3E-0000-4000-8000-000000012345", &_storeConfig), @"Never existed");
}

- (void)testAddUserReportCanonicalizesALowercaseID
{
    [self prepareReportStoreWithPathEnd:@"testLowercaseID"];
    NSString *json = @"{\"report\":{\"id\":\"0badc0de-dead-beef-f00d-0123456789ab\"},\"crash\":{}}";
    char reportIDBuffer[KSID_SIZE];
    XCTAssertTrue(kscrs_addUserReport(json.UTF8String, (int)json.length, &_storeConfig, reportIDBuffer));
    XCTAssertEqualObjects(@(reportIDBuffer), @"0BADC0DE-DEAD-BEEF-F00D-0123456789AB",
                          @"the accepted id is canonicalized to the store's grammar");

    // The canonical id is the store identity: the file is findable by it, and
    // the payload's report.id was rewritten to match its filename.
    char *report = kscrs_readReport(reportIDBuffer, &_storeConfig, NULL);
    XCTAssertTrue(report != NULL);
    XCTAssertTrue(strstr(report, "0BADC0DE-DEAD-BEEF-F00D-0123456789AB") != NULL);
    XCTAssertTrue(strstr(report, "0badc0de-dead-beef-f00d-0123456789ab") == NULL);
    free(report);
}

- (void)testReadReportWithReportSectionAsString
{
    [self prepareReportStoreWithPathEnd:@"testMalformedReportString"];
    NSString *json = @"{\"report\":\"not a dict\",\"crash\":{}}";
    char reportIDBuffer[KSID_SIZE];
    XCTAssertTrue(kscrs_addUserReport(json.UTF8String, (int)json.length, &_storeConfig, reportIDBuffer));
    NSString *reportID = @(reportIDBuffer);

    char *report = kscrs_readReport(reportID.UTF8String, &_storeConfig, NULL);
    XCTAssertTrue(report != NULL, @"Should not crash on report section being a string");
    free(report);
}

- (void)testReadReportWithReportSectionAsArray
{
    [self prepareReportStoreWithPathEnd:@"testMalformedReportArray"];
    NSString *json = @"{\"report\":[1,2,3],\"crash\":{}}";
    char reportIDBuffer[KSID_SIZE];
    XCTAssertTrue(kscrs_addUserReport(json.UTF8String, (int)json.length, &_storeConfig, reportIDBuffer));
    NSString *reportID = @(reportIDBuffer);

    char *report = kscrs_readReport(reportID.UTF8String, &_storeConfig, NULL);
    XCTAssertTrue(report != NULL, @"Should not crash on report section being an array");
    free(report);
}

- (void)testReadReportWithMissingReportSection
{
    [self prepareReportStoreWithPathEnd:@"testMalformedNoReport"];
    NSString *json = @"{\"crash\":{\"error\":{}}}";
    char reportIDBuffer[KSID_SIZE];
    XCTAssertTrue(kscrs_addUserReport(json.UTF8String, (int)json.length, &_storeConfig, reportIDBuffer));
    NSString *reportID = @(reportIDBuffer);

    char *report = kscrs_readReport(reportID.UTF8String, &_storeConfig, NULL);
    XCTAssertTrue(report != NULL, @"Should not crash when report section is absent");
    free(report);
}

- (void)testReadReportWithReportSectionAsStringWithRunSidecars
{
    self.reportStorePath = [self.tempPath stringByAppendingPathComponent:@"testMalformedRunSidecars"];
    NSString *sidecarsPath = [self.tempPath stringByAppendingPathComponent:@"Sidecars"];
    NSString *runSidecarsPath = [self.tempPath stringByAppendingPathComponent:@"RunSidecars"];
    _storeConfig.reportsPath = self.reportStorePath.UTF8String;
    _storeConfig.reportSidecarsPath = sidecarsPath.UTF8String;
    _storeConfig.runSidecarsPath = runSidecarsPath.UTF8String;
    _storeConfig.maxReportCount = 5;
    kscrs_initialize(&_storeConfig);
    kscrs_setStitchConfig(&_storeConfig);

    NSString *json = @"{\"report\":\"not a dict\",\"crash\":{}}";
    char reportIDBuffer[KSID_SIZE];
    XCTAssertTrue(kscrs_addUserReport(json.UTF8String, (int)json.length, &_storeConfig, reportIDBuffer));
    NSString *reportID = @(reportIDBuffer);

    char *report = kscrs_readReport(reportID.UTF8String, &_storeConfig, NULL);
    XCTAssertTrue(report != NULL, @"Should not crash on malformed report section with run sidecars enabled");
    free(report);
}

@end
