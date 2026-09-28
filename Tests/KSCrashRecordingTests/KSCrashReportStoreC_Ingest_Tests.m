//
//  KSCrashReportStoreC_Ingest_Tests.m
//
//  Created by Alexander Cohen on 2026-07-18.
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

#import "FileBasedTestCase.h"
#import "KSCrashReportStoreC+Private.h"
#import "KSCrashReportStoreC.h"

/** The send path refuses to run with no filters, so pass reports through unchanged. */
@interface KSCrashReportStoreC_Ingest_Tests : FileBasedTestCase
@end

@implementation KSCrashReportStoreC_Ingest_Tests {
    KSCrashReportStoreCConfiguration _extensionConfig;
    KSCrashReportStoreCConfiguration _appConfig;
}

- (void)setUp
{
    [super setUp];
    memset(&_extensionConfig, 0, sizeof(_extensionConfig));
    memset(&_appConfig, 0, sizeof(_appConfig));
}

- (NSString *)extensionReportsPath
{
    return [self.tempPath stringByAppendingPathComponent:@"ext/Reports"];
}

- (NSString *)appReportsPath
{
    return [self.tempPath stringByAppendingPathComponent:@"app/Reports"];
}

- (void)prepareStores
{
    _extensionConfig.reportsPath = self.extensionReportsPath.UTF8String;
    _extensionConfig.maxReportCount = 10;
    kscrs_initialize(&_extensionConfig);

    _appConfig.reportsPath = self.appReportsPath.UTF8String;
    _appConfig.maxReportCount = 10;
    kscrs_initialize(&_appConfig);
}

- (NSString *)writeExtensionReport
{
    NSString *json = @"{\"report\":{\"id\":\"ext\",\"run_id\":\"11111111-1111-1111-1111-111111111111\"}}";
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    char reportID[KSID_SIZE];
    if (!kscrs_addUserReport(data.bytes, (int)data.length, &_extensionConfig, reportID)) {
        return nil;
    }
    return @(reportID);
}

- (NSUInteger)fileCountAt:(NSString *)path
{
    return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil].count;
}

/** The only file in the extension store's Reports directory. */
- (NSString *)onlyExtensionReportName
{
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.extensionReportsPath
                                                                                     error:nil];
    XCTAssertEqual(names.count, 1u);
    return names.firstObject;
}

- (uint64_t)nanosecondsInName:(NSString *)name
{
    return strtoull([name substringToIndex:KSCRS_REPORT_NAME_DIGITS].UTF8String, NULL, 10);
}

#pragma mark - kscrs_takeInReport

- (void)testTakeInMovesAReportInUnderItsOwnName
{
    [self prepareStores];
    NSString *reportID = [self writeExtensionReport];
    NSString *name = [self onlyExtensionReportName];
    NSString *source = [self.extensionReportsPath stringByAppendingPathComponent:name];

    KSCrashReportTakeInResult result =
        kscrs_takeInReport(source.UTF8String, reportID.UTF8String, [self nanosecondsInName:name], &_appConfig);

    XCTAssertEqual(result, KSCrashReportTakeInResultTaken);
    XCTAssertEqual([self fileCountAt:self.extensionReportsPath], 0u, @"a move leaves nothing behind");
    XCTAssertTrue(
        [[NSFileManager defaultManager] fileExistsAtPath:[self.appReportsPath stringByAppendingPathComponent:name]]);
    char *report = kscrs_readReport(reportID.UTF8String, &_appConfig, NULL);
    XCTAssertTrue(report != NULL, @"the report must read from the app store");
    free(report);
}

