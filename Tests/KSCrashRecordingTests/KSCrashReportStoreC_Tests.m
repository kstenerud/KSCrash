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

#import "KSCrashReportStoreC+Private.h"

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
    sprintf(scanFormat, "%s-report-%%" PRIx64 ".json", self.appName.UTF8String);

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

- (void)testStoresLoadsWithUnicodeAppName
{
    self.appName = @"ЙогуртЙод";
    [self prepareReportStoreWithPathEnd:@"testStoresLoadsWithUnicodeAppName"];
    int64_t reportID = [self writeCrashReportWithStringContents:REPORT_CONTENTS(0)];
    [self expectReports:@[ @(reportID) ] areStrings:@[ REPORT_CONTENTS(0) ]];
}

@end
