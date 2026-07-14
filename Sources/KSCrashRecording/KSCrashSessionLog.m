//
//  KSCrashSessionLog.m
//
//  Created by Alexander Cohen on 2026-07-09.
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

#import "KSCrashSessionLog.h"

#import "KSCrashRunSummary.h"
#import "KSJSONCodec.h"
#import "KSLogger.h"

#import <limits.h>
#import <os/lock.h>

// Cap on a user-id string length. Trims one absurd id before it ever hits the
// in-memory array or the disk file.
#define KSSESSIONLOG_MAX_USER_ID_LENGTH 512

@implementation KSCrashSessionLog {
    NSString *_path;
    NSMutableArray<NSMutableDictionary *> *_sessions;
    os_unfair_lock _lock;
    BOOL _closed;
}

- (nullable instancetype)initForWritingAtPath:(NSString *)path
{
    if ((self = [super init])) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _closed = YES;
        if (path.length == 0) {
            return nil;
        }
        _path = [path copy];
        _sessions = [NSMutableArray array];
        _closed = NO;
        if (![self syncLocked]) {
            _closed = YES;
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

- (void)close
{
    os_unfair_lock_lock(&_lock);
    _closed = YES;
    os_unfair_lock_unlock(&_lock);
}

- (BOOL)recordSessionBeginWithID:(NSString *)sessionID
                     perceptible:(BOOL)perceptible
                            atMs:(int64_t)atMs
                          userID:(nullable NSString *)userID
{
    if (sessionID.length == 0) {
        return NO;
    }

    os_unfair_lock_lock(&_lock);
    if (_closed) {
        os_unfair_lock_unlock(&_lock);
        return NO;
    }

    // Close the previously-open session at the new session's start. The
    // ended_at_ms on any earlier session was already frozen when it was
    // succeeded, so only the tail can advance.
    NSMutableDictionary *previous = _sessions.lastObject;
    if (previous != nil) {
        previous[@"ended_at_ms"] = @(atMs);
    }

    NSMutableArray *users = [NSMutableArray array];
    NSString *trimmedUser = trimUserID(userID);
    if (trimmedUser.length > 0) {
        [users addObject:@{ @"user_id" : trimmedUser, @"at_ms" : @(atMs) }];
    }

    [_sessions addObject:[@{
                   @"session_id" : sessionID,
                   @"perceptible" : perceptible ? @YES : @NO,
                   @"started_at_ms" : @(atMs),
                   @"ended_at_ms" : @(atMs),
                   @"users" : users,
               } mutableCopy]];

    BOOL ok = [self syncLocked];
    os_unfair_lock_unlock(&_lock);
    return ok;
}

- (BOOL)recordUserID:(NSString *)userID atMs:(int64_t)atMs
{
    NSString *trimmed = trimUserID(userID);
    if (trimmed.length == 0) {
        return NO;
    }

    os_unfair_lock_lock(&_lock);
    if (_closed || _sessions.count == 0) {
        os_unfair_lock_unlock(&_lock);
        return NO;
    }

    NSMutableDictionary *current = _sessions.lastObject;
    NSMutableArray *users = current[@"users"];
    NSDictionary *last = users.lastObject;
    if ([last[@"user_id"] isEqualToString:trimmed]) {
        os_unfair_lock_unlock(&_lock);
        return YES;  // dedup adjacent same-id calls
    }

    [users addObject:@{ @"user_id" : trimmed, @"at_ms" : @(atMs) }];
    current[@"ended_at_ms"] = @(atMs);

    BOOL ok = [self syncLocked];
    os_unfair_lock_unlock(&_lock);
    return ok;
}

// Call under _lock. Serialize `_sessions` as JSON and atomically replace the
// file at `_path`. NSDataWritingAtomic writes to a temp file and renames on
// success, so the file on disk is always either the last-committed state or
// (from before this call) the previous one — never torn.
- (BOOL)syncLocked
{
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:_sessions options:0 error:&err];
    if (data == nil) {
        KSLOG_ERROR(@"Failed to serialize session log: %@", err);
        return NO;
    }
    if (![data writeToFile:_path options:NSDataWritingAtomic error:&err]) {
        KSLOG_ERROR(@"Failed to write session log %@: %@", _path, err);
        return NO;
    }
    return YES;
}

static NSString *trimUserID(NSString *userID)
{
    if (userID.length == 0) {
        return @"";
    }
    if (userID.length <= KSSESSIONLOG_MAX_USER_ID_LENGTH) {
        return userID;
    }
    return [userID substringToIndex:KSSESSIONLOG_MAX_USER_ID_LENGTH];
}

+ (NSArray<KSCrashRunSummarySession *> *)sessionsAtPath:(NSString *)path
{
    if (path.length == 0) {
        return @[];
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (data.length == 0) {
        return @[];
    }
    return [self sessionsFromData:data];
}

+ (NSArray<KSCrashRunSummarySession *> *)sessionsFromData:(NSData *)data
{
    id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![decoded isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<KSCrashRunSummarySession *> *sessions = [NSMutableArray array];
    for (id entry in (NSArray *)decoded) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dict = entry;
        NSString *sessionID = dict[@"session_id"];
        if (![sessionID isKindOfClass:[NSString class]]) {
            continue;
        }
        BOOL perceptible = [dict[@"perceptible"] boolValue];
        int64_t startedAtMs = [dict[@"started_at_ms"] longLongValue];
        int64_t endedAtMs = [dict[@"ended_at_ms"] longLongValue];
        NSMutableArray<KSCrashRunSummarySessionUser *> *users = [NSMutableArray array];
        for (id userEntry in (NSArray *)dict[@"users"]) {
            if (![userEntry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *userDict = userEntry;
            NSString *userID = userDict[@"user_id"];
            if (![userID isKindOfClass:[NSString class]]) {
                continue;
            }
            int64_t atMs = [userDict[@"at_ms"] longLongValue];
            [users addObject:[[KSCrashRunSummarySessionUser alloc] initWithUserID:userID atMs:atMs]];
        }

        [sessions addObject:[[KSCrashRunSummarySession alloc] initWithSessionID:sessionID
                                                                    perceptible:perceptible
                                                                    startedAtMs:startedAtMs
                                                                      endedAtMs:endedAtMs
                                                                          users:users]];
    }
    return sessions;
}

typedef struct {
    int depth;
    bool rootIsArray;
    bool rootEnded;
} KSSessionJSONValidationContext;

static int validationElement(const char *name, void *userData)
{
    (void)name;
    (void)userData;
    return KSJSON_OK;
}

static int validationBoolean(const char *name, bool value, void *userData)
{
    (void)value;
    return validationElement(name, userData);
}

static int validationFloat(const char *name, double value, void *userData)
{
    (void)value;
    return validationElement(name, userData);
}

static int validationInteger(const char *name, int64_t value, void *userData)
{
    (void)value;
    return validationElement(name, userData);
}

static int validationUnsignedInteger(const char *name, uint64_t value, void *userData)
{
    (void)value;
    return validationElement(name, userData);
}

static int validationString(const char *name, const char *value, void *userData)
{
    (void)value;
    return validationElement(name, userData);
}

static int validationBeginObject(const char *name, void *userData)
{
    (void)name;
    KSSessionJSONValidationContext *context = userData;
    context->depth++;
    return KSJSON_OK;
}

static int validationBeginArray(const char *name, void *userData)
{
    (void)name;
    KSSessionJSONValidationContext *context = userData;
    if (context->depth == 0) {
        context->rootIsArray = true;
    }
    context->depth++;
    return KSJSON_OK;
}

static int validationEndContainer(void *userData)
{
    KSSessionJSONValidationContext *context = userData;
    context->depth--;
    if (context->depth == 0) {
        context->rootEnded = true;
    }
    return KSJSON_OK;
}

static int validationEndData(void *userData)
{
    KSSessionJSONValidationContext *context = userData;
    return context->rootIsArray && context->rootEnded && context->depth == 0 ? KSJSON_OK : KSJSON_ERROR_INVALID_DATA;
}

+ (BOOL)isValidSessionsData:(NSData *)data
{
    if (data.length == 0 || data.length > INT_MAX) {
        return NO;
    }
    const uint8_t *bytes = data.bytes;
    NSUInteger first = 0;
    while (first < data.length &&
           (bytes[first] == ' ' || bytes[first] == '\t' || bytes[first] == '\r' || bytes[first] == '\n')) {
        first++;
    }
    NSUInteger last = data.length;
    while (last > first &&
           (bytes[last - 1] == ' ' || bytes[last - 1] == '\t' || bytes[last - 1] == '\r' || bytes[last - 1] == '\n')) {
        last--;
    }
    if (first == last || bytes[first] != '[' || bytes[last - 1] != ']') {
        return NO;
    }
    KSSessionJSONValidationContext context = { 0 };
    KSJSONDecodeCallbacks callbacks = {
        .onBooleanElement = validationBoolean,
        .onFloatingPointElement = validationFloat,
        .onIntegerElement = validationInteger,
        .onUnsignedIntegerElement = validationUnsignedInteger,
        .onNullElement = validationElement,
        .onStringElement = validationString,
        .onBeginObject = validationBeginObject,
        .onBeginArray = validationBeginArray,
        .onEndContainer = validationEndContainer,
        .onEndData = validationEndData,
    };
    char stringBuffer[4096];
    return ksjson_decode(data.bytes, (int)data.length, stringBuffer, sizeof(stringBuffer), &callbacks, &context,
                         NULL) == KSJSON_OK;
}

@end
