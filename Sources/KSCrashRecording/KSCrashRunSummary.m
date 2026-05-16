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

#import "KSJSONCodecObjC.h"
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
                               userID:(nullable NSString *)userID
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
        // @YES / @NO wrap CFBoolean so KSJSONCodec emits JSON booleans; a
        // plain @(BOOL) would be an integer NSNumber and serialize as 0/1.
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

- (nullable NSData *)jsonData
{
    NSError *error = nil;
    NSData *data = [KSJSONCodec encode:[self wireDictionary] options:KSJSONEncodeOptionNone error:&error];
    if (data == nil) {
        KSLOG_ERROR(@"Failed to encode RunSummary JSON: %@", error);
    }
    return data;
}

#pragma mark - JSON decoding

// Required-key fetchers. Each returns the value cast to the expected type,
// or nil / false via the outOK flag when the key is missing or the value
// has the wrong type. Chaining through outOK lets the decoder short-circuit
// into returning nil, honoring the header contract that malformed input
// (missing required keys, wrong types) never decodes as a "valid" summary
// full of zeros.

// NSJSONSerialization represents JSON booleans as __NSCFBoolean, a subclass
// of NSNumber — so `isKindOfClass:[NSNumber class]` accepts booleans as
// numbers and vice versa. We disambiguate via CFBooleanGetTypeID so
// {"schema_version": true} or {"clean_shutdown": 2} are rejected as
// malformed instead of silently coerced. Callers must null-check before
// invoking; CFGetTypeID(NULL) is undefined.
static BOOL isJSONBoolean(id value) { return CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID(); }

// True only for NSNumber values whose backing type is integral. The schema
// uses integer fields for every scalar (counts, ms timestamps, schema_version),
// so a JSON fractional value like {"started_at_ms": 1.5e9} is malformed and
// must be rejected rather than silently truncated via -longLongValue.
static BOOL isJSONInteger(id value)
{
    if (![value isKindOfClass:[NSNumber class]] || isJSONBoolean(value)) {
        return NO;
    }
    const char *type = [(NSNumber *)value objCType];
    // Float/double carry 'f' / 'd'; every integral type code is something
    // else (c, i, s, l, q, C, I, S, L, Q). Bool ('B') is already filtered.
    return type != NULL && type[0] != 'f' && type[0] != 'd';
}

static NSString *requiredString(NSDictionary *dict, NSString *key, BOOL *outOK)
{
    id value = dict[key];
    if (![value isKindOfClass:[NSString class]]) {
        *outOK = NO;
        return nil;
    }
    return (NSString *)value;
}

static int64_t requiredInt64(NSDictionary *dict, NSString *key, BOOL *outOK)
{
    id value = dict[key];
    if (!isJSONInteger(value)) {
        *outOK = NO;
        return 0;
    }
    return [(NSNumber *)value longLongValue];
}

static NSInteger requiredInteger(NSDictionary *dict, NSString *key, BOOL *outOK)
{
    id value = dict[key];
    if (!isJSONInteger(value)) {
        *outOK = NO;
        return 0;
    }
    return [(NSNumber *)value integerValue];
}

static BOOL requiredBool(NSDictionary *dict, NSString *key, BOOL *outOK)
{
    id value = dict[key];
    if (value == nil || !isJSONBoolean(value)) {
        *outOK = NO;
        return NO;
    }
    return [(NSNumber *)value boolValue];
}

static NSDictionary *requiredDictionary(NSDictionary *dict, NSString *key, BOOL *outOK)
{
    id value = dict[key];
    if (![value isKindOfClass:[NSDictionary class]]) {
        *outOK = NO;
        return nil;
    }
    return (NSDictionary *)value;
}

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

