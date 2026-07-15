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
#import "KSLogger.h"

#import <errno.h>
#import <fcntl.h>
#import <inttypes.h>
#import <os/lock.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>

// Cap on a user-id string length. Trims one absurd id before it ever hits
// the disk file. There is intentionally no cap on the *number* of user
// changes or sessions — see the file header for why.
#define KSSESSIONLOG_MAX_USER_ID_LENGTH 512

// Every write ends with '\n'. That newline is the commit boundary: the
// reader treats anything past the file's last '\n' as an incomplete
// write and discards it. See the file header for the shape rationale.
static const uint8_t KSSESSIONLOG_COMMIT_DELIMITER = '\n';

static BOOL isJSONBoolean(id value)
{
    return value != nil && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static BOOL isJSONInteger(id value)
{
    if (![value isKindOfClass:[NSNumber class]] || isJSONBoolean(value)) {
        return NO;
    }
    const char *type = [(NSNumber *)value objCType];
    if (type == NULL || type[0] == 'f' || type[0] == 'd') {
        return NO;
    }
    NSNumber *number = value;
    return [number compare:@(INT64_MIN)] != NSOrderedAscending && [number compare:@(INT64_MAX)] != NSOrderedDescending;
}

typedef struct {
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger position;
} KSCrashSessionLogCursor;

// The inspection path below only advances this cursor over NSData's existing
// bytes. It creates no substrings, temporary NSData objects, or collections,
// so its allocation cost is independent of the number of recorded events.

static BOOL cursorHasBytes(KSCrashSessionLogCursor *cursor, const char *expected, NSUInteger length)
{
    return length <= cursor->length - cursor->position &&
           memcmp(cursor->bytes + cursor->position, expected, length) == 0;
}

static BOOL cursorConsumeBytes(KSCrashSessionLogCursor *cursor, const char *expected, NSUInteger length)
{
    if (!cursorHasBytes(cursor, expected, length)) {
        return NO;
    }
    cursor->position += length;
    return YES;
}

#define KSSESSIONLOG_CURSOR_HAS(cursor, literal) cursorHasBytes((cursor), (literal), sizeof(literal) - 1)
#define KSSESSIONLOG_CURSOR_CONSUME(cursor, literal) cursorConsumeBytes((cursor), (literal), sizeof(literal) - 1)

static BOOL cursorConsumeHexQuad(KSCrashSessionLogCursor *cursor, uint16_t *value)
{
    if (4 > cursor->length - cursor->position) {
        return NO;
    }
    uint16_t result = 0;
    for (NSUInteger i = 0; i < 4; i++) {
        uint8_t c = cursor->bytes[cursor->position++];
        uint8_t digit;
        if (c >= '0' && c <= '9') {
            digit = (uint8_t)(c - '0');
        } else if (c >= 'a' && c <= 'f') {
            digit = (uint8_t)(c - 'a' + 10);
        } else if (c >= 'A' && c <= 'F') {
            digit = (uint8_t)(c - 'A' + 10);
        } else {
            return NO;
        }
        result = (uint16_t)((result << 4) | digit);
    }
    if (value != NULL) {
        *value = result;
    }
    return YES;
}

static BOOL cursorConsumeJSONString(KSCrashSessionLogCursor *cursor)
{
    if (!KSSESSIONLOG_CURSOR_CONSUME(cursor, "\"")) {
        return NO;
    }

    while (cursor->position < cursor->length) {
        uint8_t c = cursor->bytes[cursor->position];
        if (c == '"') {
            cursor->position++;
            return YES;
        }
        if (c == '\\') {
            cursor->position++;
            if (cursor->position >= cursor->length) {
                return NO;
            }
            uint8_t escape = cursor->bytes[cursor->position++];
            if (escape == '"' || escape == '\\' || escape == '/' || escape == 'b' || escape == 'f' || escape == 'n' ||
                escape == 'r' || escape == 't') {
                continue;
            }
            if (escape != 'u') {
                return NO;
            }
            uint16_t codeUnit;
            if (!cursorConsumeHexQuad(cursor, &codeUnit)) {
                return NO;
            }
            if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
                uint16_t lowSurrogate;
                if (!KSSESSIONLOG_CURSOR_CONSUME(cursor, "\\u") || !cursorConsumeHexQuad(cursor, &lowSurrogate) ||
                    lowSurrogate < 0xdc00 || lowSurrogate > 0xdfff) {
                    return NO;
                }
            } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
                return NO;
            }
            continue;
        }
        if (c < 0x20) {
            return NO;
        }
        if (c < 0x80) {
            cursor->position++;
            continue;
        }

        NSUInteger sequenceLength;
        uint8_t secondMinimum = 0x80;
        uint8_t secondMaximum = 0xbf;
        if (c >= 0xc2 && c <= 0xdf) {
            sequenceLength = 2;
        } else if (c >= 0xe0 && c <= 0xef) {
            sequenceLength = 3;
            if (c == 0xe0) {
                secondMinimum = 0xa0;
            } else if (c == 0xed) {
                secondMaximum = 0x9f;
            }
        } else if (c >= 0xf0 && c <= 0xf4) {
            sequenceLength = 4;
            if (c == 0xf0) {
                secondMinimum = 0x90;
            } else if (c == 0xf4) {
                secondMaximum = 0x8f;
            }
        } else {
            return NO;
        }
        if (sequenceLength > cursor->length - cursor->position) {
            return NO;
        }
        uint8_t second = cursor->bytes[cursor->position + 1];
        if (second < secondMinimum || second > secondMaximum) {
            return NO;
        }
        for (NSUInteger i = 2; i < sequenceLength; i++) {
            uint8_t continuation = cursor->bytes[cursor->position + i];
            if (continuation < 0x80 || continuation > 0xbf) {
                return NO;
            }
        }
        cursor->position += sequenceLength;
    }
    return NO;
}

