//
//  KSCrashRunSummary_Tests.m
//
//  Created by Alexander Cohen on 2026-04-19.
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

#import "KSCrashRunSummary.h"

@interface KSCrashRunSummary_Tests : XCTestCase
@end

@implementation KSCrashRunSummary_Tests

#pragma mark - Outcome

- (void)test_outcome_storesAllFields
{
    KSCrashRunSummaryOutcome *outcome =
        [[KSCrashRunSummaryOutcome alloc] initWithTerminationReason:KSTerminationReasonCrash
                                                      cleanShutdown:NO
                                                      fatalReported:YES
                                                    userPerceptible:YES];

    XCTAssertEqual(outcome.terminationReason, KSTerminationReasonCrash);
    XCTAssertFalse(outcome.cleanShutdown);
    XCTAssertTrue(outcome.fatalReported);
    XCTAssertTrue(outcome.userPerceptible);
}

#pragma mark - Durations

- (void)test_durations_storesAllFields
{
    KSCrashRunSummaryDurations *durations = [[KSCrashRunSummaryDurations alloc] initWithActiveMs:123456
                                                                                    backgroundMs:45678];

    XCTAssertEqual(durations.activeMs, 123456);
    XCTAssertEqual(durations.backgroundMs, 45678);
}

#pragma mark - Sessions

- (void)test_sessions_storesAllFields
{
    KSCrashRunSummarySessions *sessions = [[KSCrashRunSummarySessions alloc] initWithPerceptibleCount:3
                                                                                   imperceptibleCount:2];

    XCTAssertEqual(sessions.perceptibleCount, 3);
    XCTAssertEqual(sessions.imperceptibleCount, 2);
}

#pragma mark - UserIDs

- (void)test_anonymousSentinel_hasExpectedValue
{
    XCTAssertEqualObjects(KSCrashRunSummaryAnonymousUserID, @"com.kscrash.user.anon");
}

- (void)test_anonymousSentinel_isIdentityComparable
{
    // The constant is a true NSString *const, so two references are the same pointer
    // and identity comparison works without falling back to -isEqual:.
    NSString *a = KSCrashRunSummaryAnonymousUserID;
    NSString *b = KSCrashRunSummaryAnonymousUserID;
    XCTAssertTrue(a == b, @"Expected identical pointer for the anonymous sentinel");
}

- (void)test_anonymousSentinel_userIDAccessorReturnsSamePointer
{
    // The class-property form (used in Swift as `RunSummary.UserID.anonymous`)
    // must return the exact same pointer as the file-level constant.
    XCTAssertTrue(KSCrashRunSummaryUserID.anonymous == KSCrashRunSummaryAnonymousUserID);
}

- (void)test_userIDs_storesArrays
{
    NSArray<NSString *> *perceptible = @[ @"alice", KSCrashRunSummaryAnonymousUserID, @"bob" ];
    NSArray<NSString *> *imperceptible = @[ @"bob" ];

    KSCrashRunSummaryUserIDs *userIDs = [[KSCrashRunSummaryUserIDs alloc] initWithPerceptible:perceptible
                                                                                imperceptible:imperceptible];

    XCTAssertEqualObjects(userIDs.perceptible, perceptible);
    XCTAssertEqualObjects(userIDs.imperceptible, imperceptible);
}

- (void)test_userIDs_copiesArraysDefensively
{
    NSMutableArray<NSString *> *mutablePerceptible = [@[ @"alice" ] mutableCopy];
    NSMutableArray<NSString *> *mutableImperceptible = [@[ @"bob" ] mutableCopy];

    KSCrashRunSummaryUserIDs *userIDs = [[KSCrashRunSummaryUserIDs alloc] initWithPerceptible:mutablePerceptible
                                                                                imperceptible:mutableImperceptible];

    // Mutating the input arrays after construction must not change the stored state.
    [mutablePerceptible addObject:@"eve"];
    [mutableImperceptible addObject:@"eve"];

    XCTAssertEqual(userIDs.perceptible.count, (NSUInteger)1);
    XCTAssertEqual(userIDs.imperceptible.count, (NSUInteger)1);
}

