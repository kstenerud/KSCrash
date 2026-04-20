//
//  KSCrashReportStore_RunSummary_Tests.m
//
//  Created by Alexander Cohen on 2026-04-20.
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

#import "KSCrashConfiguration.h"
#import "KSCrashReportStore.h"
#import "KSCrashRunFilter.h"
#import "KSCrashRunSummary.h"

// Stub sink that captures received runs and responds per-test.
@interface KSCrashReportStore_StubRunSink : NSObject <KSCrashRunFilter>
@property(nonatomic, copy, nullable) NSArray<KSCrashRunSummary *> *lastReceivedRuns;
@property(nonatomic, strong, nullable) NSError *errorToReturn;
@end

@implementation KSCrashReportStore_StubRunSink
- (void)filterRuns:(NSArray<KSCrashRunSummary *> *)runs onCompletion:(KSCrashRunFilterCompletion)onCompletion
{
    self.lastReceivedRuns = runs;
    if (onCompletion) {
        onCompletion(runs, self.errorToReturn);
    }
}
@end

@interface KSCrashReportStore_RunSummary_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@property(nonatomic, strong) KSCrashReportStore *store;
@end

@implementation KSCrashReportStore_RunSummary_Tests

- (KSCrashRunSummary *)sampleSummaryWithRunID:(NSString *)runID
{
    KSCrashRunSummaryOutcome *outcome =
        [[KSCrashRunSummaryOutcome alloc] initWithTerminationReason:KSTerminationReasonClean
                                                      cleanShutdown:YES
                                                      fatalReported:NO
                                                    userPerceptible:YES];
    KSCrashRunSummaryDurations *durations = [[KSCrashRunSummaryDurations alloc] initWithActiveMs:100 backgroundMs:50];
    KSCrashRunSummarySessions *sessions = [[KSCrashRunSummarySessions alloc] initWithPerceptibleCount:1
                                                                                   imperceptibleCount:0];
    KSCrashRunSummaryUsers *users = [[KSCrashRunSummaryUsers alloc] initWithPerceptibleCount:1 imperceptibleCount:0];
    KSCrashRunSummaryApp *app = [[KSCrashRunSummaryApp alloc] initWithBundleID:@"com.test"
                                                                       version:@"1.0"
                                                                  shortVersion:@"1.0"
                                                                      hostKind:KSCrashRunSummaryHostKindApp];
    KSCrashRunSummaryOS *os = [[KSCrashRunSummaryOS alloc] initWithName:@"iOS" version:@"18" build:@"22A"];
    KSCrashRunSummaryDevice *device = [[KSCrashRunSummaryDevice alloc] initWithModel:@"iPhone17,1"
                                                                         modelFamily:@"iPhone"
                                                                        architecture:@"arm64e"
                                                                  binaryArchitecture:@"arm64e"
                                                                        isTranslated:NO
                                                                        isJailbroken:NO];
    return [[KSCrashRunSummary alloc] initWithSchemaVersion:1
                                                 sdkVersion:@"2.6.0-beta.1"
                                                      runID:runID
                                                   deviceID:@"d"
                                                     userID:nil
                                                      users:users
                                                startedAtMs:0
                                                  endedAtMs:100
                                                    outcome:outcome
                                                  durations:durations
                                                   sessions:sessions
                                                        app:app
                                                         os:os
                                                     device:device];
}

- (NSString *)runsDir
{
    // Parent of reportsPath + "/Runs" — matches KSCrashReportStoreConfiguration.toCConfiguration.
    return [self.tempDir stringByAppendingPathComponent:@"Runs"];
}