static BOOL cursorConsumeInt64(KSCrashSessionLogCursor *cursor, int64_t *value)
{
    BOOL negative = NO;
    if (cursor->position < cursor->length && cursor->bytes[cursor->position] == '-') {
        negative = YES;
        cursor->position++;
    }
    if (cursor->position >= cursor->length || cursor->bytes[cursor->position] < '0' ||
        cursor->bytes[cursor->position] > '9') {
        return NO;
    }

    uint64_t limit = negative ? (uint64_t)INT64_MAX + 1 : (uint64_t)INT64_MAX;
    uint64_t magnitude = 0;
    if (cursor->bytes[cursor->position] == '0') {
        cursor->position++;
        if (negative || (cursor->position < cursor->length && cursor->bytes[cursor->position] >= '0' &&
                         cursor->bytes[cursor->position] <= '9')) {
            return NO;
        }
    } else {
        while (cursor->position < cursor->length) {
            uint8_t c = cursor->bytes[cursor->position];
            if (c < '0' || c > '9') {
                break;
            }
            uint8_t digit = (uint8_t)(c - '0');
            if (magnitude > (limit - digit) / 10) {
                return NO;
            }
            magnitude = magnitude * 10 + digit;
            cursor->position++;
        }
    }

    if (value != NULL) {
        if (negative && magnitude == (uint64_t)INT64_MAX + 1) {
            *value = INT64_MIN;
        } else if (negative) {
            *value = -(int64_t)magnitude;
        } else {
            *value = (int64_t)magnitude;
        }
    }
    return YES;
}

static void updateMaximumTimestamp(int64_t timestamp, BOOL *hasTimestamp, int64_t *maximum)
{
    if (!*hasTimestamp || timestamp > *maximum) {
        *maximum = timestamp;
        *hasTimestamp = YES;
    }
}

