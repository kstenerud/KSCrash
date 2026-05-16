//
//  KSCrashRunFilter_Tests.m
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

#import "KSCrashRunFilter.h"
#import "KSCrashRunSummary.h"

// Echoes received runs back via the completion block and remembers them
// for assertions.
@interface KSCrash_TestRunFilter : NSObject <KSCrashRunFilter>
@property(nonatomic, copy, nullable) NSArray<KSCrashRunSummary *> *receivedRuns;
@end

@implementation KSCrash_TestRunFilter

- (void)filterRuns:(NSArray<KSCrashRunSummary *> *)runs onCompletion:(KSCrashRunFilterCompletion)onCompletion
{
    self.receivedRuns = runs;
    if (onCompletion) {
        onCompletion(runs, nil);
    }
}

@end

@interface KSCrashRunFilter_Tests : XCTestCase
@end

@implementation KSCrashRunFilter_Tests

- (KSCrashRunSummary *)makeSummary
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
                                                                       version:@"1.0.0"
                                                                  shortVersion:@"1.0"
                                                                      hostKind:KSCrashRunSummaryHostKindApp];
    KSCrashRunSummaryOS *os = [[KSCrashRunSummaryOS alloc] initWithName:@"iOS" version:@"18.0" build:@"22A348"];
    KSCrashRunSummaryDevice *device = [[KSCrashRunSummaryDevice alloc] initWithModel:@"iPhone17,1"
                                                                         modelFamily:@"iPhone"
                                                                        architecture:@"arm64e"
                                                                  binaryArchitecture:@"arm64e"
                                                                        isTranslated:NO
                                                                        isJailbroken:NO];
    return [[KSCrashRunSummary alloc] initWithSchemaVersion:1
                                                 sdkVersion:@"2.6.0-beta.1"
                                                      runID:@"test-run"
                                                   deviceID:@"test-device"
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

- (void)test_filterRuns_invokesCompletionWithForwardedRuns
{
    KSCrash_TestRunFilter *filter = [KSCrash_TestRunFilter new];
    NSArray<KSCrashRunSummary *> *runs = @[ [self makeSummary], [self makeSummary] ];

    XCTestExpectation *completed = [self expectationWithDescription:@"completion"];
    [filter filterRuns:runs
          onCompletion:^(NSArray<KSCrashRunSummary *> *_Nullable filteredRuns, NSError *_Nullable error) {
              XCTAssertNil(error);
              XCTAssertEqual(filteredRuns.count, 2u);
              [completed fulfill];
          }];
    [self waitForExpectations:@[ completed ] timeout:1.0];

    XCTAssertEqual(filter.receivedRuns.count, 2u);
}

- (void)test_filterRuns_nilCompletionIsAllowed
{
    KSCrash_TestRunFilter *filter = [KSCrash_TestRunFilter new];
    // Calling with a nil completion must not crash — matches the nullable
    // contract in the protocol.
    [filter filterRuns:@[ [self makeSummary] ] onCompletion:nil];
    XCTAssertEqual(filter.receivedRuns.count, 1u);
}

@end