#pragma mark - App

- (void)test_app_storesAllFields
{
    KSCrashRunSummaryApp *app = [[KSCrashRunSummaryApp alloc] initWithBundleID:@"com.acme.app"
                                                                       version:@"2.6.0.1234"
                                                                  shortVersion:@"2.6.0"
                                                                      hostKind:KSCrashRunSummaryHostKindApp];

    XCTAssertEqualObjects(app.bundleID, @"com.acme.app");
    XCTAssertEqualObjects(app.version, @"2.6.0.1234");
    XCTAssertEqualObjects(app.shortVersion, @"2.6.0");
    XCTAssertEqual(app.hostKind, KSCrashRunSummaryHostKindApp);
}

- (void)test_app_hostKindExtensionDistinct
{
    KSCrashRunSummaryApp *app = [[KSCrashRunSummaryApp alloc] initWithBundleID:@"com.acme.widget"
                                                                       version:@"2.6.0.1234"
                                                                  shortVersion:@"2.6.0"
                                                                      hostKind:KSCrashRunSummaryHostKindExtension];

    XCTAssertEqual(app.hostKind, KSCrashRunSummaryHostKindExtension);
    XCTAssertNotEqual(app.hostKind, KSCrashRunSummaryHostKindApp);
}

#pragma mark - OS

- (void)test_os_storesAllFields
{
    KSCrashRunSummaryOS *os = [[KSCrashRunSummaryOS alloc] initWithName:@"iOS" version:@"18.0" build:@"22A348"];

    XCTAssertEqualObjects(os.name, @"iOS");
    XCTAssertEqualObjects(os.version, @"18.0");
    XCTAssertEqualObjects(os.build, @"22A348");
}

#pragma mark - Device

- (void)test_device_storesAllFields
{
    KSCrashRunSummaryDevice *device = [[KSCrashRunSummaryDevice alloc] initWithModel:@"iPhone17,1"
                                                                         modelFamily:@"iPhone"
                                                                        architecture:@"arm64e"
                                                                  binaryArchitecture:@"arm64e"
                                                                        isTranslated:NO
                                                                        isJailbroken:NO];

    XCTAssertEqualObjects(device.model, @"iPhone17,1");
    XCTAssertEqualObjects(device.modelFamily, @"iPhone");
    XCTAssertEqualObjects(device.architecture, @"arm64e");
    XCTAssertEqualObjects(device.binaryArchitecture, @"arm64e");
    XCTAssertFalse(device.isTranslated);
    XCTAssertFalse(device.isJailbroken);
}

#pragma mark - RunSummary