- (void)testTakeInNamesTheReportFromItsIDAndTimestamp
{
    [self prepareStores];
    NSString *reportID = @"0e9a9c8e-5b6a-4c1e-9f5e-2f7b8f7c4d21";
    NSString *source = [self.tempPath stringByAppendingPathComponent:@"anything.json"];
    [@"{}" writeToFile:source atomically:YES encoding:NSUTF8StringEncoding error:nil];

    XCTAssertEqual(kscrs_takeInReport(source.UTF8String, reportID.UTF8String, 42, &_appConfig),
                   KSCrashReportTakeInResultTaken);

    NSString *expected = [NSString stringWithFormat:@"00000000000000000042-%@.json", reportID];
    XCTAssertEqualObjects([[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.appReportsPath error:nil],
                          @[ expected ]);
}

- (void)testTakeInNeverReplacesAnExistingReport
{
    [self prepareStores];
    NSString *reportID = [self writeExtensionReport];
    NSString *name = [self onlyExtensionReportName];
    NSString *source = [self.extensionReportsPath stringByAppendingPathComponent:name];
    NSString *destination = [self.appReportsPath stringByAppendingPathComponent:name];
    [@"{\"existing\":true}" writeToFile:destination atomically:YES encoding:NSUTF8StringEncoding error:nil];

    XCTAssertEqual(
        kscrs_takeInReport(source.UTF8String, reportID.UTF8String, [self nanosecondsInName:name], &_appConfig),
        KSCrashReportTakeInResultExists);

    XCTAssertEqual([self fileCountAt:self.extensionReportsPath], 1u, @"the source stays put");
    NSString *kept = [NSString stringWithContentsOfFile:destination encoding:NSUTF8StringEncoding error:nil];
    XCTAssertEqualObjects(kept, @"{\"existing\":true}", @"the existing report is untouched");
}

- (void)testTakeInRefusesAnIDThatIsNotAReportID
{
    [self prepareStores];
    [self writeExtensionReport];
    NSString *source = [self.extensionReportsPath stringByAppendingPathComponent:[self onlyExtensionReportName]];

    XCTAssertEqual(kscrs_takeInReport(source.UTF8String, "ext", 1, &_appConfig), KSCrashReportTakeInResultFailed);
    XCTAssertEqual([self fileCountAt:self.extensionReportsPath], 1u);
    XCTAssertEqual(kscrs_getReportCount(&_appConfig), 0);
}

- (void)testTakeInRefusesAnIDThatWouldNameAFileOutsideReports
{
    [self prepareStores];
    [self writeExtensionReport];
    NSString *source = [self.extensionReportsPath stringByAppendingPathComponent:[self onlyExtensionReportName]];

    // 36 characters, the length of an id, holding a path separator.
    XCTAssertEqual(kscrs_takeInReport(source.UTF8String, "../../../../../../../../../../..x/aa", 1, &_appConfig),
                   KSCrashReportTakeInResultFailed);
    XCTAssertEqual([self fileCountAt:self.extensionReportsPath], 1u, @"the source stays put");
}

- (void)testTakeInRefusesAnUppercaseID
{
    // The lister reads lowercase ids only, so an uppercase one would be taken in and then
    // never listed, pruned or sent.
    [self prepareStores];
    [self writeExtensionReport];
    NSString *source = [self.extensionReportsPath stringByAppendingPathComponent:[self onlyExtensionReportName]];

    XCTAssertEqual(kscrs_takeInReport(source.UTF8String, "0E9A9C8E-5B6A-4C1E-9F5E-2F7B8F7C4D21", 1, &_appConfig),
                   KSCrashReportTakeInResultFailed);
    XCTAssertEqual(kscrs_getReportCount(&_appConfig), 0);
}

- (void)testTakeInLeavesAReportItCannotMove
{
    // A source whose directory cannot be written cannot give its file up, so a copy would be
    // taken in again after every delivery. It is refused instead and left where it is.
    [self prepareStores];
    NSString *lockedDirectory = [self.tempPath stringByAppendingPathComponent:@"locked"];
    [[NSFileManager defaultManager] createDirectoryAtPath:lockedDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *source = [lockedDirectory stringByAppendingPathComponent:@"report.json"];
    [@"{}" writeToFile:source atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0555 }
                                     ofItemAtPath:lockedDirectory
                                            error:nil];

    KSCrashReportTakeInResult result =
        kscrs_takeInReport(source.UTF8String, "0e9a9c8e-5b6a-4c1e-9f5e-2f7b8f7c4d21", 7, &_appConfig);
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0755 }
                                     ofItemAtPath:lockedDirectory
                                            error:nil];

    XCTAssertEqual(result, KSCrashReportTakeInResultFailed);
    XCTAssertEqual(kscrs_getReportCount(&_appConfig), 0);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:source]);
    XCTAssertEqual([self fileCountAt:self.appReportsPath], 0u, @"nothing is left behind in the store");
}

- (void)testInitializeRemovesAStagedCopyACrashLeftBehind
{
    [[NSFileManager defaultManager] createDirectoryAtPath:self.appReportsPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *staged = [self.appReportsPath
        stringByAppendingPathComponent:@"00000000000000000001-0e9a9c8e-5b6a-4c1e-9f5e-2f7b8f7c4d21.json.incoming"];
    [@"half a report" writeToFile:staged atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [self prepareStores];

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:staged]);
}

- (void)testDeleteReportsWithIDsDeletesOnlyThoseReports
{
    [self prepareStores];
    NSArray<NSString *> *ids = @[
        @"0e9a9c8e-5b6a-4c1e-9f5e-2f7b8f7c4d21", @"0e9a9c8e-5b6a-4c1e-9f5e-2f7b8f7c4d22",
        @"0e9a9c8e-5b6a-4c1e-9f5e-2f7b8f7c4d23"
    ];
    for (NSUInteger i = 0; i < ids.count; i++) {
        NSString *source = [self.tempPath stringByAppendingPathComponent:ids[i]];
        [@"{}" writeToFile:source atomically:YES encoding:NSUTF8StringEncoding error:nil];
        XCTAssertEqual(kscrs_takeInReport(source.UTF8String, ids[i].UTF8String, i + 1, &_appConfig),
                       KSCrashReportTakeInResultTaken);
    }
    const char *victims[] = { ids[0].UTF8String, ids[2].UTF8String, "0e9a9c8e-5b6a-4c1e-9f5e-2f7b8f7c4d99" };

    kscrs_deleteReportsWithIDs(victims, 3, &_appConfig);

    NSArray<NSString *> *left = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.appReportsPath
                                                                                    error:nil];
    XCTAssertEqual(left.count, 1u);
    XCTAssertTrue([left.firstObject containsString:ids[1]]);
}

- (void)testTakeInFailsForAMissingSource
{
    [self prepareStores];
    XCTAssertEqual(kscrs_takeInReport("/nonexistent/definitely/not/here.json", "0e9a9c8e-5b6a-4c1e-9f5e-2f7b8f7c4d21",
                                      1, &_appConfig),
                   KSCrashReportTakeInResultFailed);
    XCTAssertEqual(kscrs_getReportCount(&_appConfig), 0);
}

- (void)testTakeInFailsWithoutAPath
{
    [self prepareStores];
    XCTAssertEqual(kscrs_takeInReport(NULL, "0e9a9c8e-5b6a-4c1e-9f5e-2f7b8f7c4d21", 1, &_appConfig),
                   KSCrashReportTakeInResultFailed);
}

@end
