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
#import <os/lock.h>
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

// Backwards search for a JSON integer value keyed by @c keyNeedle. The
// needle must include the trailing colon (e.g. `"at_ms":`); anchoring on
// the colon keeps the search from matching the key text inside a string
// value like `"user_id":"at_ms"`. Returns YES with @c *value set on
// success.
static BOOL findLastJSONInteger(NSData *data, const char *keyNeedle, int64_t *value)
{
    NSData *needle = [NSData dataWithBytes:keyNeedle length:strlen(keyNeedle)];
    NSRange keyRange = [data rangeOfData:needle options:NSDataSearchBackwards range:NSMakeRange(0, data.length)];
    if (keyRange.location == NSNotFound) {
        return NO;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger start = NSMaxRange(keyRange);
    while (start < data.length &&
           (bytes[start] == ' ' || bytes[start] == '\t' || bytes[start] == '\r' || bytes[start] == '\n')) {
        start++;
    }

    NSUInteger end = start;
    if (end < data.length && bytes[end] == '-') {
        end++;
    }
    NSUInteger firstDigit = end;
    while (end < data.length && bytes[end] >= '0' && bytes[end] <= '9') {
        end++;
    }
    if (end == firstDigit) {
        return NO;
    }

    NSData *numberData = [data subdataWithRange:NSMakeRange(start, end - start)];
    NSString *number = [[NSString alloc] initWithData:numberData encoding:NSUTF8StringEncoding];
    if (number == nil) {
        return NO;
    }
    if (value != NULL) {
        *value = number.longLongValue;
    }
    return YES;
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

// Return the range of @c data ending at (and including) the file's last
// commit-delimiter newline. Everything past that newline is treated as an
// uncommitted partial write and dropped. Returns an empty range if @c data
// is empty, doesn't start with the outer `[`, or contains no newline
// (which means even the initial seed's '\n' didn't land — nothing is
// safely readable).
static NSData *committedPrefix(NSData *data)
{
    if (data.length == 0) {
        return data;
    }
    const uint8_t *bytes = data.bytes;
    if (bytes[0] != '[') {
        return [data subdataWithRange:NSMakeRange(0, 0)];
    }
    NSInteger i = (NSInteger)data.length - 1;
    while (i >= 0 && bytes[i] != KSSESSIONLOG_COMMIT_DELIMITER) {
        i--;
    }
    if (i < 0) {
        return [data subdataWithRange:NSMakeRange(0, 0)];
    }
    return [data subdataWithRange:NSMakeRange(0, (NSUInteger)(i + 1))];
}

// YES when the committed prefix carries no session data — either it is
// empty (garbage or no committed newline) or it is only the outer `[`
// plus whitespace (writer opened the file but no session_begin landed).
// The scan stops at the first non-whitespace byte after `[`, so this is
// O(1) even on large files.
static BOOL isEmptyCommittedPrefix(NSData *committed)
{
    if (committed.length == 0) {
        return YES;
    }
    const uint8_t *bytes = committed.bytes;
    if (bytes[0] != '[') {
        return YES;
    }
    for (NSUInteger i = 1; i < committed.length; i++) {
        uint8_t c = bytes[i];
        if (c != ' ' && c != '\t' && c != '\r' && c != '\n') {
            return NO;
        }
    }
    return YES;
}

// Append the closing suffix `],"ended_at_ms":<N>}]` that finalizes the
// implicit-array shape from @c committed against @c endedAtMs. Assumes
// @c committed already ends in a delimiter newline (which is JSON
// whitespace) so `]` closes the tail session's users array cleanly.
static void appendClosingSuffix(NSMutableData *output, int64_t endedAtMs)
{
    NSString *suffix = [NSString stringWithFormat:@"],\"ended_at_ms\":%lld}]", endedAtMs];
    [output appendData:[suffix dataUsingEncoding:NSUTF8StringEncoding]];
}

// Highest event timestamp observable in the committed portion of @c data
// — the max of the last `"started_at_ms":` and the last `"at_ms":` in
// the file, or 0 if neither is present. Callers use this to floor the
// tail session's ended_at_ms (so a user event cannot land past its own
// session's end) and to bump the outer run's ended_at_ms when a user
// observation is more recent than any monitor-observed transition.
static int64_t maxObservedTimestampInCommitted(NSData *committed)
{
    int64_t observed = 0;
    int64_t tailStart = 0;
    if (findLastJSONInteger(committed, "\"started_at_ms\":", &tailStart) && tailStart > observed) {
        observed = tailStart;
    }
    int64_t lastAtMs = 0;
    if (findLastJSONInteger(committed, "\"at_ms\":", &lastAtMs) && lastAtMs > observed) {
        observed = lastAtMs;
    }
    return observed;
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

+ (NSArray<KSCrashRunSummarySession *> *)sessionsFromData:(NSData *)data
{
    NSData *committed = committedPrefix(data);
    if (isEmptyCommittedPrefix(committed)) {
        return @[];
    }

    // Object reader path: build the closed JSON, parse, and materialize
    // session/user objects. Parse cost is real here but only paid by
    // callers that actually want the objects (tests, filters), not the
    // startup raw-splice path.
    int64_t tailEnd = maxObservedTimestampInCommitted(committed);
    NSMutableData *closed = [committed mutableCopy];
    appendClosingSuffix(closed, tailEnd);

    id decoded = [NSJSONSerialization JSONObjectWithData:closed options:0 error:NULL];
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

+ (void)appendSessionsJSONFromData:(NSData *)data runEndedAtMs:(int64_t)runEndedAtMs toOutput:(NSMutableData *)output
{
    NSData *committed = committedPrefix(data);
    if (isEmptyCommittedPrefix(committed)) {
        [output appendBytes:"[]" length:2];
        return;
    }
    // The tail session's ended_at_ms is stamped with the outer run's end
    // time, floored against any observation still recorded in the log —
    // in particular the last user event. Without that floor, a user
    // observation more recent than any monitor-observed run transition
    // (e.g. OOM shortly after a user change with the resource monitor
    // disabled) would emit `user.at_ms > session.ended_at_ms`.
    int64_t finalizedEnd = runEndedAtMs;
    int64_t observed = maxObservedTimestampInCommitted(committed);
    if (observed > finalizedEnd) {
        finalizedEnd = observed;
    }
    [output appendData:committed];
    appendClosingSuffix(output, finalizedEnd);
}

+ (int64_t)maxObservedTimestampInData:(NSData *)data
{
    if (data.length == 0) {
        return 0;
    }
    NSData *committed = committedPrefix(data);
    if (committed.length == 0) {
        return 0;
    }
    return maxObservedTimestampInCommitted(committed);
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
