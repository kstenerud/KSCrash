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

#pragma mark - Users

- (void)test_users_storesCounts
{
    KSCrashRunSummaryUsers *users = [[KSCrashRunSummaryUsers alloc] initWithPerceptibleCount:3 imperceptibleCount:1];

    XCTAssertEqual(users.perceptibleCount, 3);
    XCTAssertEqual(users.imperceptibleCount, 1);
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
    KSCrashRunSummaryUsers *users = [[KSCrashRunSummaryUsers alloc] initWithPerceptibleCount:2 imperceptibleCount:1];
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
                                                   users:users
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
    XCTAssertIdentical(summary.users, users);
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
    KSCrashRunSummaryUsers *users = [[KSCrashRunSummaryUsers alloc] initWithPerceptibleCount:0 imperceptibleCount:0];
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
                                                                            users:users
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

#pragma mark - Decoder rejects malformed input

// Fully-valid wire-format JSON dict used as a base for the "missing key"
// tests below. Each test removes exactly one key and asserts the decoder
// returns nil.
- (NSMutableDictionary *)fullyValidWireDict
{
    return [@{
        @"schema_version" : @1,
        @"sdk_version" : @"2.6.0-beta.1",
        @"run_id" : @"r",
        @"device_id" : @"d",
        @"users" : @ { @"perceptible_count" : @0, @"imperceptible_count" : @0 },
        @"started_at_ms" : @0,
        @"ended_at_ms" : @0,
        @"outcome" : @ {
            @"termination_reason" : @"clean",
            @"clean_shutdown" : @YES,
            @"fatal_reported" : @NO,
            @"user_perceptible" : @YES,
        },
        @"durations_ms" : @ { @"active" : @0, @"background" : @0 },
        @"sessions" : @ { @"perceptible_count" : @0, @"imperceptible_count" : @0 },
        @"app" : @ { @"bundle_id" : @"x", @"version" : @"1", @"short_version" : @"1", @"host_kind" : @"app" },
        @"os" : @ { @"name" : @"iOS", @"version" : @"18", @"build" : @"X" },
        @"device" : @ {
            @"model" : @"x",
            @"model_family" : @"x",
            @"architecture" : @"arm64",
            @"binary_architecture" : @"arm64",
            @"is_translated" : @NO,
            @"is_jailbroken" : @NO,
        },
    } mutableCopy];
}

- (NSData *)jsonDataFromDict:(NSDictionary *)dict
{
    return [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
}

- (void)test_decoder_acceptsFullyValidDict
{
    KSCrashRunSummary *summary =
        [KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:[self fullyValidWireDict]] error:nil];
    XCTAssertNotNil(summary);
}

- (void)test_decoder_rejectsMissingTopLevelRequiredKeys
{
    NSArray<NSString *> *requiredKeys = @[
        @"schema_version", @"sdk_version", @"run_id", @"device_id", @"started_at_ms", @"ended_at_ms", @"users",
        @"outcome", @"durations_ms", @"sessions", @"app", @"os", @"device"
    ];
    for (NSString *key in requiredKeys) {
        NSMutableDictionary *dict = [self fullyValidWireDict];
        [dict removeObjectForKey:key];
        XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil],
                     @"Expected nil when required key %@ is missing", key);
    }
}

- (void)test_decoder_rejectsWrongTypes
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    dict[@"run_id"] = @42;  // number where string is required
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    dict[@"started_at_ms"] = @"not a number";
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    dict[@"outcome"] = @"not a dict";
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    // user_id is optional, but a present non-string value is a schema
    // violation and rejects the whole summary rather than being dropped.
    dict = [self fullyValidWireDict];
    dict[@"user_id"] = @42;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);
}

- (void)test_decoder_rejectsMissingNestedRequiredKeys
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    NSMutableDictionary *outcome = [dict[@"outcome"] mutableCopy];
    [outcome removeObjectForKey:@"clean_shutdown"];
    dict[@"outcome"] = outcome;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    NSMutableDictionary *app = [dict[@"app"] mutableCopy];
    [app removeObjectForKey:@"host_kind"];
    dict[@"app"] = app;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);
}

- (void)test_decoder_toleratesMissingUserID
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    // user_id is explicitly nullable in the header — absence is valid.
    [dict removeObjectForKey:@"user_id"];
    KSCrashRunSummary *summary = [KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil];
    XCTAssertNotNil(summary);
    XCTAssertNil(summary.userID);
}

- (void)test_decoder_rejectsNonDictionaryRoot
{
    NSData *rootArray = [NSJSONSerialization dataWithJSONObject:@[ @"not a dict" ] options:0 error:nil];
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:rootArray error:nil]);
}

// Under NSJSONSerialization JSON booleans are __NSCFBoolean (an NSNumber
// subclass), so a naive isKindOfClass:[NSNumber class] check accepts
// {"schema_version": true} and {"clean_shutdown": 2} alike. These tests
// lock in that the decoder distinguishes the two.
- (void)test_decoder_rejectsBooleanWhereNumberRequired
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    dict[@"schema_version"] = @YES;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    dict[@"started_at_ms"] = @NO;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    NSMutableDictionary *durations = [dict[@"durations_ms"] mutableCopy];
    durations[@"active"] = @YES;
    dict[@"durations_ms"] = durations;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    NSMutableDictionary *users = [dict[@"users"] mutableCopy];
    users[@"perceptible_count"] = @YES;
    dict[@"users"] = users;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);
}

// Fractional JSON values must not silently truncate via -longLongValue. The
// schema only has integer scalars (counts, ms timestamps, schema_version),
// so a {"started_at_ms": 1.5e9} wire payload indicates producer/consumer
// version drift rather than a value to accept.
- (void)test_decoder_rejectsFractionalWhereIntegerRequired
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    dict[@"started_at_ms"] = @(1.5);
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    dict[@"schema_version"] = @(2.5);
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    NSMutableDictionary *durations = [dict[@"durations_ms"] mutableCopy];
    durations[@"active"] = @(100.25);
    dict[@"durations_ms"] = durations;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    NSMutableDictionary *sessions = [dict[@"sessions"] mutableCopy];
    sessions[@"perceptible_count"] = @(3.7);
    dict[@"sessions"] = sessions;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);
}

- (void)test_decoder_rejectsNumberWhereBooleanRequired
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    NSMutableDictionary *outcome = [dict[@"outcome"] mutableCopy];
    outcome[@"clean_shutdown"] = @2;
    dict[@"outcome"] = outcome;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    outcome = [dict[@"outcome"] mutableCopy];
    outcome[@"fatal_reported"] = @0;  // 0 also rejected — bool is not a synonym for "zero"
    dict[@"outcome"] = outcome;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);

    dict = [self fullyValidWireDict];
    NSMutableDictionary *device = [dict[@"device"] mutableCopy];
    device[@"is_translated"] = @1;
    dict[@"device"] = device;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);
}

@end