- (void)test_runSummary_storesAllFields
{
    KSCrashRunSummaryOutcome *outcome =
        [[KSCrashRunSummaryOutcome alloc] initWithTerminationReason:KSTerminationReasonClean
                                                      cleanShutdown:YES
                                                      fatalReported:NO
                                                    userPerceptible:YES];
    KSCrashRunSummaryDurations *durations = [[KSCrashRunSummaryDurations alloc] initWithActiveMs:123456
                                                                                    backgroundMs:45678];
    KSCrashRunSummarySessions *sessions = [[KSCrashRunSummarySessions alloc] initWithPerceptibleCount:3
                                                                                   imperceptibleCount:2];
    KSCrashRunSummaryUserIDs *userIDs = [[KSCrashRunSummaryUserIDs alloc] initWithPerceptible:@[ @"alice", @"bob" ]
                                                                                imperceptible:@[ @"bob" ]];
    KSCrashRunSummaryApp *app = [[KSCrashRunSummaryApp alloc] initWithBundleID:@"com.acme.app"
                                                                       version:@"2.6.0.1234"
                                                                  shortVersion:@"2.6.0"
                                                                      hostKind:KSCrashRunSummaryHostKindApp];
    KSCrashRunSummaryOS *os = [[KSCrashRunSummaryOS alloc] initWithName:@"iOS" version:@"18.0" build:@"22A348"];
    KSCrashRunSummaryDevice *device = [[KSCrashRunSummaryDevice alloc] initWithModel:@"iPhone17,1"
                                                                         modelFamily:@"iPhone"
                                                                        architecture:@"arm64e"
                                                                  binaryArchitecture:@"arm64e"
                                                                        isTranslated:NO
                                                                        isJailbroken:NO];

    KSCrashRunSummary *summary =
        [[KSCrashRunSummary alloc] initWithSchemaVersion:1
                                              sdkVersion:@"2.6.0-beta.1"
                                                   runID:@"a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                                                deviceID:@"0123456789abcdef"
                                                  userID:@"bob"
                                                 userIDs:userIDs
                                             startedAtMs:1744000000000
                                               endedAtMs:1744000180000
                                                 outcome:outcome
                                               durations:durations
                                                sessions:sessions
                                                     app:app
                                                      os:os
                                                  device:device];

    XCTAssertEqual(summary.schemaVersion, 1);
    XCTAssertEqualObjects(summary.sdkVersion, @"2.6.0-beta.1");
    XCTAssertEqualObjects(summary.runID, @"a1b2c3d4-e5f6-7890-abcd-ef1234567890");
    XCTAssertEqualObjects(summary.deviceID, @"0123456789abcdef");
    XCTAssertEqualObjects(summary.userID, @"bob");
    XCTAssertEqual(summary.startedAtMs, 1744000000000);
    XCTAssertEqual(summary.endedAtMs, 1744000180000);
    XCTAssertIdentical(summary.outcome, outcome);
    XCTAssertIdentical(summary.durations, durations);
    XCTAssertIdentical(summary.sessions, sessions);
    XCTAssertIdentical(summary.userIDs, userIDs);
    XCTAssertIdentical(summary.app, app);
    XCTAssertIdentical(summary.os, os);
    XCTAssertIdentical(summary.device, device);
}

- (void)test_runSummary_acceptsNilUserID
{
    KSCrashRunSummaryOutcome *outcome =
        [[KSCrashRunSummaryOutcome alloc] initWithTerminationReason:KSTerminationReasonClean
                                                      cleanShutdown:YES
                                                      fatalReported:NO
                                                    userPerceptible:NO];
    KSCrashRunSummaryDurations *durations = [[KSCrashRunSummaryDurations alloc] initWithActiveMs:0 backgroundMs:0];
    KSCrashRunSummarySessions *sessions = [[KSCrashRunSummarySessions alloc] initWithPerceptibleCount:0
                                                                                   imperceptibleCount:1];
    KSCrashRunSummaryUserIDs *userIDs = [[KSCrashRunSummaryUserIDs alloc] initWithPerceptible:@[] imperceptible:@[]];
    KSCrashRunSummaryApp *app = [[KSCrashRunSummaryApp alloc] initWithBundleID:@"com.acme.app"
                                                                       version:@"1"
                                                                  shortVersion:@"1"
                                                                      hostKind:KSCrashRunSummaryHostKindApp];
    KSCrashRunSummaryOS *os = [[KSCrashRunSummaryOS alloc] initWithName:@"iOS" version:@"18" build:@"X"];
    KSCrashRunSummaryDevice *device = [[KSCrashRunSummaryDevice alloc] initWithModel:@"x"
                                                                         modelFamily:@"x"
                                                                        architecture:@"arm64"
                                                                  binaryArchitecture:@"arm64"
                                                                        isTranslated:NO
                                                                        isJailbroken:NO];

    KSCrashRunSummary *summary = [[KSCrashRunSummary alloc] initWithSchemaVersion:1
                                                                       sdkVersion:@"2.6.0-beta.1"
                                                                            runID:@"r"
                                                                         deviceID:@"d"
                                                                           userID:nil
                                                                          userIDs:userIDs
                                                                      startedAtMs:0
                                                                        endedAtMs:0
                                                                          outcome:outcome
                                                                        durations:durations
                                                                         sessions:sessions
                                                                              app:app
                                                                               os:os
                                                                           device:device];

    XCTAssertNil(summary.userID);
}

@end
