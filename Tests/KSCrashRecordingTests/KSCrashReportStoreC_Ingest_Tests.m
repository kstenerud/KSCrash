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
    _appConfig.extensionReportsPath = self.extensionReportsPath.UTF8String;
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

#pragma mark - kscrs_ingestExtensionReports

- (void)testIngestMovesExtensionReportsIntoStore
{
    [self prepareStores];
    NSString *firstID = [self writeExtensionReport];
    NSString *secondID = [self writeExtensionReport];

    kscrs_ingestExtensionReports(&_appConfig);

    XCTAssertEqual(kscrs_getReportCount(&_appConfig), 2);
    XCTAssertEqual([self fileCountAt:self.extensionReportsPath], 0u, @"The source directory must drain");

    for (NSString *reportID in @[ firstID, secondID ]) {
        char *report = kscrs_readReport(reportID.UTF8String, &_appConfig, NULL);
        XCTAssertTrue(report != NULL, @"Ingested report %@ must read from the app store", reportID);
        if (report != NULL) {
            NSData *data = [NSData dataWithBytes:report length:strlen(report)];
            XCTAssertNotNil([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
            free(report);
        }
    }
}

- (void)testIngestDrainsADirectoryLargerThanOneReadBuffer
{
    // Two files fit in a single getdirentries refill, so they cannot catch a walk that mutates
    // the directory it is reading. Enough entries to span several refills can: removing entries
    // mid-readdir invalidates the offsets the next refill resumes from, and the skipped ones
    // would silently stay behind until some later send.
    [self prepareStores];
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (int i = 0; i < 300; i++) {
        [ids addObject:[self writeExtensionReport]];
    }

    kscrs_ingestExtensionReports(&_appConfig);

    XCTAssertEqual([self fileCountAt:self.extensionReportsPath], 0u, @"The source directory must drain in one pass");
    XCTAssertEqual(kscrs_getReportCount(&_appConfig), (int)ids.count);
    for (NSString *reportID in ids) {
        char *report = kscrs_readReport(reportID.UTF8String, &_appConfig, NULL);
        XCTAssertTrue(report != NULL, @"Ingested report %@ must read from the app store", reportID);
        free(report);
    }
}

- (void)testIngestSkipsExistingDestination
{
    [self prepareStores];
    [self writeExtensionReport];

    // Occupy the destination: the move must refuse to clobber and leave the source alone.
    NSString *fileName =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.extensionReportsPath error:nil].firstObject;
    NSString *destination = [self.appReportsPath stringByAppendingPathComponent:fileName];
    [@"{\"existing\":true}" writeToFile:destination atomically:YES encoding:NSUTF8StringEncoding error:nil];

    kscrs_ingestExtensionReports(&_appConfig);

    XCTAssertEqual([self fileCountAt:self.extensionReportsPath], 1u, @"The source file must stay put");
    NSString *kept = [NSString stringWithContentsOfFile:destination encoding:NSUTF8StringEncoding error:nil];
    XCTAssertEqualObjects(kept, @"{\"existing\":true}", @"The existing report must be untouched");
}

- (void)testIngestLeavesForeignFilesAlone
{
    [self prepareStores];
    NSString *notes = [self.extensionReportsPath stringByAppendingPathComponent:@"other.txt"];
    NSString *otherApp =
        [self.extensionReportsPath stringByAppendingPathComponent:@"OtherApp-report-0000000000000001.json"];
    [@"notes" writeToFile:notes atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"{}" writeToFile:otherApp atomically:YES encoding:NSUTF8StringEncoding error:nil];

    kscrs_ingestExtensionReports(&_appConfig);

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:notes]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:otherApp]);
    XCTAssertEqual(kscrs_getReportCount(&_appConfig), 0);
}

- (void)testIngestNoOpWithoutPath
{
    [self prepareStores];
    [self writeExtensionReport];
    _appConfig.extensionReportsPath = NULL;

    kscrs_ingestExtensionReports(&_appConfig);

    XCTAssertEqual(kscrs_getReportCount(&_appConfig), 0);
    XCTAssertEqual([self fileCountAt:self.extensionReportsPath], 1u);
}

- (void)testIngestNoOpWithMissingDirectory
{
    [self prepareStores];
    _appConfig.extensionReportsPath = "/nonexistent/definitely/not/here";

    kscrs_ingestExtensionReports(&_appConfig);

    XCTAssertEqual(kscrs_getReportCount(&_appConfig), 0);
}

@end