+ (nullable instancetype)summaryFromJSONData:(NSData *)data error:(NSError *_Nullable *_Nullable)error
{
    // IgnoreNullInObject so an explicit `"user_id": null` decodes as missing
    // rather than NSNull; all other null values in required fields still fail
    // the type checks below.
    id decoded = [KSJSONCodec decode:data options:KSJSONDecodeOptionIgnoreNullInObject error:error];
    if (![decoded isKindOfClass:[NSDictionary class]]) {
        if (error != NULL && *error == nil) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadCorruptFileError
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Run summary JSON is not an object." }];
        }
        return nil;
    }
    NSDictionary *dict = decoded;

    BOOL ok = YES;

    NSDictionary *outcomeDict = requiredDictionary(dict, @"outcome", &ok);
    NSDictionary *durationsDict = requiredDictionary(dict, @"durations_ms", &ok);
    NSDictionary *sessionsDict = requiredDictionary(dict, @"sessions", &ok);
    NSDictionary *usersDict = requiredDictionary(dict, @"users", &ok);
    NSDictionary *appDict = requiredDictionary(dict, @"app", &ok);
    NSDictionary *osDict = requiredDictionary(dict, @"os", &ok);
    NSDictionary *deviceDict = requiredDictionary(dict, @"device", &ok);
    if (!ok) {
        if (error != NULL) {
            *error = [NSError
                errorWithDomain:NSCocoaErrorDomain
                           code:NSFileReadCorruptFileError
                       userInfo:@{ NSLocalizedDescriptionKey : @"Run summary JSON is missing a required section." }];
        }
        return nil;
    }

    // Gather every required scalar up front so we can fail once at the end
    // instead of threading `ok` through each nested initializer. Missing any
    // required field → nil return; no partial object is built.

    NSInteger schemaVersion = requiredInteger(dict, @"schema_version", &ok);
    NSString *sdkVersion = requiredString(dict, @"sdk_version", &ok);
    NSString *runID = requiredString(dict, @"run_id", &ok);
    NSString *deviceID = requiredString(dict, @"device_id", &ok);
    int64_t startedAtMs = requiredInt64(dict, @"started_at_ms", &ok);
    int64_t endedAtMs = requiredInt64(dict, @"ended_at_ms", &ok);

    NSString *reasonString = requiredString(outcomeDict, @"termination_reason", &ok);
    BOOL cleanShutdown = requiredBool(outcomeDict, @"clean_shutdown", &ok);
    BOOL fatalReported = requiredBool(outcomeDict, @"fatal_reported", &ok);
    BOOL userPerceptible = requiredBool(outcomeDict, @"user_perceptible", &ok);

    int64_t activeMs = requiredInt64(durationsDict, @"active", &ok);
    int64_t backgroundMs = requiredInt64(durationsDict, @"background", &ok);

    NSInteger sessionsPerceptible = requiredInteger(sessionsDict, @"perceptible_count", &ok);
    NSInteger sessionsImperceptible = requiredInteger(sessionsDict, @"imperceptible_count", &ok);

    NSInteger usersPerceptible = requiredInteger(usersDict, @"perceptible_count", &ok);
    NSInteger usersImperceptible = requiredInteger(usersDict, @"imperceptible_count", &ok);

    NSString *bundleID = requiredString(appDict, @"bundle_id", &ok);
    NSString *appVersion = requiredString(appDict, @"version", &ok);
    NSString *appShortVersion = requiredString(appDict, @"short_version", &ok);
    NSString *hostKindString = requiredString(appDict, @"host_kind", &ok);

    NSString *osName = requiredString(osDict, @"name", &ok);
    NSString *osVersion = requiredString(osDict, @"version", &ok);
    NSString *osBuild = requiredString(osDict, @"build", &ok);

    NSString *deviceModel = requiredString(deviceDict, @"model", &ok);
    NSString *deviceModelFamily = requiredString(deviceDict, @"model_family", &ok);
    NSString *deviceArchitecture = requiredString(deviceDict, @"architecture", &ok);
    NSString *deviceBinaryArchitecture = requiredString(deviceDict, @"binary_architecture", &ok);
    BOOL isTranslated = requiredBool(deviceDict, @"is_translated", &ok);
    BOOL isJailbroken = requiredBool(deviceDict, @"is_jailbroken", &ok);

    if (!ok) {
        if (error != NULL) {
            *error = [NSError
                errorWithDomain:NSCocoaErrorDomain
                           code:NSFileReadCorruptFileError
                       userInfo:@{ NSLocalizedDescriptionKey : @"Run summary JSON is missing a required field." }];
        }
        return nil;
    }

    // user_id is explicitly nullable — missing or null maps to nil, but a
    // present non-string value is a schema violation and fails the decode,
    // matching the strictness of the required-field checks above.
    id userIDValue = dict[@"user_id"];
    NSString *userID = nil;
    if (userIDValue != nil && userIDValue != (id)kCFNull) {
        if (![userIDValue isKindOfClass:[NSString class]]) {
            if (error != NULL) {
                *error = [NSError
                    errorWithDomain:NSCocoaErrorDomain
                               code:NSFileReadCorruptFileError
                           userInfo:@{
                               NSLocalizedDescriptionKey : @"Run summary JSON has a wrong-typed optional field."
                           }];
            }
            return nil;
        }
        userID = (NSString *)userIDValue;
    }

    KSCrashRunSummaryOutcome *outcome = [[KSCrashRunSummaryOutcome alloc]
        initWithTerminationReason:kstermination_reasonFromString(reasonString.UTF8String)
                    cleanShutdown:cleanShutdown
                    fatalReported:fatalReported
                  userPerceptible:userPerceptible];
    KSCrashRunSummaryDurations *durations = [[KSCrashRunSummaryDurations alloc] initWithActiveMs:activeMs
                                                                                    backgroundMs:backgroundMs];
    KSCrashRunSummarySessions *sessions =
        [[KSCrashRunSummarySessions alloc] initWithPerceptibleCount:sessionsPerceptible
                                                 imperceptibleCount:sessionsImperceptible];
    KSCrashRunSummaryUsers *users = [[KSCrashRunSummaryUsers alloc] initWithPerceptibleCount:usersPerceptible
                                                                          imperceptibleCount:usersImperceptible];
    KSCrashRunSummaryApp *app = [[KSCrashRunSummaryApp alloc] initWithBundleID:bundleID
                                                                       version:appVersion
                                                                  shortVersion:appShortVersion
                                                                      hostKind:hostKindFromWireString(hostKindString)];
    KSCrashRunSummaryOS *os = [[KSCrashRunSummaryOS alloc] initWithName:osName version:osVersion build:osBuild];
    KSCrashRunSummaryDevice *device = [[KSCrashRunSummaryDevice alloc] initWithModel:deviceModel
                                                                         modelFamily:deviceModelFamily
                                                                        architecture:deviceArchitecture
                                                                  binaryArchitecture:deviceBinaryArchitecture
                                                                        isTranslated:isTranslated
                                                                        isJailbroken:isJailbroken];

    return [[KSCrashRunSummary alloc] initWithSchemaVersion:schemaVersion
                                                 sdkVersion:sdkVersion
                                                      runID:runID
                                                   deviceID:deviceID
                                                     userID:userID
                                                      users:users
                                                startedAtMs:startedAtMs
                                                  endedAtMs:endedAtMs
                                                    outcome:outcome
                                                  durations:durations
                                                   sessions:sessions
                                                        app:app
                                                         os:os
                                                     device:device];
}

@end
