//
//  KSCrashRunSummary.m
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

#import "KSCrashRunSummary.h"

// kstermination_reasonToString already returns the snake_case wire strings
// used by the schema, so we reuse it rather than duplicating the mapping.
#import "KSTerminationReason.h"

#import "KSLogger.h"

@implementation KSCrashRunSummaryOutcome

- (instancetype)initWithTerminationReason:(KSTerminationReason)terminationReason
                            cleanShutdown:(BOOL)cleanShutdown
                            fatalReported:(BOOL)fatalReported
                          userPerceptible:(BOOL)userPerceptible
{
    if ((self = [super init])) {
        _terminationReason = terminationReason;
        _cleanShutdown = cleanShutdown;
        _fatalReported = fatalReported;
        _userPerceptible = userPerceptible;
    }
    return self;
}

@end

@implementation KSCrashRunSummaryDurations

- (instancetype)initWithActiveMs:(int64_t)activeMs backgroundMs:(int64_t)backgroundMs
{
    if ((self = [super init])) {
        _activeMs = activeMs;
        _backgroundMs = backgroundMs;
    }
    return self;
}

@end

@implementation KSCrashRunSummarySessions

- (instancetype)initWithPerceptibleCount:(NSInteger)perceptibleCount imperceptibleCount:(NSInteger)imperceptibleCount
{
    if ((self = [super init])) {
        _perceptibleCount = perceptibleCount;
        _imperceptibleCount = imperceptibleCount;
    }
    return self;
}

@end

@implementation KSCrashRunSummaryUsers

- (instancetype)initWithPerceptibleCount:(NSInteger)perceptibleCount imperceptibleCount:(NSInteger)imperceptibleCount
{
    if ((self = [super init])) {
        _perceptibleCount = perceptibleCount;
        _imperceptibleCount = imperceptibleCount;
    }
    return self;
}

@end

@implementation KSCrashRunSummaryApp

- (instancetype)initWithBundleID:(NSString *)bundleID
                         version:(NSString *)version
                    shortVersion:(NSString *)shortVersion
                        hostKind:(KSCrashRunSummaryHostKind)hostKind
{
    if ((self = [super init])) {
        _bundleID = [bundleID copy];
        _version = [version copy];
        _shortVersion = [shortVersion copy];
        _hostKind = hostKind;
    }
    return self;
}

@end

@implementation KSCrashRunSummaryOS

- (instancetype)initWithName:(NSString *)name version:(NSString *)version build:(NSString *)build
{
    if ((self = [super init])) {
        _name = [name copy];
        _version = [version copy];
        _build = [build copy];
    }
    return self;
}

@end

@implementation KSCrashRunSummaryDevice

- (instancetype)initWithModel:(NSString *)model
                  modelFamily:(NSString *)modelFamily
                 architecture:(NSString *)architecture
           binaryArchitecture:(NSString *)binaryArchitecture
                 isTranslated:(BOOL)isTranslated
                 isJailbroken:(BOOL)isJailbroken
{
    if ((self = [super init])) {
        _model = [model copy];
        _modelFamily = [modelFamily copy];
        _architecture = [architecture copy];
        _binaryArchitecture = [binaryArchitecture copy];
        _isTranslated = isTranslated;
        _isJailbroken = isJailbroken;
    }
    return self;
}

@end

@implementation KSCrashRunSummary

- (instancetype)initWithSchemaVersion:(NSInteger)schemaVersion
                           sdkVersion:(NSString *)sdkVersion
                                runID:(NSString *)runID
                             deviceID:(NSString *)deviceID
                               userID:(NSString *)userID
                                users:(KSCrashRunSummaryUsers *)users
                          startedAtMs:(int64_t)startedAtMs
                            endedAtMs:(int64_t)endedAtMs
                              outcome:(KSCrashRunSummaryOutcome *)outcome
                            durations:(KSCrashRunSummaryDurations *)durations
                             sessions:(KSCrashRunSummarySessions *)sessions
                                  app:(KSCrashRunSummaryApp *)app
                                   os:(KSCrashRunSummaryOS *)os
                               device:(KSCrashRunSummaryDevice *)device
{
    if ((self = [super init])) {
        _schemaVersion = schemaVersion;
        _sdkVersion = [sdkVersion copy];
        _runID = [runID copy];
        _deviceID = [deviceID copy];
        _userID = [userID copy];
        _users = users;
        _startedAtMs = startedAtMs;
        _endedAtMs = endedAtMs;
        _outcome = outcome;
        _durations = durations;
        _sessions = sessions;
        _app = app;
        _os = os;
        _device = device;
    }
    return self;
}

