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

#import <string.h>

#import "KSCrashRunSummary.h"
#import "KSCrashSessionLog.h"

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

// A zero anchor makes epoch-ms = monotonicNs / 1e6, so ns written in whole-ms
// multiples read back as those ms values.
- (NSArray<KSCrashRunSummarySession *> *)sessionsWithRunEndedAtMs:(int64_t)runEndedAtMs
{
    return [KSCrashSessionLog sessionsAtPath:self.path
                          wallClockAtStartNs:0
                          monotonicAtStartNs:0
                                runEndedAtMs:runEndedAtMs];
}

- (void)test_sessions_builtFromLogInOrderWithUsers
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertNotNil(log);
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES monotonicNs:1000000]);  // 1 ms
    XCTAssertTrue([log recordUserID:@"alice" monotonicNs:2000000]);                               // 2 ms
    XCTAssertTrue([log recordUserID:@"bob" monotonicNs:3000000]);                                 // 3 ms
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-B" perceptible:NO monotonicNs:5000000]);   // 5 ms
    [log close];

    NSArray<KSCrashRunSummarySession *> *sessions = [self sessionsWithRunEndedAtMs:10];
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
    XCTAssertEqual(b.endedAtMs, 10);  // last open session ends at the run end
    XCTAssertEqual(b.users.count, 0u);
}

- (void)test_tornTail_ignoresUncommittedTrailingBytes
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES monotonicNs:1000000]);
    XCTAssertTrue([log recordUserID:@"alice" monotonicNs:2000000]);
    [log close];

    // Simulate a record that was mid-write when the process died: append raw
    // bytes past the committed region. The header's committedSize is unchanged,
    // so the reader must ignore them.
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:self.path];
    [handle seekToEndOfFile];
    uint8_t garbage[40];
    memset(garbage, 0xAB, sizeof(garbage));
    [handle writeData:[NSData dataWithBytes:garbage length:sizeof(garbage)]];
    [handle closeFile];

    NSArray<KSCrashRunSummarySession *> *sessions = [self sessionsWithRunEndedAtMs:10];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqualObjects(sessions[0].sessionID, @"sess-A");
    XCTAssertEqual(sessions[0].users.count, 1u);
    XCTAssertEqualObjects(sessions[0].users[0].userID, @"alice");
}

- (void)test_emptyLog_readsAsNoSessions
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertNotNil(log);
    [log close];
    XCTAssertEqual([self sessionsWithRunEndedAtMs:10].count, 0u);
}

- (void)test_open_truncatesExistingLog
{
    KSCrashSessionLog *first = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([first recordSessionBeginWithID:@"sess-A" perceptible:YES monotonicNs:1000000]);
    [first close];

    // Reopening the same path resets it to empty (one log per run).
    KSCrashSessionLog *second = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertNotNil(second);
    [second close];
    XCTAssertEqual([self sessionsWithRunEndedAtMs:10].count, 0u);
}

- (void)test_missingFile_readsAsNoSessions
{
    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:@"/nonexistent/path/Sessions"
                                                                   wallClockAtStartNs:0
                                                                   monotonicAtStartNs:0
                                                                         runEndedAtMs:10];
    XCTAssertEqual(sessions.count, 0u);
}

- (void)test_writeAfterClose_returnsNO
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    [log close];
    XCTAssertFalse([log recordSessionBeginWithID:@"sess-A" perceptible:YES monotonicNs:1000000]);
    XCTAssertFalse([log recordUserID:@"alice" monotonicNs:2000000]);
}

@end