- (void)writeSummaryWithRunID:(NSString *)runID
{
    [[NSFileManager defaultManager] createDirectoryAtPath:self.runsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSData *data = [[self sampleSummaryWithRunID:runID] jsonData];
    XCTAssertNotNil(data);
    NSString *path = [self.runsDir stringByAppendingPathComponent:[runID stringByAppendingPathExtension:@"json"]];
    [data writeToFile:path atomically:YES];
}

- (void)setUp
{
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSString *reportsPath = [self.tempDir stringByAppendingPathComponent:@"Reports"];

    KSCrashReportStoreConfiguration *config = [KSCrashReportStoreConfiguration new];
    config.reportsPath = reportsPath;
    config.appName = @"test-app";
    self.store = [KSCrashReportStore storeWithConfiguration:config error:nil];
    XCTAssertNotNil(self.store);
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Tests

- (void)test_sendAllRunSummaries_completesWithErrorWhenNoSink
{
    [self writeSummaryWithRunID:@"run-A"];

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [self.store
        sendAllRunSummariesWithCompletion:^(NSArray<KSCrashRunSummary *> *_Nullable runs, NSError *_Nullable error) {
            XCTAssertNotNil(error);
            XCTAssertEqual(runs.count, 0u);
            [done fulfill];
        }];
    [self waitForExpectations:@[ done ] timeout:1.0];

    // Files must be left on disk — they'll be retried once a sink is provided.
    XCTAssertTrue(
        [[NSFileManager defaultManager] fileExistsAtPath:[self.runsDir stringByAppendingPathComponent:@"run-A.json"]]);
}

- (void)test_sendAllRunSummaries_completesWithEmptyArrayWhenNoFiles
{
    self.store.runSink = [KSCrashReportStore_StubRunSink new];

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [self.store
        sendAllRunSummariesWithCompletion:^(NSArray<KSCrashRunSummary *> *_Nullable runs, NSError *_Nullable error) {
            XCTAssertNil(error);
            XCTAssertEqual(runs.count, 0u);
            [done fulfill];
        }];
    [self waitForExpectations:@[ done ] timeout:1.0];
}

- (void)test_sendAllRunSummaries_passesDecodedRunsToSinkAndDeletesOnSuccess
{
    [self writeSummaryWithRunID:@"run-A"];
    [self writeSummaryWithRunID:@"run-B"];
    KSCrashReportStore_StubRunSink *sink = [KSCrashReportStore_StubRunSink new];
    self.store.runSink = sink;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [self.store
        sendAllRunSummariesWithCompletion:^(NSArray<KSCrashRunSummary *> *_Nullable runs, NSError *_Nullable error) {
            XCTAssertNil(error);
            XCTAssertEqual(runs.count, 2u);
            [done fulfill];
        }];
    [self waitForExpectations:@[ done ] timeout:1.0];

    XCTAssertEqual(sink.lastReceivedRuns.count, 2u);
    NSSet<NSString *> *runIDs = [NSSet setWithArray:[sink.lastReceivedRuns valueForKey:@"runID"]];
    XCTAssertEqualObjects(runIDs, ([NSSet setWithArray:@[ @"run-A", @"run-B" ]]));

    // Files gone after successful send.
    XCTAssertFalse(
        [[NSFileManager defaultManager] fileExistsAtPath:[self.runsDir stringByAppendingPathComponent:@"run-A.json"]]);
    XCTAssertFalse(
        [[NSFileManager defaultManager] fileExistsAtPath:[self.runsDir stringByAppendingPathComponent:@"run-B.json"]]);
}

- (void)test_sendAllRunSummaries_retainsFilesWhenSinkReturnsError
{
    [self writeSummaryWithRunID:@"run-A"];
    KSCrashReportStore_StubRunSink *sink = [KSCrashReportStore_StubRunSink new];
    sink.errorToReturn = [NSError errorWithDomain:@"test" code:42 userInfo:nil];
    self.store.runSink = sink;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [self.store sendAllRunSummariesWithCompletion:^(__unused NSArray<KSCrashRunSummary *> *_Nullable runs,
                                                    NSError *_Nullable error) {
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, 42);
        [done fulfill];
    }];
    [self waitForExpectations:@[ done ] timeout:1.0];

    XCTAssertTrue(
        [[NSFileManager defaultManager] fileExistsAtPath:[self.runsDir stringByAppendingPathComponent:@"run-A.json"]]);
}

- (void)test_sendAllRunSummaries_skipsCorruptFiles
{
    [self writeSummaryWithRunID:@"run-A"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.runsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *junkPath = [self.runsDir stringByAppendingPathComponent:@"garbage.json"];
    [[NSData dataWithBytes:"not json" length:8] writeToFile:junkPath atomically:YES];

    KSCrashReportStore_StubRunSink *sink = [KSCrashReportStore_StubRunSink new];
    self.store.runSink = sink;

    XCTestExpectation *done = [self expectationWithDescription:@"completion"];
    [self.store
        sendAllRunSummariesWithCompletion:^(NSArray<KSCrashRunSummary *> *_Nullable runs, NSError *_Nullable error) {
            XCTAssertNil(error);
            XCTAssertEqual(runs.count, 1u);
            [done fulfill];
        }];
    [self waitForExpectations:@[ done ] timeout:1.0];

    XCTAssertEqual(sink.lastReceivedRuns.count, 1u);
    XCTAssertEqualObjects(sink.lastReceivedRuns.firstObject.runID, @"run-A");
    // Corrupt file is left in place — not sent, not deleted.
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:junkPath]);
}

@end