#pragma mark - JSON encoding

static NSString *hostKindWireString(KSCrashRunSummaryHostKind kind)
{
    switch (kind) {
        case KSCrashRunSummaryHostKindApp:
            return @"app";
        case KSCrashRunSummaryHostKindExtension:
            return @"extension";
        case KSCrashRunSummaryHostKindXCTest:
            return @"xctest";
        case KSCrashRunSummaryHostKindOther:
        default:
            return @"other";
    }
}

- (NSDictionary<NSString *, id> *)wireDictionary
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:14];
    dict[@"schema_version"] = @(self.schemaVersion);
    dict[@"sdk_version"] = self.sdkVersion;
    dict[@"run_id"] = self.runID;
    dict[@"device_id"] = self.deviceID;
    if (self.userID != nil) {
        dict[@"user_id"] = self.userID;
    }
    dict[@"users"] = @{
        @"perceptible_count" : @(self.users.perceptibleCount),
        @"imperceptible_count" : @(self.users.imperceptibleCount),
    };
    dict[@"started_at_ms"] = @(self.startedAtMs);
    dict[@"ended_at_ms"] = @(self.endedAtMs);
    dict[@"outcome"] = @{
        @"termination_reason" : @(kstermination_reasonToString(self.outcome.terminationReason)),
        // Use @YES / @NO literals so NSJSONSerialization emits JSON booleans
        // rather than serializing the NSNumber as an integer.
        @"clean_shutdown" : self.outcome.cleanShutdown ? @YES : @NO,
        @"fatal_reported" : self.outcome.fatalReported ? @YES : @NO,
        @"user_perceptible" : self.outcome.userPerceptible ? @YES : @NO,
    };
    dict[@"durations_ms"] = @{
        @"active" : @(self.durations.activeMs),
        @"background" : @(self.durations.backgroundMs),
    };
    dict[@"sessions"] = @{
        @"perceptible_count" : @(self.sessions.perceptibleCount),
        @"imperceptible_count" : @(self.sessions.imperceptibleCount),
    };
    dict[@"app"] = @{
        @"bundle_id" : self.app.bundleID,
        @"version" : self.app.version,
        @"short_version" : self.app.shortVersion,
        @"host_kind" : hostKindWireString(self.app.hostKind),
    };
    dict[@"os"] = @{
        @"name" : self.os.name,
        @"version" : self.os.version,
        @"build" : self.os.build,
    };
    dict[@"device"] = @{
        @"model" : self.device.model,
        @"model_family" : self.device.modelFamily,
        @"architecture" : self.device.architecture,
        @"binary_architecture" : self.device.binaryArchitecture,
        @"is_translated" : self.device.isTranslated ? @YES : @NO,
        @"is_jailbroken" : self.device.isJailbroken ? @YES : @NO,
    };
    return dict;
}

- (NSData *)jsonData
{
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self wireDictionary] options:0 error:&error];
    if (data == nil) {
        KSLOG_ERROR(@"Failed to encode RunSummary JSON: %@", error);
    }
    return data;
}

#pragma mark - JSON decoding

static NSString *stringOrEmpty(id value) { return [value isKindOfClass:[NSString class]] ? value : @""; }

static int64_t int64FromValue(id value)
{
    return [value isKindOfClass:[NSNumber class]] ? [(NSNumber *)value longLongValue] : 0;
}

static NSInteger nsIntegerFromValue(id value)
{
    return [value isKindOfClass:[NSNumber class]] ? [(NSNumber *)value integerValue] : 0;
}

static BOOL boolFromValue(id value) { return [value isKindOfClass:[NSNumber class]] && [(NSNumber *)value boolValue]; }

static KSCrashRunSummaryHostKind hostKindFromWireString(NSString *value)
{
    if ([value isEqualToString:@"app"]) {
        return KSCrashRunSummaryHostKindApp;
    }
    if ([value isEqualToString:@"extension"]) {
        return KSCrashRunSummaryHostKindExtension;
    }
    if ([value isEqualToString:@"xctest"]) {
        return KSCrashRunSummaryHostKindXCTest;
    }
    return KSCrashRunSummaryHostKindOther;
}

