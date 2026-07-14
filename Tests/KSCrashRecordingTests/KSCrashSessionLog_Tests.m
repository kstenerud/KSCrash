//
//  KSCrashSessionLog_Tests.m
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

#import <XCTest/XCTest.h>

#import <fcntl.h>
#import <string.h>
#import <unistd.h>

#import "KSCrashRunSummary.h"
#import "KSCrashSessionLog.h"

@interface KSCrashSessionLog (TestHelpers)
- (void)_testcode_invalidateFileDescriptor;
@end

@interface KSCrashSessionLog_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@property(nonatomic, strong) NSString *path;
@end

@implementation KSCrashSessionLog_Tests

- (void)setUp
{
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.path = [self.tempDir stringByAppendingPathComponent:@"Sessions"];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)test_sessions_builtFromLogInOrderWithUsers
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertNotNil(log);
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:nil]);
    XCTAssertTrue([log recordUserID:@"alice" atMs:2]);
    XCTAssertTrue([log recordUserID:@"bob" atMs:3]);
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-B" perceptible:NO atMs:5 userID:nil]);
    [log close];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 2u);

    KSCrashRunSummarySession *a = sessions[0];
    XCTAssertEqualObjects(a.sessionID, @"sess-A");
    XCTAssertTrue(a.perceptible);
    XCTAssertEqual(a.startedAtMs, 1);
    XCTAssertEqual(a.endedAtMs, 5);  // closed at sess-B's start
    XCTAssertEqual(a.users.count, 2u);
    XCTAssertEqualObjects(a.users[0].userID, @"alice");
    XCTAssertEqual(a.users[0].atMs, 2);
    XCTAssertEqualObjects(a.users[1].userID, @"bob");

    KSCrashRunSummarySession *b = sessions[1];
    XCTAssertEqualObjects(b.sessionID, @"sess-B");
    XCTAssertFalse(b.perceptible);
    XCTAssertEqual(b.startedAtMs, 5);
    XCTAssertEqual(b.endedAtMs, 5);  // still-open session's end reflects last write
    XCTAssertEqual(b.users.count, 0u);
}

- (void)test_newSessionInheritsCurrentUser
{
    // Callers of recordSessionBeginWithID:...:userID: pass the current user
    // in with the new session, so the first user record in a new session is
    // written up front rather than as a separate USER call.
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:@"alice"]);
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-B" perceptible:NO atMs:5 userID:@"alice"]);
    [log close];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 2u);
    XCTAssertEqual(sessions[0].users.count, 1u);
    XCTAssertEqualObjects(sessions[0].users[0].userID, @"alice");
    XCTAssertEqual(sessions[1].users.count, 1u);
    XCTAssertEqualObjects(sessions[1].users[0].userID, @"alice");
}

- (void)test_recordUserID_withoutOpenSession_isDropped
{
    // Users observed before the first SESSION_BEGIN don't attach to anything:
    // callers hand the current user in when they open the first session.
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertFalse([log recordUserID:@"alice" atMs:1]);
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:5 userID:@"bob"]);
    [log close];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions[0].users.count, 1u);
    XCTAssertEqualObjects(sessions[0].users[0].userID, @"bob");
}

- (void)test_recordUserID_dedupsAdjacentSameID
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:@"alice"]);
    XCTAssertTrue([log recordUserID:@"alice" atMs:2]);  // no-op — already current
    XCTAssertTrue([log recordUserID:@"bob" atMs:3]);
    XCTAssertTrue([log recordUserID:@"bob" atMs:4]);  // no-op — already current
    [log close];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions[0].users.count, 2u);
    XCTAssertEqualObjects(sessions[0].users[0].userID, @"alice");
    XCTAssertEqualObjects(sessions[0].users[1].userID, @"bob");
}

- (void)test_emptyLog_readsAsNoSessions
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertNotNil(log);
    [log close];
    XCTAssertEqual([KSCrashSessionLog sessionsAtPath:self.path].count, 0u);
}

- (void)test_open_truncatesExistingLog
{
    KSCrashSessionLog *first = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([first recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:nil]);
    [first close];

    KSCrashSessionLog *second = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertNotNil(second);
    [second close];
    XCTAssertEqual([KSCrashSessionLog sessionsAtPath:self.path].count, 0u);
}

- (void)test_missingFile_readsAsNoSessions
{
    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:@"/nonexistent/path/Sessions"];
    XCTAssertEqual(sessions.count, 0u);
}

- (void)test_malformedFile_readsAsNoSessions
{
    // A leftover binary-format Sessions.ksscr from an older SDK, or any garbage,
    // isn't valid JSON — the reader treats it as no per-session detail rather
    // than crashing or returning something misleading.
    NSData *junk = [@"kssl\x01not-json" dataUsingEncoding:NSUTF8StringEncoding];
    [junk writeToFile:self.path atomically:YES];
    XCTAssertEqual([KSCrashSessionLog sessionsAtPath:self.path].count, 0u);
}

