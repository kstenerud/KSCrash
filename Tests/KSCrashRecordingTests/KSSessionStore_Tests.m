//
//  KSSessionStore_Tests.m
//
//  Created by Alexander Cohen on 2026-07-25.
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
#import <unistd.h>

#import "KSSessionStore.h"

@interface KSSessionStore_Tests : XCTestCase
@end

@implementation KSSessionStore_Tests {
    NSString *_dir;
    NSString *_runID;
    KSSessionWriter *_writer;
    KSSessionReader *_reader;
}

- (void)setUp
{
    [super setUp];
    _dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    _runID = [[NSUUID UUID] UUIDString];
}

- (void)tearDown
{
    if (_writer != NULL) {
        kssw_close(_writer);
        _writer = NULL;
    }
    if (_reader != NULL) {
        kssr_close(_reader);
        _reader = NULL;
    }
    [[NSFileManager defaultManager] removeItemAtPath:_dir error:nil];
    [super tearDown];
}

- (NSString *)sessionsPath
{
    return [_dir stringByAppendingPathComponent:[_runID stringByAppendingPathExtension:@"sessions"]];
}

- (void)makeWriter
{
    _writer = kssw_open(self.sessionsPath.fileSystemRepresentation);
    XCTAssertTrue(_writer != NULL);
}

/** Close the writer and open a reader over the same file. */
- (void)openReader
{
    if (_writer != NULL) {
        kssw_close(_writer);
        _writer = NULL;
    }
    _reader = kssr_open(self.sessionsPath.fileSystemRepresentation);
    XCTAssertTrue(_reader != NULL);
}

/** The writer's current-session id, or nil if none is open. */
- (NSString *)currentID
{
    const char *id = kssw_current(_writer);
    return id != NULL ? @(id) : nil;
}

- (KSSessionRecord)recordAt:(int)index
{
    KSSessionRecord rec;
    memset(&rec, 0, sizeof(rec));
    XCTAssertTrue(kssr_sessionAt(_reader, index, &rec), @"session %d should exist", index);
    return rec;
}

#pragma mark - Writer

- (void)testOpenWithoutPathReturnsNULL
{
    XCTAssertTrue(kssw_open(NULL) == NULL);
    XCTAssertTrue(kssw_open("") == NULL);
}

- (void)testCurrentEmptyBeforeAnySession
{
    [self makeWriter];
    XCTAssertNil([self currentID]);
    XCTAssertTrue(kssw_current(_writer) == NULL);
}

- (void)testUpdateOpensSession
{
    [self makeWriter];
    const char *cut = kssw_update(_writer, true, "user-1");
    XCTAssertTrue(cut != NULL, @"first update opens a session and returns its id");
    NSString *id1 = @(cut);
    XCTAssertEqual(id1.length, 36u, @"a lowercase UUID string");
    XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:id1]);
    XCTAssertEqualObjects(@(kssw_current(_writer)), id1, @"current returns the same id");

    // The recorded session's fields, via a reader.
    [self openReader];
    XCTAssertEqual(kssr_count(_reader), 1);
    KSSessionRecord r = [self recordAt:0];
    XCTAssertEqualObjects(@(r.guid), id1);
    XCTAssertEqualObjects(@(r.user), @"user-1");
    XCTAssertTrue(r.perceptible);
    XCTAssertTrue(r.endInferred, @"the open session's end is not yet known");
    XCTAssertEqual(r.endedAtMs, 0);
    int64_t nowMs = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
    XCTAssertEqualWithAccuracy((double)r.startedAtMs, (double)nowMs, 5000.0);
}

- (void)testSameStateIsNoOp
{
    [self makeWriter];
    XCTAssertTrue(kssw_update(_writer, true, "user-1") != NULL);
    NSString *id1 = [self currentID];
    XCTAssertTrue(kssw_update(_writer, true, "user-1") == NULL, @"unchanged (perceptible,user) is a no-op");
    XCTAssertEqualObjects(id1, [self currentID]);
}