static BOOL cursorConsumeUser(KSCrashSessionLogCursor *cursor, BOOL *hasTimestamp, int64_t *maximum)
{
    if (!KSSESSIONLOG_CURSOR_CONSUME(cursor, "{\"user_id\":") || !cursorConsumeJSONString(cursor) ||
        !KSSESSIONLOG_CURSOR_CONSUME(cursor, ",\"at_ms\":")) {
        return NO;
    }
    int64_t atMs;
    if (!cursorConsumeInt64(cursor, &atMs) || !KSSESSIONLOG_CURSOR_CONSUME(cursor, "}")) {
        return NO;
    }
    updateMaximumTimestamp(atMs, hasTimestamp, maximum);
    return YES;
}

static BOOL cursorConsumeSession(KSCrashSessionLogCursor *cursor, BOOL hasPreviousSession, BOOL *hasUsers,
                                 BOOL *hasTimestamp, int64_t *maximum)
{
    if (hasPreviousSession) {
        int64_t ignoredEnd;
        if (!KSSESSIONLOG_CURSOR_CONSUME(cursor, "],\"ended_at_ms\":") || !cursorConsumeInt64(cursor, &ignoredEnd) ||
            !KSSESSIONLOG_CURSOR_CONSUME(cursor, "},")) {
            return NO;
        }
    }
    if (!KSSESSIONLOG_CURSOR_CONSUME(cursor, "{\"session_id\":") || !cursorConsumeJSONString(cursor) ||
        !KSSESSIONLOG_CURSOR_CONSUME(cursor, ",\"perceptible\":")) {
        return NO;
    }
    if (!KSSESSIONLOG_CURSOR_CONSUME(cursor, "true") && !KSSESSIONLOG_CURSOR_CONSUME(cursor, "false")) {
        return NO;
    }
    if (!KSSESSIONLOG_CURSOR_CONSUME(cursor, ",\"started_at_ms\":")) {
        return NO;
    }
    int64_t startedAtMs;
    if (!cursorConsumeInt64(cursor, &startedAtMs) || !KSSESSIONLOG_CURSOR_CONSUME(cursor, ",\"users\":[")) {
        return NO;
    }
    updateMaximumTimestamp(startedAtMs, hasTimestamp, maximum);

    *hasUsers = NO;
    if (!KSSESSIONLOG_CURSOR_HAS(cursor, "\n")) {
        if (!cursorConsumeUser(cursor, hasTimestamp, maximum)) {
            return NO;
        }
        *hasUsers = YES;
    }
    return KSSESSIONLOG_CURSOR_CONSUME(cursor, "\n");
}

// Escape a Foundation string as a bare JSON string literal (leading and
// trailing quotes included). Uses NSJSONSerialization on a one-element
// array to reuse Foundation's escaping and Unicode handling; the array
// brackets are stripped from the result. Returns nil if the string
// cannot be encoded (e.g. contains an unpaired surrogate that survived
// truncation).
static NSData *jsonEncodedString(NSString *s)
{
    NSData *arrayData = [NSJSONSerialization dataWithJSONObject:@[ s ] options:0 error:NULL];
    if (arrayData.length < 2) {
        return nil;
    }
    return [arrayData subdataWithRange:NSMakeRange(1, arrayData.length - 2)];
}

@implementation KSCrashSessionLog {
    NSString *_path;
    os_unfair_lock _lock;
    int _fd;
    BOOL _closed;
    // File tail state. Bookkeeping is per-writer, not shared across runs;
    // the reader reconstructs the same state from the on-disk bytes.
    BOOL _hasOpenSession;
    BOOL _hasUsersInCurrentSession;
    NSString *_lastUserID;
}