- (void)test_partialWriteAfterUserRecord_recoversPreviousEvents
{
    // Simulate a crash mid-write partway through a user_change delta: the
    // file has the previous user's `}` followed by a partial user object.
    // Reader should keep the completed user and drop the fragment.
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:@"alice"]);
    XCTAssertTrue([log recordUserID:@"bob" atMs:5]);
    [log close];

    NSData *good = [NSData dataWithContentsOfFile:self.path];
    NSMutableData *corrupt = [good mutableCopy];
    [corrupt appendData:[@",{\"user_id\":\"cha" dataUsingEncoding:NSUTF8StringEncoding]];
    [corrupt writeToFile:self.path atomically:YES];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions[0].users.count, 2u);
    XCTAssertEqualObjects(sessions[0].users[0].userID, @"alice");
    XCTAssertEqualObjects(sessions[0].users[1].userID, @"bob");
}

- (void)test_partialSessionOpening_afterSeal_discardsPartialTransition
{
    // Simulate a mid-session_begin-transition partial write: the delta
    // that seals the current session and opens the next one is one
    // atomic write. If it lands only partially (no trailing '\n' commit
    // delimiter), the reader must drop the whole thing and surface the
    // pre-transition state, since the seal and the new opening are
    // meaningless without each other.
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:nil]);
    XCTAssertTrue([log recordUserID:@"alice" atMs:5]);
    [log close];

    NSData *good = [NSData dataWithContentsOfFile:self.path];
    NSMutableData *corrupt = [good mutableCopy];
    [corrupt appendData:[@"],\"ended_at_ms\":10},{\"session_id\":\"s" dataUsingEncoding:NSUTF8StringEncoding]];
    [corrupt writeToFile:self.path atomically:YES];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqualObjects(sessions[0].sessionID, @"sess-A");
    // Session-A is still the (open) tail; its inferred end is the last
    // committed observation, alice's at_ms.
    XCTAssertEqual(sessions[0].endedAtMs, 5);
    XCTAssertEqual(sessions[0].users.count, 1u);
    XCTAssertEqualObjects(sessions[0].users.firstObject.userID, @"alice");
}

- (void)test_forgetLastUserID_breaksAdjacentSameIDDedup
{
    // The lifecycle monitor calls -forgetLastUserID on sign-out so a
    // subsequent alice → nil → alice sequence records the second alice
    // activation. Without this the second alice matches the stashed
    // _lastUserID and gets deduped out of the log, and downstream loses
    // the "when did this user become active again" timestamp.
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:@"alice"]);
    XCTAssertTrue([log recordUserID:@"alice" atMs:2]);  // dedup — alice is current
    [log forgetLastUserID];
    XCTAssertTrue([log recordUserID:@"alice" atMs:5]);  // not dedup — logout broke it
    [log close];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions[0].users.count, 2u);
    XCTAssertEqualObjects(sessions[0].users[0].userID, @"alice");
    XCTAssertEqual(sessions[0].users[0].atMs, 1);
    XCTAssertEqualObjects(sessions[0].users[1].userID, @"alice");
    XCTAssertEqual(sessions[0].users[1].atMs, 5);
}

- (void)test_shortWritePoisonsWriterSoLaterWritesDontCommitFragment
{
    // If a `write()` returns short (disk full, RLIMIT_FSIZE crossed, etc.)
    // the partial bytes are already on disk past the last committed
    // newline. If the writer stayed open, the *next* successful write
    // would end with its own '\n' and silently commit the earlier
    // fragment as part of a bogus event. The writer must poison itself
    // on any non-full write so subsequent calls return NO and the on-
    // disk state stays truncatable to the last valid commit.
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:@"alice"]);

    // Force the next write() to fail by closing the underlying fd out
    // from under the writer. write() will return -1 (EBADF), which the
    // poison path treats the same as a genuine short write.
    [log _testcode_invalidateFileDescriptor];

    XCTAssertFalse([log recordUserID:@"bob" atMs:2]);    // failure triggers poison
    XCTAssertFalse([log recordUserID:@"carol" atMs:3]);  // subsequent writes stay refused
    XCTAssertFalse([log recordSessionBeginWithID:@"sess-B" perceptible:YES atMs:4 userID:nil]);
    [log close];

    // Reader still sees the pre-failure state — alice's activation
    // survives; nothing bogus was committed by the poisoned writer.
    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqualObjects(sessions[0].sessionID, @"sess-A");
    XCTAssertEqual(sessions[0].users.count, 1u);
    XCTAssertEqualObjects(sessions[0].users.firstObject.userID, @"alice");
}