- (void)testPerceptibilityChangeCutsNewSession
{
    [self makeWriter];
    kssw_update(_writer, true, "user-1");
    NSString *id1 = [self currentID];
    XCTAssertTrue(kssw_update(_writer, false, "user-1") != NULL);
    XCTAssertNotEqualObjects(id1, [self currentID]);
}

- (void)testUserChangeCutsNewSession
{
    [self makeWriter];
    kssw_update(_writer, true, "user-1");
    NSString *id1 = [self currentID];
    XCTAssertTrue(kssw_update(_writer, true, "user-2") != NULL);
    XCTAssertNotEqualObjects(id1, [self currentID]);
}

- (void)testNullObjectsAreSafe
{
    XCTAssertTrue(kssw_update(NULL, true, "user-1") == NULL);
    XCTAssertTrue(kssw_current(NULL) == NULL);
    kssw_close(NULL);  // must not crash

    XCTAssertEqual(kssr_count(NULL), 0);
    KSSessionRecord rec;
    XCTAssertFalse(kssr_sessionAt(NULL, 0, &rec));
    kssr_close(NULL);  // must not crash
}

- (void)testFailedWriteRollsBack
{
    // A path in a directory that does not exist makes the lazy open() fail.
    NSString *badPath = [_dir stringByAppendingPathComponent:@"missing-subdir/x.sessions"];
    _writer = kssw_open(badPath.fileSystemRepresentation);
    XCTAssertTrue(_writer != NULL, @"open is lazy, so creating the writer still succeeds");
    XCTAssertTrue(kssw_update(_writer, true, "user-1") == NULL, @"a failed write reports no session");
    XCTAssertNil([self currentID], @"the failed cut rolled back to no open session");
}

#pragma mark - Reader

- (void)testPairsSessionsAndInfersTheOpenOne
{
    [self makeWriter];
    kssw_update(_writer, true, "user-1");
    kssw_update(_writer, false, "user-1");
    kssw_update(_writer, true, "user-2");  // left open (never closed)
    [self openReader];

    XCTAssertEqual(kssr_count(_reader), 3);
    KSSessionRecord r0 = [self recordAt:0], r1 = [self recordAt:1], r2 = [self recordAt:2];

    XCTAssertTrue(r0.perceptible);
    XCTAssertEqualObjects(@(r0.user), @"user-1");
    XCTAssertFalse(r0.endInferred, @"closed by the second open");
    XCTAssertGreaterThanOrEqual(r0.endedAtMs, r0.startedAtMs);

    XCTAssertFalse(r1.perceptible);
    XCTAssertEqualObjects(@(r1.user), @"user-1");
    XCTAssertFalse(r1.endInferred, @"closed by the third open");

    XCTAssertTrue(r2.perceptible);
    XCTAssertEqualObjects(@(r2.user), @"user-2");
    XCTAssertTrue(r2.endInferred, @"the final session was never closed");
    XCTAssertEqual(r2.endedAtMs, 0, @"end left for the send path to fill");

    XCTAssertNotEqualObjects(@(r0.guid), @(r1.guid));
    XCTAssertNotEqualObjects(@(r1.guid), @(r2.guid));
    XCTAssertLessThanOrEqual(r0.startedAtMs, r1.startedAtMs);

    KSSessionRecord oob;
    XCTAssertFalse(kssr_sessionAt(_reader, 3, &oob), @"index past the end fails");
}

- (void)testAnonymousUserIsEmpty
{
    [self makeWriter];
    kssw_update(_writer, true, NULL);
    [self openReader];
    XCTAssertEqual(kssr_count(_reader), 1);
    KSSessionRecord r = [self recordAt:0];
    XCTAssertEqual(r.user[0], '\0', @"NULL userID stores as empty (anonymous)");
}

