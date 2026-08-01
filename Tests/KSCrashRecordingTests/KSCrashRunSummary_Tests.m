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
    KSCrashRunSummarySession *session = [[KSCrashRunSummarySession alloc] initWithSessionID:@"s1"
                                                                                     userID:@"bob"
                                                                                perceptible:YES
                                                                                startedAtMs:1000
                                                                                  endedAtMs:2000];
    KSCrashRunSummarySessions *sessions = [[KSCrashRunSummarySessions alloc] initWithPerceptibleCount:3
                                                                                   imperceptibleCount:2
                                                                                              records:@[ session ]];

    XCTAssertEqual(sessions.perceptibleCount, 3);
    XCTAssertEqual(sessions.imperceptibleCount, 2);
    XCTAssertEqual(sessions.records.count, 1u);
    KSCrashRunSummarySession *stored = sessions.records.firstObject;
    XCTAssertEqualObjects(stored.sessionID, @"s1");
    XCTAssertEqualObjects(stored.userID, @"bob");
    XCTAssertTrue(stored.perceptible);
    XCTAssertEqual(stored.startedAtMs, 1000);
    XCTAssertEqual(stored.endedAtMs, 2000);
}

- (void)test_sessionRecords_roundTrip
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    dict[@"sessions"] = @{
        @"perceptible_count" : @2,
        @"imperceptible_count" : @1,
        @"records" : @[
            @{
                @"session_id" : @"s1",
                @"user_id" : @"bob",
                @"perceptible" : @YES,
                @"started_at_ms" : @1000,
                @"ended_at_ms" : @2000,
            },
            @{
                @"session_id" : @"s2",
                @"perceptible" : @NO,
                @"started_at_ms" : @2000,
                @"ended_at_ms" : @3000,
            },
        ],
    };

    KSCrashRunSummary *summary = [KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil];
    XCTAssertNotNil(summary);
    XCTAssertEqual(summary.sessions.records.count, 2u);
    KSCrashRunSummarySession *s1 = summary.sessions.records[0];
    XCTAssertEqualObjects(s1.sessionID, @"s1");
    XCTAssertEqualObjects(s1.userID, @"bob");
    XCTAssertTrue(s1.perceptible);
    XCTAssertEqual(s1.startedAtMs, 1000);
    XCTAssertEqual(s1.endedAtMs, 2000);
    XCTAssertNil(summary.sessions.records[1].userID, @"anonymous session decodes to nil userID");
    XCTAssertFalse(summary.sessions.records[1].perceptible);

    // Records survive the encoder too.
    KSCrashRunSummary *reDecoded = [KSCrashRunSummary summaryFromJSONData:summary.jsonData error:nil];
    XCTAssertEqual(reDecoded.sessions.records.count, 2u);
    XCTAssertEqualObjects(reDecoded.sessions.records[1].sessionID, @"s2");
    XCTAssertNil(reDecoded.sessions.records[1].userID);
}

- (void)test_decoder_rejectsMalformedSessionRecord
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    dict[@"sessions"] = @{
        @"perceptible_count" : @0,
        @"imperceptible_count" : @0,
        @"records" : @[ @{ @"perceptible" : @YES, @"started_at_ms" : @1, @"ended_at_ms" : @2 } ],  // no session_id
    };
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);
}

- (void)test_decoder_rejectsWrongTypedSessionUserID
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    dict[@"sessions"] = @{
        @"perceptible_count" : @0,
        @"imperceptible_count" : @0,
        @"records" : @[ @{
            @"session_id" : @"s1",
            @"user_id" : @42,  // present but not a string
            @"perceptible" : @YES,
            @"started_at_ms" : @1,
            @"ended_at_ms" : @2,
        } ],
    };
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);
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
                                                                                   imperceptibleCount:2
                                                                                              records:@[]];
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
                                         isBeingDebugged:YES
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
    XCTAssertTrue(summary.isBeingDebugged);
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
                                                                                   imperceptibleCount:1
                                                                                              records:@[]];
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
                                                                  isBeingDebugged:NO
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
        @"is_being_debugged" : @NO,
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

- (void)test_decoder_readsIsBeingDebugged
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    dict[@"is_being_debugged"] = @YES;
    KSCrashRunSummary *summary = [KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil];
    XCTAssertNotNil(summary);
    XCTAssertTrue(summary.isBeingDebugged);
}

- (void)test_decoder_toleratesMissingIsBeingDebugged
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    // Payloads written before the field existed lack the key; unknown decodes
    // as NO rather than failing.
    [dict removeObjectForKey:@"is_being_debugged"];
    KSCrashRunSummary *summary = [KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil];
    XCTAssertNotNil(summary);
    XCTAssertFalse(summary.isBeingDebugged);
}

- (void)test_encoder_roundTripsIsBeingDebugged
{
    NSMutableDictionary *dict = [self fullyValidWireDict];
    dict[@"is_being_debugged"] = @YES;
    KSCrashRunSummary *summary = [KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil];

    NSData *encoded = summary.jsonData;
    XCTAssertNotNil(encoded);
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:encoded options:0 error:nil];
    XCTAssertEqualObjects(json[@"is_being_debugged"], @YES);

    KSCrashRunSummary *decoded = [KSCrashRunSummary summaryFromJSONData:encoded error:nil];
    XCTAssertNotNil(decoded);
    XCTAssertTrue(decoded.isBeingDebugged);
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

    // is_being_debugged is optional, but a present non-boolean is a schema
    // violation and rejects the whole summary, same as user_id.
    dict = [self fullyValidWireDict];
    dict[@"is_being_debugged"] = @1;
    XCTAssertNil([KSCrashRunSummary summaryFromJSONData:[self jsonDataFromDict:dict] error:nil]);
}

@end