- (void)test_userIDTruncationRespectsComposedCharacterBoundary
{
    // The 512-UTF-16-unit cap must not split a surrogate pair. A user_id
    // built from 511 ASCII chars followed by an emoji (which occupies two
    // code units) sits with its start at index 511 and its second half
    // at index 512 — a naive substringToIndex:512 would leave a lone
    // high surrogate that NSJSONSerialization rejects.
    NSMutableString *userID = [NSMutableString stringWithCapacity:600];
    for (NSUInteger i = 0; i < 511; i++) {
        [userID appendString:@"a"];
    }
    [userID appendString:@"\U0001F680"];  // 🚀 — surrogate pair
    XCTAssertEqual(userID.length, 513u);

    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:userID]);
    [log close];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions[0].users.count, 1u);
    // The emoji sits astride the 512-unit cap and gets dropped whole;
    // what survives is exactly the 511 'a' chars, with no unpaired
    // surrogate half that would have made NSJSONSerialization reject
    // the event.
    XCTAssertEqual(sessions[0].users.firstObject.userID.length, 511u);
}

- (void)test_garbageAppendedToValidTail_recoversPreviousEvents
{
    // Something clobbered the file's tail with non-JSON bytes. Reader
    // should still return the events that were recorded before the
    // clobber, not throw the whole log away.
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:@"alice"]);
    [log close];

    NSData *good = [NSData dataWithContentsOfFile:self.path];
    NSMutableData *corrupt = [good mutableCopy];
    [corrupt appendData:[@" not-json !!" dataUsingEncoding:NSUTF8StringEncoding]];
    [corrupt writeToFile:self.path atomically:YES];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqualObjects(sessions[0].sessionID, @"sess-A");
    XCTAssertEqualObjects(sessions[0].users.firstObject.userID, @"alice");
}

- (void)test_userIDWithJSONReservedChars_isEscapedAndRoundtripped
{
    // A user_id with quotes, backslashes, and newlines must be encoded so
    // the appended delta stays valid JSON. Round-trip through the reader
    // to confirm the escape and unescape agree.
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    NSString *nasty = @"weird\"user\\with\nnewline";
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:nasty]);
    [log close];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqualObjects(sessions[0].users.firstObject.userID, nasty);
}

- (void)test_writeAfterClose_returnsNO
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    [log close];
    XCTAssertFalse([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:nil]);
    XCTAssertFalse([log recordUserID:@"alice" atMs:2]);
}

- (void)test_emptyPathDoesNotCloseStandardInput
{
    BOOL installedTemporaryStdin = NO;
    if (fcntl(STDIN_FILENO, F_GETFD) == -1) {
        int fd = open("/dev/null", O_RDONLY);
        XCTAssertEqual(fd, STDIN_FILENO);
        installedTemporaryStdin = fd == STDIN_FILENO;
    }

    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:@""];

    XCTAssertNil(log);
    XCTAssertNotEqual(fcntl(STDIN_FILENO, F_GETFD), -1);
    if (installedTemporaryStdin) {
        close(STDIN_FILENO);
    }
}

- (void)test_openSessionEndAdvancesWithEachEvent
{
    // The currently-open session's ended_at_ms tracks the time of its most
    // recent event, so a consumer can compute a reasonable duration even
    // without seeing a subsequent SESSION_BEGIN.
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:nil]);
    XCTAssertTrue([log recordUserID:@"alice" atMs:5]);
    [log close];

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions[0].users.firstObject.atMs, 5);
    XCTAssertEqual(sessions[0].endedAtMs, 5);
}

- (void)test_allUserChangesArePreserved
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:nil]);

    for (NSUInteger i = 0; i < 400; i++) {
        NSString *userID = [NSString stringWithFormat:@"user-%lu", (unsigned long)i];
        XCTAssertTrue([log recordUserID:userID atMs:(int64_t)i + 2]);
    }

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions.firstObject.users.count, 400u);
    XCTAssertEqualObjects(sessions.firstObject.users.firstObject.userID, @"user-0");
    XCTAssertEqualObjects(sessions.firstObject.users.lastObject.userID, @"user-399");
}

- (void)test_allSessionsArePreserved
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    for (NSUInteger i = 0; i < 600; i++) {
        NSString *sessionID = [NSString stringWithFormat:@"session-%lu", (unsigned long)i];
        XCTAssertTrue([log recordSessionBeginWithID:sessionID perceptible:(i % 2) == 0 atMs:(int64_t)i userID:nil]);
    }

    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:self.path];
    XCTAssertEqual(sessions.count, 600u);
    XCTAssertEqualObjects(sessions.firstObject.sessionID, @"session-0");
    XCTAssertEqualObjects(sessions.lastObject.sessionID, @"session-599");
}

@end