- (void)testTornTailStopsReadButKeepsPriorRecords
{
    [self makeWriter];
    kssw_update(_writer, true, "user-1");
    kssw_update(_writer, false, "user-1");  // a closed session, then leave one open
    kssw_close(_writer);
    _writer = NULL;

    // Append garbage after the valid records: a torn/short trailing write.
    int fd = open(self.sessionsPath.fileSystemRepresentation, O_WRONLY | O_APPEND);
    XCTAssertGreaterThanOrEqual(fd, 0);
    const char junk[73] = { (char)0xAB };
    write(fd, junk, sizeof(junk));
    close(fd);

    _reader = kssr_open(self.sessionsPath.fileSystemRepresentation);
    XCTAssertTrue(_reader != NULL);
    XCTAssertEqual(kssr_count(_reader), 2, @"both valid sessions survive the torn tail");
    XCTAssertEqualObjects(@([self recordAt:0].user), @"user-1");
}

- (void)testCountOfMissingFileIsZero
{
    _reader = kssr_open([_dir stringByAppendingPathComponent:@"nope.sessions"].fileSystemRepresentation);
    XCTAssertTrue(_reader != NULL);
    XCTAssertEqual(kssr_count(_reader), 0);
    KSSessionRecord rec;
    XCTAssertFalse(kssr_sessionAt(_reader, 0, &rec));
}

/** Write one real session, then append a raw entry with the given corruption. */
- (void)writeOneSessionThenRaw:(uint64_t)startMonoNs guid:(const char *)guid userNoNul:(BOOL)userNoNul
{
    [self makeWriter];
    kssw_update(_writer, true, "user-1");
    kssw_close(_writer);
    _writer = NULL;
    kssession_testcode_appendRawEntry(self.sessionsPath.fileSystemRepresentation, startMonoNs, true, guid, "user-2",
                                      userNoNul);
    _reader = kssr_open(self.sessionsPath.fileSystemRepresentation);
    XCTAssertTrue(_reader != NULL);
}

- (void)testUnterminatedUserIsReadBounded
{
    // A full-sized, otherwise-valid entry whose user has no NUL must not over-read.
    [self writeOneSessionThenRaw:2000000000000000000ULL guid:"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" userNoNul:YES];
    XCTAssertEqual(kssr_count(_reader), 2);
    KSSessionRecord r = [self recordAt:1];
    XCTAssertEqual((int)strlen(r.user), (int)(sizeof(r.user) - 1), @"user copied bounded to 127 chars, no over-read");
}

- (void)testEntryBeforeReferenceStopsRead
{
    // A start before the file's monotonic reference is corrupt; stop there.
    [self writeOneSessionThenRaw:1ULL guid:"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" userNoNul:NO];
    XCTAssertEqual(kssr_count(_reader), 1);
}

- (void)testEmptyGuidStopsRead
{
    [self writeOneSessionThenRaw:2000000000000000000ULL guid:"" userNoNul:NO];
    XCTAssertEqual(kssr_count(_reader), 1);
}

- (void)testOverflowingStartStopsRead
{
    // A monotonic start whose wall-clock conversion overflows is corrupt: stop
    // there instead of emitting an epoch-zero / negative-duration session.
    [self writeOneSessionThenRaw:0xFFFFFFFFFFFFFFFFULL guid:"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" userNoNul:NO];
    XCTAssertEqual(kssr_count(_reader), 1);
}

- (void)testUserIDTruncatedOnUTF8Boundary
{
    [self makeWriter];
    // 126 ASCII bytes then a 4-byte emoji: a raw 127-byte cut would split it.
    NSString *longUser = [[@"" stringByPaddingToLength:126 withString:@"a"
                                       startingAtIndex:0] stringByAppendingString:@"\U0001F600"];
    XCTAssertEqual((int)strlen(longUser.UTF8String), 130);
    kssw_update(_writer, true, longUser.UTF8String);
    [self openReader];
    XCTAssertEqual(kssr_count(_reader), 1);

    KSSessionRecord r = [self recordAt:0];
    XCTAssertEqual((int)strlen(r.user), 126, @"the split emoji is dropped whole");
    XCTAssertNotNil([NSString stringWithUTF8String:r.user], @"stored user is valid UTF-8");
    XCTAssertEqualObjects([NSString stringWithUTF8String:r.user], [longUser substringToIndex:126]);
}

@end
