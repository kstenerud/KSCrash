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
#import "KSCrashRunSummary+Merge.h"

#import "KSCrashReportFields.h"

// kstermination_reasonToString already returns the snake_case wire strings
// used by the schema, so we reuse it rather than duplicating the mapping.
#import "KSTerminationReason.h"

#import "KSJSONCodecObjC.h"
#import "KSLogger.h"

@implementation KSCrashRunSummaryOutcome

- (instancetype)initWithTerminationReason:(KSTerminationReason)terminationReason userPerceptible:(BOOL)userPerceptible
{
    if ((self = [super init])) {
        _terminationReason = terminationReason;
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

@implementation KSCrashRunSummarySession

- (instancetype)initWithSessionID:(NSString *)sessionID
                           userID:(nullable NSString *)userID
                      perceptible:(BOOL)perceptible
                      startedAtMs:(int64_t)startedAtMs
                        endedAtMs:(int64_t)endedAtMs
{
    if ((self = [super init])) {
        _sessionID = [sessionID copy];
        _userID = [userID copy];
        _perceptible = perceptible;
        _startedAtMs = startedAtMs;
        _endedAtMs = endedAtMs;
    }
    return self;
}

@end

@implementation KSCrashRunSummarySessions

- (instancetype)initWithRecords:(NSArray<KSCrashRunSummarySession *> *)records
{
    if ((self = [super init])) {
        _records = [records copy] ?: @[];
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
                          startedAtMs:(int64_t)startedAtMs
                            endedAtMs:(int64_t)endedAtMs
                      isBeingDebugged:(BOOL)isBeingDebugged
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
        _startedAtMs = startedAtMs;
        _endedAtMs = endedAtMs;
        _isBeingDebugged = isBeingDebugged;
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
    dict[KSCrashRunSummaryField_SchemaVersion] = @(self.schemaVersion);
    dict[KSCrashRunSummaryField_SDKVersion] = self.sdkVersion;
    dict[KSCrashRunSummaryField_RunID] = self.runID;
    dict[KSCrashRunSummaryField_DeviceID] = self.deviceID;
    if (self.userID != nil) {
        dict[KSCrashRunSummaryField_UserID] = self.userID;
    }
    dict[KSCrashRunSummaryField_StartedAtMs] = @(self.startedAtMs);
    dict[KSCrashRunSummaryField_EndedAtMs] = @(self.endedAtMs);
    dict[KSCrashRunSummaryField_IsBeingDebugged] = self.isBeingDebugged ? @YES : @NO;
    dict[KSCrashRunSummaryField_Outcome] = @{
        KSCrashRunSummaryField_TerminationReason : @(kstermination_reasonToString(self.outcome.terminationReason)),
        // @YES / @NO wrap CFBoolean so KSJSONCodec emits JSON booleans; a
        // plain @(BOOL) would be an integer NSNumber and serialize as 0/1.
        KSCrashRunSummaryField_UserPerceptible : self.outcome.userPerceptible ? @YES : @NO,
    };
    dict[KSCrashRunSummaryField_DurationsMs] = @{
        KSCrashRunSummaryField_Active : @(self.durations.activeMs),
        KSCrashRunSummaryField_Background : @(self.durations.backgroundMs),
    };
    NSMutableDictionary *sessionsDict = [NSMutableDictionary dictionary];
    if (self.sessions.records.count > 0) {
        NSMutableArray *records = [NSMutableArray arrayWithCapacity:self.sessions.records.count];
        for (KSCrashRunSummarySession *session in self.sessions.records) {
            NSMutableDictionary *record = [@{
                KSCrashRunSummaryField_SessionID : session.sessionID,
                KSCrashRunSummaryField_Perceptible : session.perceptible ? @YES : @NO,
                KSCrashRunSummaryField_StartedAtMs : @(session.startedAtMs),
                KSCrashRunSummaryField_EndedAtMs : @(session.endedAtMs),
            } mutableCopy];
            if (session.userID != nil) {
                record[KSCrashRunSummaryField_UserID] = session.userID;
            }
            [records addObject:record];
        }
        sessionsDict[KSCrashRunSummaryField_Records] = records;
    }
    dict[KSCrashRunSummaryField_Sessions] = sessionsDict;
    dict[KSCrashRunSummaryField_App] = @{
        KSCrashRunSummaryField_BundleID : self.app.bundleID,
        KSCrashRunSummaryField_Version : self.app.version,
        KSCrashRunSummaryField_ShortVersion : self.app.shortVersion,
        KSCrashRunSummaryField_HostKind : hostKindWireString(self.app.hostKind),
    };
    dict[KSCrashRunSummaryField_OS] = @{
        KSCrashRunSummaryField_Name : self.os.name,
        KSCrashRunSummaryField_Version : self.os.version,
        KSCrashRunSummaryField_Build : self.os.build,
    };
    dict[KSCrashRunSummaryField_Device] = @{
        KSCrashRunSummaryField_Model : self.device.model,
        KSCrashRunSummaryField_ModelFamily : self.device.modelFamily,
        KSCrashRunSummaryField_Architecture : self.device.architecture,
        KSCrashRunSummaryField_BinaryArchitecture : self.device.binaryArchitecture,
        KSCrashRunSummaryField_IsTranslated : self.device.isTranslated ? @YES : @NO,
        KSCrashRunSummaryField_IsJailbroken : self.device.isJailbroken ? @YES : @NO,
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
// {"schema_version": true} or {"user_perceptible": 2} are rejected as
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

    NSDictionary *outcomeDict = requiredDictionary(dict, KSCrashRunSummaryField_Outcome, &ok);
    NSDictionary *durationsDict = requiredDictionary(dict, KSCrashRunSummaryField_DurationsMs, &ok);
    NSDictionary *sessionsDict = requiredDictionary(dict, KSCrashRunSummaryField_Sessions, &ok);
    NSDictionary *appDict = requiredDictionary(dict, KSCrashRunSummaryField_App, &ok);
    NSDictionary *osDict = requiredDictionary(dict, KSCrashRunSummaryField_OS, &ok);
    NSDictionary *deviceDict = requiredDictionary(dict, KSCrashRunSummaryField_Device, &ok);
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

    NSInteger schemaVersion = requiredInteger(dict, KSCrashRunSummaryField_SchemaVersion, &ok);
    NSString *sdkVersion = requiredString(dict, KSCrashRunSummaryField_SDKVersion, &ok);
    NSString *runID = requiredString(dict, KSCrashRunSummaryField_RunID, &ok);
    NSString *deviceID = requiredString(dict, KSCrashRunSummaryField_DeviceID, &ok);
    int64_t startedAtMs = requiredInt64(dict, KSCrashRunSummaryField_StartedAtMs, &ok);
    int64_t endedAtMs = requiredInt64(dict, KSCrashRunSummaryField_EndedAtMs, &ok);

    NSString *reasonString = requiredString(outcomeDict, KSCrashRunSummaryField_TerminationReason, &ok);
    // Older .run files also carry clean_shutdown / fatal_reported here; both are ignored.
    BOOL userPerceptible = requiredBool(outcomeDict, KSCrashRunSummaryField_UserPerceptible, &ok);

    int64_t activeMs = requiredInt64(durationsDict, KSCrashRunSummaryField_Active, &ok);
    int64_t backgroundMs = requiredInt64(durationsDict, KSCrashRunSummaryField_Background, &ok);

    NSString *bundleID = requiredString(appDict, KSCrashRunSummaryField_BundleID, &ok);
    NSString *appVersion = requiredString(appDict, KSCrashRunSummaryField_Version, &ok);
    NSString *appShortVersion = requiredString(appDict, KSCrashRunSummaryField_ShortVersion, &ok);
    NSString *hostKindString = requiredString(appDict, KSCrashRunSummaryField_HostKind, &ok);

    NSString *osName = requiredString(osDict, KSCrashRunSummaryField_Name, &ok);
    NSString *osVersion = requiredString(osDict, KSCrashRunSummaryField_Version, &ok);
    NSString *osBuild = requiredString(osDict, KSCrashRunSummaryField_Build, &ok);

    NSString *deviceModel = requiredString(deviceDict, KSCrashRunSummaryField_Model, &ok);
    NSString *deviceModelFamily = requiredString(deviceDict, KSCrashRunSummaryField_ModelFamily, &ok);
    NSString *deviceArchitecture = requiredString(deviceDict, KSCrashRunSummaryField_Architecture, &ok);
    NSString *deviceBinaryArchitecture = requiredString(deviceDict, KSCrashRunSummaryField_BinaryArchitecture, &ok);
    BOOL isTranslated = requiredBool(deviceDict, KSCrashRunSummaryField_IsTranslated, &ok);
    BOOL isJailbroken = requiredBool(deviceDict, KSCrashRunSummaryField_IsJailbroken, &ok);

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
    id userIDValue = dict[KSCrashRunSummaryField_UserID];
    NSString *userID = nil;
    if (userIDValue != nil && userIDValue != (id)kCFNull) {
        if (![userIDValue isKindOfClass:[NSString class]]) {
            if (error != NULL) {
                *error =
                    [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileReadCorruptFileError
                                    userInfo:@{
                                        NSLocalizedDescriptionKey : @"Run summary JSON has a wrong-typed user_id field."
                                    }];
            }
            return nil;
        }
        userID = (NSString *)userIDValue;
    }

    // is_being_debugged was added after the first shipped summaries, so a
    // payload written by an older SDK lacks the key; that decodes as NO
    // rather than failing. A present non-boolean still fails the decode.
    id isBeingDebuggedValue = dict[KSCrashRunSummaryField_IsBeingDebugged];
    BOOL isBeingDebugged = NO;
    if (isBeingDebuggedValue != nil && isBeingDebuggedValue != (id)kCFNull) {
        if (!isJSONBoolean(isBeingDebuggedValue)) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileReadCorruptFileError
                                         userInfo:@{
                                             NSLocalizedDescriptionKey :
                                                 @"Run summary JSON has a wrong-typed is_being_debugged field."
                                         }];
            }
            return nil;
        }
        isBeingDebugged = [(NSNumber *)isBeingDebuggedValue boolValue];
    }

    // Optional per-session records; absent in summaries not yet merged with a
    // session file. A present value must be a well-formed array.
    NSMutableArray<KSCrashRunSummarySession *> *sessionRecords = [NSMutableArray array];
    id recordsValue = sessionsDict[KSCrashRunSummaryField_Records];
    if (recordsValue != nil && recordsValue != (id)kCFNull) {
        if (![recordsValue isKindOfClass:[NSArray class]]) {
            if (error != NULL) {
                *error = [NSError
                    errorWithDomain:NSCocoaErrorDomain
                               code:NSFileReadCorruptFileError
                           userInfo:@{
                               NSLocalizedDescriptionKey : @"Run summary JSON has a wrong-typed sessions.records field."
                           }];
            }
            return nil;
        }
        for (id element in (NSArray *)recordsValue) {
            if (![element isKindOfClass:[NSDictionary class]]) {
                ok = NO;
                break;
            }
            NSDictionary *recordDict = element;
            NSString *sessionID = requiredString(recordDict, KSCrashRunSummaryField_SessionID, &ok);
            BOOL sessionPerceptible = requiredBool(recordDict, KSCrashRunSummaryField_Perceptible, &ok);
            int64_t sessionStartedAtMs = requiredInt64(recordDict, KSCrashRunSummaryField_StartedAtMs, &ok);
            int64_t sessionEndedAtMs = requiredInt64(recordDict, KSCrashRunSummaryField_EndedAtMs, &ok);
            if (!ok) {
                break;
            }
            // user_id is nullable: missing or null is anonymous, but a present
            // non-string fails the decode, matching the top-level user_id.
            id sessionUserIDValue = recordDict[KSCrashRunSummaryField_UserID];
            NSString *sessionUserID = nil;
            if (sessionUserIDValue != nil && sessionUserIDValue != (id)kCFNull) {
                if (![sessionUserIDValue isKindOfClass:[NSString class]]) {
                    ok = NO;
                    break;
                }
                sessionUserID = (NSString *)sessionUserIDValue;
            }
            [sessionRecords addObject:[[KSCrashRunSummarySession alloc] initWithSessionID:sessionID
                                                                                   userID:sessionUserID
                                                                              perceptible:sessionPerceptible
                                                                              startedAtMs:sessionStartedAtMs
                                                                                endedAtMs:sessionEndedAtMs]];
        }
        if (!ok) {
            if (error != NULL) {
                *error =
                    [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileReadCorruptFileError
                                    userInfo:@{
                                        NSLocalizedDescriptionKey : @"Run summary JSON has a malformed session record."
                                    }];
            }
            return nil;
        }
    }

    KSCrashRunSummaryOutcome *outcome = [[KSCrashRunSummaryOutcome alloc]
        initWithTerminationReason:kstermination_reasonFromString(reasonString.UTF8String)
                  userPerceptible:userPerceptible];
    KSCrashRunSummaryDurations *durations = [[KSCrashRunSummaryDurations alloc] initWithActiveMs:activeMs
                                                                                    backgroundMs:backgroundMs];
    KSCrashRunSummarySessions *sessions = [[KSCrashRunSummarySessions alloc] initWithRecords:sessionRecords];
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
                                                startedAtMs:startedAtMs
                                                  endedAtMs:endedAtMs
                                            isBeingDebugged:isBeingDebugged
                                                    outcome:outcome
                                                  durations:durations
                                                   sessions:sessions
                                                        app:app
                                                         os:os
                                                     device:device];
}

- (instancetype)summaryByMergingSessions:(NSArray<KSCrashRunSummarySession *> *)sessions
{
    KSCrashRunSummarySessions *mergedSessions = [[KSCrashRunSummarySessions alloc] initWithRecords:sessions];
    return [[KSCrashRunSummary alloc] initWithSchemaVersion:self.schemaVersion
                                                 sdkVersion:self.sdkVersion
                                                      runID:self.runID
                                                   deviceID:self.deviceID
                                                     userID:self.userID
                                                startedAtMs:self.startedAtMs
                                                  endedAtMs:self.endedAtMs
                                            isBeingDebugged:self.isBeingDebugged
                                                    outcome:self.outcome
                                                  durations:self.durations
                                                   sessions:mergedSessions
                                                        app:self.app
                                                         os:self.os
                                                     device:self.device];
}

@end
