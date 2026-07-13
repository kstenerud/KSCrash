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

#import "KSCrashMonitor_Lifecycle.h"
#import "KSCrashRunContext.h"
#import "KSCrashRunSummary.h"
#import "KSFileUtils.h"
#import "KSLogger.h"

#import <errno.h>
#import <fcntl.h>
#import <os/lock.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

// On-disk format:
//   [ header ][ record ][ record ] ...
//   record : [uint32 len][uint8 type][uint64 monotonicNs][payload]  (len covers
//            type + monotonicNs + payload). The length prefix delimits records;
//            the header's committedSize is the torn-tail boundary.
#define KSSESSIONLOG_MAGIC ((int32_t)'kssl')
static const uint8_t KSSessionLog_CurrentVersion = 1;

// Session id string length incl. null (UUID: 36 + 1). Kept identical to the
// run id length — a session id and a run id are both minted by ksid_generate.
// The static_assert locks the on-disk field size to that shared constant, so
// any change forces a version bump here.
#define KSCRASH_SESSION_ID_LENGTH KSRUNCONTEXT_RUN_ID_LENGTH
_Static_assert(KSCRASH_SESSION_ID_LENGTH == 37, "session id field size is on-disk — bump version to change");

// Record body opens with a 1-byte type and an 8-byte monotonic-ns timestamp.
#define KSSESSIONLOG_RECORD_HEADER_LEN (1 + 8)

// Cap a userID record so one absurd id can't bloat the log unbounded.
#define KSSESSIONLOG_MAX_USER_ID_LENGTH 512

// Cap on the whole file when reading back (session logs are tiny in practice).
#define KSSESSIONLOG_MAX_FILE_LENGTH (4 * 1024 * 1024)

typedef NS_ENUM(uint8_t, KSSessionLogRecordType) {
    KSSessionLogRecordTypeSessionBegin = 1,
    KSSessionLogRecordTypeUser = 2,
};

typedef struct {
    int32_t magic;
    uint8_t version;
    uint8_t reserved[3];
    uint32_t committedSize;  // bytes of committed records following the header
} KSSessionLogHeader;

_Static_assert(sizeof(KSSessionLogHeader) == 12, "KSSessionLogHeader layout changed");

@implementation KSCrashSessionLog {
    int _fd;
    uint32_t _committedSize;
    os_unfair_lock _lock;
}