- (nullable instancetype)initForWritingAtPath:(NSString *)path
{
    if ((self = [super init])) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _fd = -1;
        _closed = YES;
        if (path.length == 0) {
            return nil;
        }
        _path = [path copy];
        // O_TRUNC drops any leftover content (previous run's log, older
        // binary Sessions.ksscr, etc.) so we always start from `[\n`.
        int fd = open(_path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND | O_CLOEXEC, 0644);
        if (fd < 0) {
            KSLOG_ERROR(@"Failed to open session log %@: %s", _path, strerror(errno));
            return nil;
        }
        _fd = fd;
        _closed = NO;

        // Seed the file with `[` followed by the commit-delimiter newline.
        // The newline is what makes the seed itself "committed" — without
        // it the reader would see a file with no committed prefix and
        // return an empty sessions array.
        static const uint8_t opener[] = { '[', KSSESSIONLOG_COMMIT_DELIMITER };
        if (write(_fd, opener, sizeof(opener)) != (ssize_t)sizeof(opener)) {
            KSLOG_ERROR(@"Failed to seed session log %@: %s", _path, strerror(errno));
            close(_fd);
            _fd = -1;
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
    [self closeLocked];
    os_unfair_lock_unlock(&_lock);
}

// Mark the writer permanently closed and release the fd. Call under
// @c _lock. Idempotent — a second call is a no-op.
- (void)closeLocked
{
    _closed = YES;
    if (_fd >= 0) {
        close(_fd);
        _fd = -1;
    }
}

- (BOOL)recordSessionBeginWithID:(NSString *)sessionID
                     perceptible:(BOOL)perceptible
                            atMs:(int64_t)atMs
                          userID:(nullable NSString *)userID
{
    if (sessionID.length == 0) {
        return NO;
    }

    NSData *sessionIDData = jsonEncodedString(sessionID);
    if (sessionIDData == nil) {
        return NO;
    }
    NSString *trimmedUser = trimUserID(userID);
    NSData *userIDData = trimmedUser.length > 0 ? jsonEncodedString(trimmedUser) : nil;

    NSMutableData *delta = [NSMutableData dataWithCapacity:256];

    os_unfair_lock_lock(&_lock);
    if (_closed || _fd < 0) {
        os_unfair_lock_unlock(&_lock);
        return NO;
    }

    // If there is a still-open session, close its users array and stamp
    // its ended_at_ms at the incoming atMs (the transition time), then
    // separate with `,` before the new session's opening `{`. If we're
    // opening the first session, no separator is needed.
    if (_hasOpenSession) {
        NSString *seal = [NSString stringWithFormat:@"],\"ended_at_ms\":%lld},", atMs];
        [delta appendData:[seal dataUsingEncoding:NSUTF8StringEncoding]];
    }

    // Session opening: {"session_id":...,"perceptible":...,"started_at_ms":...,"users":[
    [delta appendBytes:"{\"session_id\":" length:14];
    [delta appendData:sessionIDData];
    [delta appendBytes:",\"perceptible\":" length:15];
    [delta appendBytes:perceptible ? "true" : "false" length:perceptible ? 4 : 5];
    NSString *tail = [NSString stringWithFormat:@",\"started_at_ms\":%lld,\"users\":[", atMs];
    [delta appendData:[tail dataUsingEncoding:NSUTF8StringEncoding]];

    // Optional initial user for the new session. Callers pass the current
    // user in here so the first user record lands with the session in a
    // single write, instead of a separate recordUserID call.
    if (userIDData != nil) {
        [delta appendBytes:"{\"user_id\":" length:11];
        [delta appendData:userIDData];
        NSString *userTail = [NSString stringWithFormat:@",\"at_ms\":%lld}", atMs];
        [delta appendData:[userTail dataUsingEncoding:NSUTF8StringEncoding]];
    }

    // Commit delimiter. On a partial write of any of the bytes above, the
    // reader will find its last '\n' at the previous event and discard
    // everything after — including whatever partial fragment made it to
    // disk here.
    [delta appendBytes:&KSSESSIONLOG_COMMIT_DELIMITER length:1];

    ssize_t written = write(_fd, delta.bytes, delta.length);
    if (written != (ssize_t)delta.length) {
        KSLOG_ERROR(@"Failed to write session begin to %@: %s", _path, strerror(errno));
        // A *short* write left partial event bytes past the last '\n'
        // that the fd is still positioned after. If we kept the writer
        // open, the next successful append would end with '\n' and
        // silently commit that fragment as part of a bogus event.
        // Poison the writer instead — subsequent writes return NO, and
        // whatever is on disk stays truncated to the last valid commit
        // by the reader's normal newline recovery.
        [self closeLocked];
        os_unfair_lock_unlock(&_lock);
        return NO;
    }

    _hasOpenSession = YES;
    _hasUsersInCurrentSession = userIDData != nil;
    _lastUserID = userIDData != nil ? trimmedUser : nil;
    os_unfair_lock_unlock(&_lock);
    return YES;
}

- (BOOL)recordUserID:(NSString *)userID atMs:(int64_t)atMs
{
    NSString *trimmed = trimUserID(userID);
    if (trimmed.length == 0) {
        return NO;
    }
    NSData *userIDData = jsonEncodedString(trimmed);
    if (userIDData == nil) {
        return NO;
    }

    NSMutableData *delta = [NSMutableData dataWithCapacity:128];

    os_unfair_lock_lock(&_lock);
    if (_closed || _fd < 0 || !_hasOpenSession) {
        os_unfair_lock_unlock(&_lock);
        return NO;
    }
    if ([_lastUserID isEqualToString:trimmed]) {
        // Dedup adjacent same-id observations. No disk write, no state
        // change; the caller sees YES because the state they wanted (this
        // user is current) is already reflected.
        os_unfair_lock_unlock(&_lock);
        return YES;
    }

    if (_hasUsersInCurrentSession) {
        [delta appendBytes:"," length:1];
    }
    [delta appendBytes:"{\"user_id\":" length:11];
    [delta appendData:userIDData];
    NSString *tail = [NSString stringWithFormat:@",\"at_ms\":%lld}", atMs];
    [delta appendData:[tail dataUsingEncoding:NSUTF8StringEncoding]];
    [delta appendBytes:&KSSESSIONLOG_COMMIT_DELIMITER length:1];

    ssize_t written = write(_fd, delta.bytes, delta.length);
    if (written != (ssize_t)delta.length) {
        KSLOG_ERROR(@"Failed to write user change to %@: %s", _path, strerror(errno));
        // See recordSessionBeginWithID: — a short write leaves partial
        // bytes past the last committed newline. Poison the writer so a
        // subsequent successful append can't commit them.
        [self closeLocked];
        os_unfair_lock_unlock(&_lock);
        return NO;
    }

    _hasUsersInCurrentSession = YES;
    _lastUserID = trimmed;
    os_unfair_lock_unlock(&_lock);
    return YES;
}

- (void)forgetLastUserID
{
    os_unfair_lock_lock(&_lock);
    _lastUserID = nil;
    os_unfair_lock_unlock(&_lock);
}

// Truncate a user_id string to the maximum length while staying on a
// valid composed-character boundary. UTF-16 surrogate pairs (emoji, some
// CJK code points) span two units — a naive substringToIndex: at the
// 512-unit cap can split one and produce an unpaired surrogate that
// NSJSONSerialization then rejects.
static NSString *trimUserID(NSString *userID)
{
    if (userID.length == 0) {
        return @"";
    }
    if (userID.length <= KSSESSIONLOG_MAX_USER_ID_LENGTH) {
        return userID;
    }
    NSRange composed = [userID rangeOfComposedCharacterSequenceAtIndex:KSSESSIONLOG_MAX_USER_ID_LENGTH];
    // If the cap index is inside a composed sequence, composed.location
    // is the start of that sequence — truncate there to keep only
    // complete characters before the cap.
    return [userID substringToIndex:composed.location];
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

+ (KSCrashSessionLogInspection)inspectionForData:(NSData *)data
{
    KSCrashSessionLogInspection inspection = {
        .committedRange = NSMakeRange(0, 0),
        .maxObservedTimestampMs = 0,
        .isValid = NO,
        .hasSessions = NO,
    };
    const uint8_t *bytes = data.bytes;
    NSUInteger committedLength = 0;
    for (NSUInteger i = data.length; i > 0; i--) {
        if (bytes[i - 1] == KSSESSIONLOG_COMMIT_DELIMITER) {
            committedLength = i;
            break;
        }
    }
    if (committedLength == 0) {
        return inspection;
    }
    inspection.committedRange = NSMakeRange(0, committedLength);

    KSCrashSessionLogCursor cursor = {
        .bytes = bytes,
        .length = committedLength,
        .position = 0,
    };
    if (!KSSESSIONLOG_CURSOR_CONSUME(&cursor, "[\n")) {
        return inspection;
    }
    if (cursor.position == cursor.length) {
        inspection.isValid = YES;
        return inspection;
    }

    BOOL hasSession = NO;
    BOOL hasUsers = NO;
    BOOL hasTimestamp = NO;
    int64_t maximumTimestamp = 0;
    while (cursor.position < cursor.length) {
        if (!hasSession || KSSESSIONLOG_CURSOR_HAS(&cursor, "],\"ended_at_ms\":")) {
            if (!cursorConsumeSession(&cursor, hasSession, &hasUsers, &hasTimestamp, &maximumTimestamp)) {
                return inspection;
            }
            hasSession = YES;
            continue;
        }

        if (hasUsers && !KSSESSIONLOG_CURSOR_CONSUME(&cursor, ",")) {
            return inspection;
        }
        if (!cursorConsumeUser(&cursor, &hasTimestamp, &maximumTimestamp) ||
            !KSSESSIONLOG_CURSOR_CONSUME(&cursor, "\n")) {
            return inspection;
        }
        hasUsers = YES;
    }

    inspection.maxObservedTimestampMs = maximumTimestamp;
    inspection.isValid = YES;
    inspection.hasSessions = hasSession;
    return inspection;
}

+ (NSArray<KSCrashRunSummarySession *> *)testcode_sessionsFromDecodedArray:(NSArray *)decoded
{
    NSMutableArray<KSCrashRunSummarySession *> *sessions = [NSMutableArray array];
    for (id entry in decoded) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dict = entry;
        NSString *sessionID = dict[@"session_id"];
        id perceptibleValue = dict[@"perceptible"];
        id startedAtMsValue = dict[@"started_at_ms"];
        id endedAtMsValue = dict[@"ended_at_ms"];
        id usersValue = dict[@"users"];
        if (![sessionID isKindOfClass:[NSString class]] || !isJSONBoolean(perceptibleValue) ||
            !isJSONInteger(startedAtMsValue) || !isJSONInteger(endedAtMsValue) ||
            ![usersValue isKindOfClass:[NSArray class]]) {
            continue;
        }
        BOOL perceptible = [perceptibleValue boolValue];
        int64_t startedAtMs = [startedAtMsValue longLongValue];
        int64_t endedAtMs = [endedAtMsValue longLongValue];
        NSMutableArray<KSCrashRunSummarySessionUser *> *users = [NSMutableArray array];
        for (id userEntry in (NSArray *)usersValue) {
            if (![userEntry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *userDict = userEntry;
            NSString *userID = userDict[@"user_id"];
            id atMsValue = userDict[@"at_ms"];
            if (![userID isKindOfClass:[NSString class]] || !isJSONInteger(atMsValue)) {
                continue;
            }
            int64_t atMs = [atMsValue longLongValue];
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

+ (NSArray<KSCrashRunSummarySession *> *)sessionsFromData:(NSData *)data
{
    KSCrashSessionLogInspection inspection = [self inspectionForData:data];
    if (!inspection.isValid || !inspection.hasSessions) {
        return @[];
    }

    // Object reader path: build the closed JSON, parse, and materialize
    // session/user objects. Parse cost is real here but only paid by
    // callers that actually want the objects (tests, filters), not the
    // startup raw-splice path.
    NSMutableData *closed = [NSMutableData dataWithCapacity:inspection.committedRange.length + 32];
    [self appendSessionsJSONFromData:data
                          inspection:inspection
                        runEndedAtMs:inspection.maxObservedTimestampMs
                            toOutput:closed];

    id decoded = [NSJSONSerialization JSONObjectWithData:closed options:0 error:NULL];
    if (![decoded isKindOfClass:[NSArray class]]) {
        return @[];
    }
    return [self testcode_sessionsFromDecodedArray:(NSArray *)decoded];
}

+ (void)appendSessionsJSONFromData:(NSData *)data runEndedAtMs:(int64_t)runEndedAtMs toOutput:(NSMutableData *)output
{
    KSCrashSessionLogInspection inspection = [self inspectionForData:data];
    [self appendSessionsJSONFromData:data inspection:inspection runEndedAtMs:runEndedAtMs toOutput:output];
}

+ (void)appendSessionsJSONFromData:(NSData *)data
                        inspection:(KSCrashSessionLogInspection)inspection
                      runEndedAtMs:(int64_t)runEndedAtMs
                          toOutput:(NSMutableData *)output
{
    if (inspection.isValid && inspection.hasSessions) {
        if (inspection.committedRange.location > data.length ||
            inspection.committedRange.length > data.length - inspection.committedRange.location) {
            [output appendBytes:"[]" length:2];
            return;
        }
        const uint8_t *bytes = data.bytes;
        [output appendBytes:bytes + inspection.committedRange.location length:inspection.committedRange.length];
    }
    [output appendData:[self closingDataForInspection:inspection runEndedAtMs:runEndedAtMs]];
}

+ (NSData *)closingDataForInspection:(KSCrashSessionLogInspection)inspection runEndedAtMs:(int64_t)runEndedAtMs
{
    if (!inspection.isValid || !inspection.hasSessions) {
        return [NSData dataWithBytes:"[]" length:2];
    }
    // The tail session's ended_at_ms is floored against every observation
    // recorded in the log, so a user event cannot land past its session end.
    int64_t finalizedEnd = runEndedAtMs;
    if (inspection.maxObservedTimestampMs > finalizedEnd) {
        finalizedEnd = inspection.maxObservedTimestampMs;
    }
    char suffix[64];
    int length = snprintf(suffix, sizeof(suffix), "],\"ended_at_ms\":%" PRId64 "}]", finalizedEnd);
    if (length <= 0 || (NSUInteger)length >= sizeof(suffix)) {
        return [NSData data];
    }
    return [NSData dataWithBytes:suffix length:(NSUInteger)length];
}

+ (int64_t)maxObservedTimestampInData:(NSData *)data
{
    KSCrashSessionLogInspection inspection = [self inspectionForData:data];
    return inspection.isValid ? inspection.maxObservedTimestampMs : 0;
}

#pragma mark - Test helpers

// Close the underlying file descriptor while leaving @c _fd's stored
// value intact (i.e., non-negative), so the next `recordSessionBegin`
// or `recordUserID` call will actually attempt a write, hit EBADF from
// the kernel, and exercise the poison-on-write-failure path. Used by
// the short-write regression test — poisoning is triggered by the same
// `write() != expected` check for full failures as for genuine short
// writes, so this closes the loop without needing to actually fill the
// disk.
- (void)_testcode_invalidateFileDescriptor
{
    os_unfair_lock_lock(&_lock);
    if (_fd >= 0) {
        close(_fd);
    }
    os_unfair_lock_unlock(&_lock);
}

@end