+ (instancetype)summaryFromJSONData:(NSData *)data error:(NSError **)error
{
    id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![decoded isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *dict = decoded;

    NSDictionary *outcomeDict = dict[@"outcome"];
    NSDictionary *durationsDict = dict[@"durations_ms"];
    NSDictionary *sessionsDict = dict[@"sessions"];
    NSDictionary *usersDict = dict[@"users"];
    NSDictionary *appDict = dict[@"app"];
    NSDictionary *osDict = dict[@"os"];
    NSDictionary *deviceDict = dict[@"device"];
    if (![outcomeDict isKindOfClass:[NSDictionary class]] || ![durationsDict isKindOfClass:[NSDictionary class]] ||
        ![sessionsDict isKindOfClass:[NSDictionary class]] || ![usersDict isKindOfClass:[NSDictionary class]] ||
        ![appDict isKindOfClass:[NSDictionary class]] || ![osDict isKindOfClass:[NSDictionary class]] ||
        ![deviceDict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *reasonString = stringOrEmpty(outcomeDict[@"termination_reason"]);
    KSCrashRunSummaryOutcome *outcome = [[KSCrashRunSummaryOutcome alloc]
        initWithTerminationReason:kstermination_reasonFromString(reasonString.UTF8String)
                    cleanShutdown:boolFromValue(outcomeDict[@"clean_shutdown"])
                    fatalReported:boolFromValue(outcomeDict[@"fatal_reported"])
                  userPerceptible:boolFromValue(outcomeDict[@"user_perceptible"])];

    KSCrashRunSummaryDurations *durations =
        [[KSCrashRunSummaryDurations alloc] initWithActiveMs:int64FromValue(durationsDict[@"active"])
                                                backgroundMs:int64FromValue(durationsDict[@"background"])];

    KSCrashRunSummarySessions *sessions = [[KSCrashRunSummarySessions alloc]
        initWithPerceptibleCount:nsIntegerFromValue(sessionsDict[@"perceptible_count"])
              imperceptibleCount:nsIntegerFromValue(sessionsDict[@"imperceptible_count"])];

    KSCrashRunSummaryUsers *users =
        [[KSCrashRunSummaryUsers alloc] initWithPerceptibleCount:nsIntegerFromValue(usersDict[@"perceptible_count"])
                                              imperceptibleCount:nsIntegerFromValue(usersDict[@"imperceptible_count"])];

    KSCrashRunSummaryApp *app =
        [[KSCrashRunSummaryApp alloc] initWithBundleID:stringOrEmpty(appDict[@"bundle_id"])
                                               version:stringOrEmpty(appDict[@"version"])
                                          shortVersion:stringOrEmpty(appDict[@"short_version"])
                                              hostKind:hostKindFromWireString(stringOrEmpty(appDict[@"host_kind"]))];

    KSCrashRunSummaryOS *os = [[KSCrashRunSummaryOS alloc] initWithName:stringOrEmpty(osDict[@"name"])
                                                                version:stringOrEmpty(osDict[@"version"])
                                                                  build:stringOrEmpty(osDict[@"build"])];

    KSCrashRunSummaryDevice *device =
        [[KSCrashRunSummaryDevice alloc] initWithModel:stringOrEmpty(deviceDict[@"model"])
                                           modelFamily:stringOrEmpty(deviceDict[@"model_family"])
                                          architecture:stringOrEmpty(deviceDict[@"architecture"])
                                    binaryArchitecture:stringOrEmpty(deviceDict[@"binary_architecture"])
                                          isTranslated:boolFromValue(deviceDict[@"is_translated"])
                                          isJailbroken:boolFromValue(deviceDict[@"is_jailbroken"])];

    NSString *userID = [dict[@"user_id"] isKindOfClass:[NSString class]] ? dict[@"user_id"] : nil;

    return [[KSCrashRunSummary alloc] initWithSchemaVersion:nsIntegerFromValue(dict[@"schema_version"])
                                                 sdkVersion:stringOrEmpty(dict[@"sdk_version"])
                                                      runID:stringOrEmpty(dict[@"run_id"])
                                                   deviceID:stringOrEmpty(dict[@"device_id"])
                                                     userID:userID
                                                      users:users
                                                startedAtMs:int64FromValue(dict[@"started_at_ms"])
                                                  endedAtMs:int64FromValue(dict[@"ended_at_ms"])
                                                    outcome:outcome
                                                  durations:durations
                                                   sessions:sessions
                                                        app:app
                                                         os:os
                                                     device:device];
}

@end