- (nullable instancetype)initForWritingAtPath:(NSString *)path
{
    if (path.length == 0) {
        return nil;
    }
    if ((self = [super init])) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _committedSize = 0;
        _fd = open(path.fileSystemRepresentation, O_RDWR | O_CREAT | O_TRUNC, 0644);
        if (_fd < 0) {
            KSLOG_ERROR(@"Failed to open session log %@: errno=%d", path, errno);
            return nil;
        }
        if (![self publishHeaderLocked]) {
            close(_fd);
            _fd = -1;
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
    if (_fd >= 0) {
        close(_fd);
        _fd = -1;
    }
    os_unfair_lock_unlock(&_lock);
}

// Call under _lock. Publish the current committed size/count by rewriting the
// header. This is the commit point: only after it returns are the just-written
// record bytes considered valid by a reader.
- (BOOL)publishHeaderLocked
{
    KSSessionLogHeader header = {
        .magic = KSSESSIONLOG_MAGIC,
        .version = KSSessionLog_CurrentVersion,
        .reserved = { 0, 0, 0 },
        .committedSize = _committedSize,
    };
    return pwrite(_fd, &header, sizeof(header), 0) == (ssize_t)sizeof(header);
}

// Call under _lock. Append one record (length prefix + body) at the tail of the
// committed region, THEN publish. The body lands before the header bump, so a
// crash in between leaves the record uncommitted (past committedSize) and a
// reader ignores it.
- (BOOL)appendRecordLocked:(uint8_t)type
               monotonicNs:(uint64_t)monotonicNs
                   payload:(const uint8_t *)payload
                payloadLen:(uint32_t)payloadLen
{
    if (_fd < 0) {
        return NO;
    }
    uint32_t bodyLen = KSSESSIONLOG_RECORD_HEADER_LEN + payloadLen;
    // Refuse to grow the file past the reader's tail-read budget. Beyond that
    // the read would truncate the header off the front and the log would look
    // corrupt on the next launch.
    uint64_t projectedSize = sizeof(KSSessionLogHeader) + (uint64_t)_committedSize + 4ULL + (uint64_t)bodyLen;
    if (projectedSize > KSSESSIONLOG_MAX_FILE_LENGTH) {
        return NO;
    }
    off_t off = (off_t)sizeof(KSSessionLogHeader) + (off_t)_committedSize;

    uint8_t prefixAndHead[4 + KSSESSIONLOG_RECORD_HEADER_LEN];
    memcpy(prefixAndHead, &bodyLen, 4);
    prefixAndHead[4] = type;
    memcpy(prefixAndHead + 5, &monotonicNs, sizeof(monotonicNs));
    if (pwrite(_fd, prefixAndHead, sizeof(prefixAndHead), off) != (ssize_t)sizeof(prefixAndHead)) {
        return NO;
    }
    if (payloadLen > 0) {
        if (pwrite(_fd, payload, payloadLen, off + (off_t)sizeof(prefixAndHead)) != (ssize_t)payloadLen) {
            return NO;
        }
    }

    _committedSize += 4 + bodyLen;
    return [self publishHeaderLocked];
}

- (BOOL)recordSessionBeginWithID:(NSString *)sessionID perceptible:(BOOL)perceptible monotonicNs:(uint64_t)monotonicNs
{
    // Payload: [uint8 perceptible][char sessionID[KSCRASH_SESSION_ID_LENGTH]] —
    // fixed field, zero-padded + null-terminated.
    uint8_t payload[1 + KSCRASH_SESSION_ID_LENGTH] = { 0 };
    payload[0] = perceptible ? 1 : 0;
    strlcpy((char *)(payload + 1), sessionID.UTF8String ?: "", KSCRASH_SESSION_ID_LENGTH);

    os_unfair_lock_lock(&_lock);
    BOOL ok = [self appendRecordLocked:(uint8_t)KSSessionLogRecordTypeSessionBegin
                           monotonicNs:monotonicNs
                               payload:payload
                            payloadLen:sizeof(payload)];
    os_unfair_lock_unlock(&_lock);
    return ok;
}

- (BOOL)recordUserID:(NSString *)userID monotonicNs:(uint64_t)monotonicNs
{
    const char *utf8 = userID.UTF8String;
    if (utf8 == NULL) {
        return NO;
    }
    // strnlen bounds the scan at MAX+1 bytes: if the caller passes a
    // megabyte-long id, we don't walk the whole thing to discover we'd cap it
    // anyway. A return of MAX+1 means "at least MAX+1 bytes present" and
    // triggers the truncation path.
    size_t idLen = strnlen(utf8, KSSESSIONLOG_MAX_USER_ID_LENGTH + 1);
    if (idLen > KSSESSIONLOG_MAX_USER_ID_LENGTH) {
        idLen = KSSESSIONLOG_MAX_USER_ID_LENGTH;
        // If the cut fell inside a multi-byte codepoint, back up to a UTF-8
        // start byte so the reader's initWithBytes:encoding:NSUTF8StringEncoding
        // doesn't reject the record over a torn character.
        while (idLen > 0 && ((uint8_t)utf8[idLen] & 0xC0) == 0x80) {
            idLen--;
        }
    }
    os_unfair_lock_lock(&_lock);
    BOOL ok = [self appendRecordLocked:(uint8_t)KSSessionLogRecordTypeUser
                           monotonicNs:monotonicNs
                               payload:(const uint8_t *)utf8
                            payloadLen:(uint32_t)idLen];
    os_unfair_lock_unlock(&_lock);
    return ok;
}

+ (NSArray<KSCrashRunSummarySession *> *)sessionsAtPath:(NSString *)path
                                     wallClockAtStartNs:(uint64_t)wallClockAtStartNs
                                     monotonicAtStartNs:(uint64_t)monotonicAtStartNs
                                           runEndedAtMs:(int64_t)runEndedAtMs
{
    if (path.length == 0) {
        return @[];
    }
    char *rawData = NULL;
    int rawLength = 0;
    if (!ksfu_readEntireFile(path.fileSystemRepresentation, &rawData, &rawLength, KSSESSIONLOG_MAX_FILE_LENGTH) ||
        rawData == NULL) {
        return @[];
    }

    const uint8_t *bytes = (const uint8_t *)rawData;
    size_t fileLength = (size_t)rawLength;
    if (fileLength < sizeof(KSSessionLogHeader)) {
        free(rawData);
        return @[];
    }
    KSSessionLogHeader header;
    memcpy(&header, bytes, sizeof(header));
    if (header.magic != KSSESSIONLOG_MAGIC || header.version == 0 || header.version > KSSessionLog_CurrentVersion) {
        free(rawData);
        return @[];
    }

    // Torn-tail guard: never trust committedSize past the bytes actually present.
    size_t available = fileLength - sizeof(KSSessionLogHeader);
    size_t committed = header.committedSize < available ? header.committedSize : available;
    const uint8_t *region = bytes + sizeof(KSSessionLogHeader);

    // Replay in order: each SESSION_BEGIN closes the previous session at its
    // start; USER records attach to the currently-open session (buffered until
    // the first session begins). The last open session ends at the run's end.
    NSMutableArray<KSCrashRunSummarySession *> *sessions = [NSMutableArray array];
    NSMutableArray<KSCrashRunSummarySessionUser *> *pendingUsers = [NSMutableArray array];
    NSString *openID = nil;
    BOOL openPerceptible = NO;
    int64_t openStart = 0;
    NSMutableArray<KSCrashRunSummarySessionUser *> *openUsers = nil;

    // Boundary checks use `committed - pos` (safe when pos <= committed) rather
    // than `pos + N` — the latter overflows on 32-bit targets (watchOS
    // arm64_32) where a huge bodyLen would wrap the sum below `committed` and
    // let a corrupt record drive an OOB read into `region`.
    size_t pos = 0;
    while (committed - pos >= 4) {
        uint32_t bodyLen;
        memcpy(&bodyLen, region + pos, 4);
        pos += 4;
        if (bodyLen < KSSESSIONLOG_RECORD_HEADER_LEN || bodyLen > committed - pos) {
            break;  // corrupt or truncated record — stop
        }
        const uint8_t *body = region + pos;
        uint8_t type = body[0];
        uint64_t monotonicNs;
        memcpy(&monotonicNs, body + 1, sizeof(monotonicNs));
        const uint8_t *payload = body + KSSESSIONLOG_RECORD_HEADER_LEN;
        uint32_t payloadLen = bodyLen - KSSESSIONLOG_RECORD_HEADER_LEN;
        int64_t atMs = kslifecycle_epochMsFromMonotonicNs(monotonicNs, wallClockAtStartNs, monotonicAtStartNs);

        if (type == KSSessionLogRecordTypeSessionBegin) {
            // A short payload here means the file is corrupt: the writer
            // always emits a fixed-size body. Stop replay rather than let
            // subsequent USER records attach to the wrong session.
            if (payloadLen < 1 + KSCRASH_SESSION_ID_LENGTH) {
                break;
            }
            BOOL perceptible = payload[0] != 0;
            // Bound the read to the fixed 37-byte field: strnlen stops at the
            // first null OR at the field boundary, so a corrupt record without
            // a null terminator can't splice bytes from the next record into
            // the returned string.
            size_t sessionIDLen = strnlen((const char *)(payload + 1), KSCRASH_SESSION_ID_LENGTH);
            NSString *sessionID =
                [[NSString alloc] initWithBytes:payload + 1 length:sessionIDLen encoding:NSUTF8StringEncoding] ?: @"";
            if (openID != nil) {
                [sessions addObject:[[KSCrashRunSummarySession alloc] initWithSessionID:openID
                                                                            perceptible:openPerceptible
                                                                            startedAtMs:openStart
                                                                              endedAtMs:atMs
                                                                                  users:openUsers]];
            }
            openID = sessionID;
            openPerceptible = perceptible;
            openStart = atMs;
            openUsers = [NSMutableArray array];
            if (pendingUsers.count > 0) {
                [openUsers addObjectsFromArray:pendingUsers];
                [pendingUsers removeAllObjects];
            }
        } else if (type == KSSessionLogRecordTypeUser) {
            NSString *userID =
                [[NSString alloc] initWithBytes:payload length:payloadLen encoding:NSUTF8StringEncoding] ?: @"";
            KSCrashRunSummarySessionUser *user = [[KSCrashRunSummarySessionUser alloc] initWithUserID:userID atMs:atMs];
            [(openUsers ?: pendingUsers) addObject:user];
        }
        // Unknown record types are skipped for forward-compatibility.

        pos += bodyLen;
    }
    free(rawData);

    if (openID != nil) {
        int64_t endedAtMs = runEndedAtMs >= openStart ? runEndedAtMs : openStart;
        [sessions addObject:[[KSCrashRunSummarySession alloc] initWithSessionID:openID
                                                                    perceptible:openPerceptible
                                                                    startedAtMs:openStart
                                                                      endedAtMs:endedAtMs
                                                                          users:openUsers]];
    }
    return sessions;
}

@end
