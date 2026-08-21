//
//  KSCrashReportStore_Tests.m
//
//  Created by Alexander Cohen on 2026-08-20.
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

#import "KSCrashInstallConfiguration.h"
#import "KSCrashReportStore.h"

@interface KSCrashReportStore_Tests : XCTestCase
@property(nonatomic, copy) NSString *tempPath;
@property(nonatomic, copy) NSString *reportsPath;
@property(nonatomic, strong) KSCrashReportStore *store;
@end

@implementation KSCrashReportStore_Tests

- (void)setUp
{
    [super setUp];
    self.tempPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"KSCrashReportStore_Tests-%@", [NSUUID UUID]]];
    self.reportsPath = [self.tempPath stringByAppendingPathComponent:@"Reports"];
    KSCrashReportStoreConfiguration *config = [KSCrashReportStoreConfiguration new];
    config.appName = @"TestApp";
    config.reportsPath = self.reportsPath;
    self.store = [KSCrashReportStore storeWithConfiguration:config error:nil];
    XCTAssertNotNil(self.store);
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempPath error:NULL];
    [super tearDown];
}

/// Write a report file under the C store's filename grammar.
- (int64_t)writeReportWithContents:(NSString *)contents
{
    static int64_t nextID = 7000;
    int64_t reportID = nextID++;
    NSString *name = [NSString stringWithFormat:@"TestApp-report-%016llx.json", (unsigned long long)reportID];
    NSData *data = [contents dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([data writeToFile:[self.reportsPath stringByAppendingPathComponent:name] atomically:YES]);
    return reportID;
}

/// Replace the reports directory with a plain file so enumeration fails.
- (void)breakReportsDirectory
{
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:self.reportsPath error:NULL]);
    XCTAssertTrue([[NSData data] writeToFile:self.reportsPath atomically:YES]);
}

- (void)testListReportIDsReturnsOldestFirst
{
    int64_t first = [self writeReportWithContents:@"{\"report\":{}}"];
    int64_t second = [self writeReportWithContents:@"{\"report\":{}}"];

    NSError *error = nil;
    NSArray<NSNumber *> *ids = [self.store listReportIDsWithError:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(ids, (@[ @(first), @(second) ]));
}

- (void)testListReportIDsSetsAnErrorWhenTheDirectoryCannotBeEnumerated
{
    [self breakReportsDirectory];

    NSError *error = nil;
    XCTAssertNil([self.store listReportIDsWithError:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, NSFileReadUnknownError);

    // The clamped count reads as empty rather than leaking the failure.
    XCTAssertEqual(self.store.reportCount, 0);
}

- (void)testRemoveReportRemovesAndReportsAMissingReport
{
    int64_t reportID = [self writeReportWithContents:@"{\"report\":{}}"];

    NSError *error = nil;
    XCTAssertTrue([self.store removeReportWithID:reportID error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(self.store.reportCount, 0);

    XCTAssertFalse([self.store removeReportWithID:reportID error:&error]);
    XCTAssertNotNil(error);
}

- (void)testReportDataDistinguishesMissingFromUndecodable
{
    NSError *error = nil;
    XCTAssertNil([self.store reportDataForID:12345 error:&error]);
    XCTAssertEqual(error.code, NSFileReadUnknownError);

    int64_t badID = [self writeReportWithContents:@"[1,2]"];
    error = nil;
    XCTAssertNil([self.store reportDataForID:badID error:&error]);
    XCTAssertEqual(error.code, NSFileReadCorruptFileError);

    int64_t goodID = [self writeReportWithContents:@"{\"report\":{\"id\":\"x\"}}"];
    error = nil;
    XCTAssertNotNil([self.store reportDataForID:goodID error:&error]);
    XCTAssertNil(error);
}

- (void)testRunIDForReportIDAnswersFromTheReportFile
{
    int64_t reportID =
        [self writeReportWithContents:@"{\"report\":{\"run_id\":\"0155A1E2-D4C3-4B6A-9C8D-1234567890AB\"}}"];
    XCTAssertEqualObjects([self.store runIDForReportID:reportID], @"0155A1E2-D4C3-4B6A-9C8D-1234567890AB");

    int64_t noRunID = [self writeReportWithContents:@"{\"report\":{}}"];
    XCTAssertNil([self.store runIDForReportID:noRunID]);
    XCTAssertNil([self.store runIDForReportID:12345]);
}

@end
