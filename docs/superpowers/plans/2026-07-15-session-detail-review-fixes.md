# Session Detail Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make malformed session logs safe and make previous-run persistence bounded-memory without changing sidecar correlation, the append-only format, synchronous behavior, or the startup performance contract.

**Architecture:** A single specialized scanner validates the exact append grammar directly over mmap-backed bytes and produces a reusable inspection value containing the committed range and timestamp floor. `KSCrashRunSummary` caches that inspection and uses a private synchronous `writev` path to persist mapped bytes without constructing a full-log output buffer; public `jsonData` remains intact.

**Tech Stack:** Objective-C, Foundation mapped `NSData`, POSIX `writev`, XCTest, Swift Package Manager, clang-format-20.

---

## File Map

- Modify `Sources/KSCrashRecording/KSCrashSessionLog.h`: define the internal inspection value and inspected splice APIs.
- Modify `Sources/KSCrashRecording/KSCrashSessionLog.m`: implement the allocation-free grammar scanner, reuse it for timestamp discovery/splicing, and harden object field decoding.
- Create `Sources/KSCrashRecording/KSCrashRunSummary+Private.h`: declare the synchronous fd writer and focused writev test seam without changing the public RunSummary header.
- Modify `Sources/KSCrashRecording/KSCrashRunSummary.m`: cache session inspection, preserve lazy loading, and implement scatter-write persistence.
- Modify `Sources/KSCrashRecording/KSCrashRunContext.m`: call the private fd writer instead of materializing `jsonData` during startup.
- Modify `Tests/KSCrashRecordingTests/KSCrashSessionLog_Tests.m`: cover committed garbage, grammar corruption, partial recovery, and wrong-typed fields.
- Modify `Tests/KSCrashRecordingTests/KSCrashRunContext_Summary_Tests.m`: cover persisted JSON equivalence, laziness, corrupt fallback, and partial writev advancement.
- Modify `Tests/KSCrashRecordingTests/KSCrashMonitor_Lifecycle_Tests.m`: apply clang-format-20 to the existing formatting violation only.

### Task 1: Capture the Performance Baseline

**Files:**
- Read: `Tests/KSCrashBenchmarksObjC/KSCrashRunSummaryBenchmarks.m`

- [ ] **Step 1: Run the three existing startup benchmarks before editing production code**

Run:

```bash
swift test --filter 'KSCrashRunSummaryBenchmarks/(testBenchmarkPersistWithSmallSessionLog|testBenchmarkPersistWithLargeSessionLog|testBenchmarkBuildAndPersistWithLargeSessionLog)'
```

Expected: all three tests pass. Save each reported average and relative standard deviation in the implementation notes for comparison in Task 6.

- [ ] **Step 2: Confirm the worktree contains only the committed design plus the uncommitted plan**

Run:

```bash
git status --short
```

Expected: only `docs/superpowers/plans/2026-07-15-session-detail-review-fixes.md` is untracked; stop if unrelated files are modified.

### Task 2: Validate the Append Grammar and Reject Committed Garbage

**Files:**
- Modify: `Sources/KSCrashRecording/KSCrashSessionLog.h`
- Modify: `Sources/KSCrashRecording/KSCrashSessionLog.m`
- Test: `Tests/KSCrashRecordingTests/KSCrashSessionLog_Tests.m`

- [ ] **Step 1: Add failing raw-splice regression tests**

Add this helper and tests near `test_malformedFile_readsAsNoSessions`:

```objc
static NSDictionary *summaryFragmentForSessionData(NSData *data)
{
    NSMutableData *output = [[@"{\"sessions\":" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [KSCrashSessionLog appendSessionsJSONFromData:data runEndedAtMs:100 toOutput:output];
    [output appendBytes:"}" length:1];
    return [NSJSONSerialization JSONObjectWithData:output options:0 error:nil];
}

- (void)test_committedGarbage_rawSplicePersistsEmptySessions
{
    NSData *garbage = [@"[not-json\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *result = summaryFragmentForSessionData(garbage);
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"sessions"], @[]);
}

- (void)test_corruptionInsideWriterShapedLog_rawSplicePersistsEmptySessions
{
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:self.path];
    XCTAssertTrue([log recordSessionBeginWithID:@"sess-A" perceptible:YES atMs:1 userID:@"alice"]);
    XCTAssertTrue([log recordUserID:@"bob" atMs:2]);
    [log close];

    NSMutableData *corrupt = [[NSData dataWithContentsOfFile:self.path] mutableCopy];
    NSRange token = [corrupt rangeOfData:[@"\"at_ms\":2" dataUsingEncoding:NSUTF8StringEncoding]
                                options:0
                                  range:NSMakeRange(0, corrupt.length)];
    XCTAssertNotEqual(token.location, NSNotFound);
    ((uint8_t *)corrupt.mutableBytes)[token.location] = '!';

    NSDictionary *result = summaryFragmentForSessionData(corrupt);
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"sessions"], @[]);
}
```

- [ ] **Step 2: Run the tests and observe the malformed JSON failure**

Run:

```bash
swift test --filter 'KSCrashSessionLog_Tests/(test_committedGarbage_rawSplicePersistsEmptySessions|test_corruptionInsideWriterShapedLog_rawSplicePersistsEmptySessions)'
```

Expected: fail because `summaryFragmentForSessionData` returns `nil` for bytes currently copied verbatim.

- [ ] **Step 3: Define the reusable inspection value and inspected splice entry point**

Add before `@interface KSCrashSessionLog` in `KSCrashSessionLog.h`:

```objc
typedef struct {
    NSRange committedRange;
    int64_t maxObservedTimestampMs;
    bool isValid;
    bool hasSessions;
} KSCrashSessionLogInspection;
```

Add these internal class methods beside the existing splice method:

```objc
+ (KSCrashSessionLogInspection)inspectionForData:(NSData *)data;

+ (void)appendSessionsJSONFromData:(NSData *)data
                        inspection:(KSCrashSessionLogInspection)inspection
                      runEndedAtMs:(int64_t)runEndedAtMs
                          toOutput:(NSMutableData *)output;

+ (NSData *)closingDataForInspection:(KSCrashSessionLogInspection)inspection
                        runEndedAtMs:(int64_t)runEndedAtMs;
```

The existing `appendSessionsJSONFromData:runEndedAtMs:toOutput:` remains the compatibility wrapper that performs one inspection and delegates.

- [ ] **Step 4: Implement the exact append-grammar scanner**

Replace `committedPrefix`, `isEmptyCommittedPrefix`, and the separate backward timestamp searches with byte-cursor helpers in `KSCrashSessionLog.m`. The scanner must implement these exact transitions:

```objc
// File       := "[\n" (SessionLine | UserLine)*
// SessionLine:= ("],\"ended_at_ms\":" Int "},")?
//              "{\"session_id\":" String
//              ",\"perceptible\":" ("true" | "false")
//              ",\"started_at_ms\":" Int
//              ",\"users\":[" User? "\n"
// UserLine   := ","? "{\"user_id\":" String ",\"at_ms\":" Int "}\n"
```

Use this result shape and top-level loop:

```objc
+ (KSCrashSessionLogInspection)inspectionForData:(NSData *)data
{
    KSCrashSessionLogInspection result = { .committedRange = NSMakeRange(0, 0) };
    const uint8_t *bytes = data.bytes;
    NSUInteger committedLength = lastCommittedLength(bytes, data.length);
    if (committedLength < 2 || bytes[0] != '[' || bytes[1] != '\n') {
        return result;
    }

    result.committedRange = NSMakeRange(0, committedLength);
    if (committedLength == 2) {
        result.isValid = true;
        return result;
    }

    KSByteCursor cursor = { .bytes = bytes, .position = 2, .end = committedLength };
    BOOL hasOpenSession = NO;
    BOOL hasUser = NO;
    int64_t observed = 0;
    while (cursor.position < cursor.end) {
        if (cursorStartsSessionLine(&cursor, hasOpenSession)) {
            int64_t startedAtMs = 0;
            BOOL initialUser = NO;
            if (!consumeSessionLine(&cursor, hasOpenSession, &startedAtMs, &initialUser)) {
                return (KSCrashSessionLogInspection) { 0 };
            }
            hasOpenSession = YES;
            hasUser = initialUser;
            observed = MAX(observed, startedAtMs);
        } else {
            int64_t atMs = 0;
            if (!hasOpenSession || !consumeUserLine(&cursor, hasUser, &atMs)) {
                return (KSCrashSessionLogInspection) { 0 };
            }
            hasUser = YES;
            observed = MAX(observed, atMs);
        }
    }
    result.isValid = hasOpenSession;
    result.hasSessions = hasOpenSession;
    result.maxObservedTimestampMs = observed;
    return result;
}
```

Implement `lastCommittedLength` as a backwards newline search. Implement `consumeLiteral`, checked signed `consumeInteger`, and `consumeJSONString`; the string helper must accept legal JSON escapes, require four hex digits after `\\u`, reject unescaped control bytes, and validate complete UTF-8 scalar sequences for non-ASCII bytes. `consumeSessionLine` and `consumeUserLine` must require the fixed tokens and the terminating newline exactly, so extra committed bytes are invalid.

- [ ] **Step 5: Reuse inspection for splicing and timestamp flooring**

Implement the closing/splice methods as:

```objc
+ (NSData *)closingDataForInspection:(KSCrashSessionLogInspection)inspection
                        runEndedAtMs:(int64_t)runEndedAtMs
{
    if (!inspection.isValid || !inspection.hasSessions) {
        return [@"[]" dataUsingEncoding:NSUTF8StringEncoding];
    }
    int64_t finalizedEnd = MAX(runEndedAtMs, inspection.maxObservedTimestampMs);
    NSString *suffix = [NSString stringWithFormat:@"],\"ended_at_ms\":%lld}]", finalizedEnd];
    return [suffix dataUsingEncoding:NSUTF8StringEncoding];
}

+ (void)appendSessionsJSONFromData:(NSData *)data
                        inspection:(KSCrashSessionLogInspection)inspection
                      runEndedAtMs:(int64_t)runEndedAtMs
                          toOutput:(NSMutableData *)output
{
    if (inspection.isValid && inspection.hasSessions) {
        [output appendBytes:(const uint8_t *)data.bytes + inspection.committedRange.location
                     length:inspection.committedRange.length];
    }
    [output appendData:[self closingDataForInspection:inspection runEndedAtMs:runEndedAtMs]];
}
```

Make the existing splice method inspect then delegate. Make `maxObservedTimestampInData:` return the inspected timestamp only when valid.

- [ ] **Step 6: Run all SessionLog tests**

Run:

```bash
swift test --filter KSCrashSessionLog_Tests
```

Expected: all tests pass, including partial-write recovery and Unicode user IDs.

- [ ] **Step 7: Commit the grammar validation**

```bash
git add Sources/KSCrashRecording/KSCrashSessionLog.h Sources/KSCrashRecording/KSCrashSessionLog.m Tests/KSCrashRecordingTests/KSCrashSessionLog_Tests.m
git commit -m "Validate committed session log grammar"
```

### Task 3: Make Lazy Object Decoding Type-Safe

**Files:**
- Modify: `Sources/KSCrashRecording/KSCrashSessionLog.m`
- Test: `Tests/KSCrashRecordingTests/KSCrashSessionLog_Tests.m`

- [ ] **Step 1: Add failing tests for wrong-typed decoded fields**

Declare this test-only category beside the test case interface so the tests can drive the materialization boundary independently of the grammar scanner:

```objc
@interface KSCrashSessionLog (DecodedEntryTests)
+ (NSArray<KSCrashRunSummarySession *> *)testcode_sessionsFromDecodedArray:(NSArray *)decoded;
@end
```

Add tests that pass already-decoded JSON objects and assert no Objective-C exception escapes:

```objc
- (void)test_wrongTypedSessionScalar_returnsSafely
{
    __block NSArray *sessions = nil;
    NSArray *decoded = @[
        @{ @"session_id" : @"s", @"perceptible" : @[], @"started_at_ms" : @1,
           @"ended_at_ms" : @2, @"users" : @[] }
    ];
    XCTAssertNoThrow(sessions = [KSCrashSessionLog testcode_sessionsFromDecodedArray:decoded]);
    XCTAssertEqualObjects(sessions, @[]);
}

- (void)test_wrongTypedUserScalar_skipsOnlyInvalidUser
{
    __block NSArray *sessions = nil;
    NSArray *decoded = @[
        @{
            @"session_id" : @"s",
            @"perceptible" : @YES,
            @"started_at_ms" : @1,
            @"ended_at_ms" : @2,
            @"users" : @[
                @{ @"user_id" : @"bad", @"at_ms" : @[] },
                @{ @"user_id" : @"good", @"at_ms" : @2 },
            ],
        }
    ];
    XCTAssertNoThrow(sessions = [KSCrashSessionLog testcode_sessionsFromDecodedArray:decoded]);
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions[0].users.count, 1u);
    XCTAssertEqualObjects(sessions[0].users[0].userID, @"good");
}
```

- [ ] **Step 2: Run the tests and confirm the old implementation throws or the missing strict checks are exposed**

Run:

```bash
swift test --filter 'KSCrashSessionLog_Tests/(test_wrongTypedSessionScalar_returnsSafely|test_wrongTypedUserScalar_skipsOnlyInvalidUser)'
```

Expected before hardening: both fail because the test-only selector is not implemented. After extracting the existing materialization loop but before adding type guards, they fail by exception.

- [ ] **Step 3: Add strict JSON scalar helpers and guard every selector**

Add local helpers in `KSCrashSessionLog.m`:

```objc
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
    return type != NULL && type[0] != 'f' && type[0] != 'd';
}
```

In the session loop, fetch and check all values before calling selectors:

```objc
id perceptibleValue = dict[@"perceptible"];
id startedValue = dict[@"started_at_ms"];
id endedValue = dict[@"ended_at_ms"];
id usersValue = dict[@"users"];
if (![sessionID isKindOfClass:[NSString class]] || !isJSONBoolean(perceptibleValue) ||
    !isJSONInteger(startedValue) || !isJSONInteger(endedValue) ||
    ![usersValue isKindOfClass:[NSArray class]]) {
    continue;
}
```

For each user, require string `user_id` and integral `at_ms` before constructing the model. Extract the existing decoded-array loop into `+testcode_sessionsFromDecodedArray:` and make `sessionsFromData:` call that method after `NSJSONSerialization` succeeds.

- [ ] **Step 4: Run the full SessionLog suite**

Run:

```bash
swift test --filter KSCrashSessionLog_Tests
```

Expected: all tests pass with no exceptions.

- [ ] **Step 5: Commit the decoder hardening**

```bash
git add Sources/KSCrashRecording/KSCrashSessionLog.m Tests/KSCrashRecordingTests/KSCrashSessionLog_Tests.m
git commit -m "Reject wrong-typed session log fields"
```

### Task 4: Persist Lazy Sessions Synchronously Without a Full-Log Buffer

**Files:**
- Create: `Sources/KSCrashRecording/KSCrashRunSummary+Private.h`
- Modify: `Sources/KSCrashRecording/KSCrashRunSummary.m`
- Modify: `Sources/KSCrashRecording/KSCrashRunContext.m`
- Test: `Tests/KSCrashRecordingTests/KSCrashRunContext_Summary_Tests.m`

- [ ] **Step 1: Add failing persistence and laziness tests**

Extend the existing persistence section with a helper that reads the single `.run` output and these cases:

```objc
- (void)test_persistPreviousRunSummary_keepsSessionGraphLazy
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"Sessions"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:path];
    XCTAssertTrue([log recordSessionBeginWithID:@"session-A" perceptible:YES atMs:1744000000000 userID:@"alice"]);
    [log close];

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, path.UTF8String);
    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);
    XCTAssertNil([summary valueForKey:@"_sessions"]);

    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String);

    XCTAssertNil([summary valueForKey:@"_sessions"]);
    NSData *persisted = [NSData dataWithContentsOfFile:[self.runsDir stringByAppendingPathComponent:runFilenameForNs(
                                                                   ctx.lifecycle.wallClockAtStartNs)]];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:persisted options:0 error:nil];
    XCTAssertEqualObjects(json[@"sessions"][0][@"session_id"], @"session-A");
}

- (void)test_persistPreviousRunSummary_committedGarbageWritesEmptySessions
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"Sessions"];
    [@"[not-json\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, path.UTF8String);
    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);

    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String);

    NSString *output = [self.runsDir stringByAppendingPathComponent:runFilenameForNs(ctx.lifecycle.wallClockAtStartNs)];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:output]
                                                          options:0
                                                            error:nil];
    XCTAssertEqualObjects(json[@"sessions"], @[]);
}

- (void)test_persistPreviousRunSummary_lazyPathDoesNotCallJSONData
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"Sessions"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:path];
    XCTAssertTrue([log recordSessionBeginWithID:@"session-A" perceptible:YES atMs:1744000000000 userID:nil]);
    [log close];
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, path.UTF8String);
    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);

    Method method = class_getInstanceMethod(KSCrashRunSummary.class, @selector(jsonData));
    __block BOOL called = NO;
    IMP replacement = imp_implementationWithBlock(^NSData *(__unused KSCrashRunSummary *object) {
        called = YES;
        return nil;
    });
    IMP original = method_setImplementation(method, replacement);
    @try {
        ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String);
    } @finally {
        method_setImplementation(method, original);
        imp_removeBlock(replacement);
    }

    XCTAssertFalse(called);
    NSString *output = [self.runsDir stringByAppendingPathComponent:runFilenameForNs(ctx.lifecycle.wallClockAtStartNs)];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:output]
                                                          options:0
                                                            error:nil];
    XCTAssertEqualObjects(json[@"sessions"][0][@"session_id"], @"session-A");
}
```

Import `<objc/runtime.h>` for the scoped method interception. Restore the original implementation in `@finally` so later tests cannot observe the replacement.

- [ ] **Step 2: Run the focused persistence tests**

Run:

```bash
swift test --filter 'KSCrashRunContext_Summary_Tests/(test_persistPreviousRunSummary_keepsSessionGraphLazy|test_persistPreviousRunSummary_committedGarbageWritesEmptySessions|test_persistPreviousRunSummary_lazyPathDoesNotCallJSONData)'
```

Expected before the private writer: `test_persistPreviousRunSummary_lazyPathDoesNotCallJSONData` fails because `called` is true and no valid output file is produced. The other two protect output and lazy-object behavior.

- [ ] **Step 3: Declare the private writer and writev test seam**

Create `KSCrashRunSummary+Private.h`:

```objc
#import "KSCrashRunSummary.h"

#import <sys/uio.h>

NS_ASSUME_NONNULL_BEGIN

typedef ssize_t (^KSCrashRunSummaryWritevBlock)(int fd, const struct iovec *iov, int iovCount);

@interface KSCrashRunSummary (Private)
- (BOOL)writeJSONToFileDescriptor:(int)fd;
+ (BOOL)testcode_writeAllVectors:(struct iovec *)vectors
                           count:(int)count
                              fd:(int)fd
                          writer:(KSCrashRunSummaryWritevBlock)writer;
@end

NS_ASSUME_NONNULL_END
```

- [ ] **Step 4: Cache the inspection beside mapped data**

Add `KSCrashSessionLogInspection _sessionLogInspection;` to RunSummary's implementation ivars. Immediately after mapping the log, inspect once and use that cached timestamp:

```objc
_sessionLogInspection = [KSCrashSessionLog inspectionForData:_sessionLogData ?: [NSData data]];
if (_sessionLogInspection.isValid && _sessionLogInspection.maxObservedTimestampMs > _endedAtMs) {
    _endedAtMs = _sessionLogInspection.maxObservedTimestampMs;
}
```

When `.sessions` materializes and clears `_sessionLogData`, zero `_sessionLogInspection`. Update `jsonData` to snapshot both data and inspection under `_sessionsLock`, then call the inspected splice overload. This prevents a second startup scan and preserves public encoding behavior.

- [ ] **Step 5: Implement robust vector advancement and synchronous fd encoding**

Import the private header, `<errno.h>`, `<limits.h>`, and `<sys/uio.h>` in `KSCrashRunSummary.m`. Implement a static helper used by both production and the class test seam:

```objc
static BOOL writeAllVectors(int fd, struct iovec *vectors, int count, KSCrashRunSummaryWritevBlock writer)
{
    while (count > 0) {
        ssize_t written = writer(fd, vectors, count);
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written <= 0) {
            return NO;
        }
        size_t consumed = (size_t)written;
        while (count > 0 && consumed >= vectors[0].iov_len) {
            consumed -= vectors[0].iov_len;
            vectors++;
            count--;
        }
        if (count > 0 && consumed > 0) {
            vectors[0].iov_base = (uint8_t *)vectors[0].iov_base + consumed;
            vectors[0].iov_len -= consumed;
        }
    }
    return YES;
}
```

Before each real `writev`, construct a bounded stack view whose cumulative length does not exceed `SSIZE_MAX`; pass at most the five RunSummary vectors. Apply the returned byte count to the original vectors with the helper above. This handles an mmap larger than one platform write without allocating proportional memory.

Implement `-writeJSONToFileDescriptor:` by snapshotting lazy state under `_sessionsLock`. If sessions are materialized, encode with `jsonData` and write one vector. Otherwise encode `wireDictionaryWithoutSessions`, verify/remove its closing brace logically by setting the first vector length to `base.length - 1`, and assemble:

```objc
static const char sessionsKey[] = ",\"sessions\":";
static const char closingBrace[] = "}";
NSData *closing = [KSCrashSessionLog closingDataForInspection:inspection runEndedAtMs:self.endedAtMs];
struct iovec vectors[5];
int count = 0;
vectors[count++] = (struct iovec) { .iov_base = (void *)base.bytes, .iov_len = base.length - 1 };
vectors[count++] = (struct iovec) { .iov_base = (void *)sessionsKey, .iov_len = sizeof(sessionsKey) - 1 };
if (inspection.isValid && inspection.hasSessions) {
    vectors[count++] = (struct iovec) {
        .iov_base = (uint8_t *)sessionData.bytes + inspection.committedRange.location,
        .iov_len = inspection.committedRange.length,
    };
}
vectors[count++] = (struct iovec) { .iov_base = (void *)closing.bytes, .iov_len = closing.length };
vectors[count++] = (struct iovec) { .iov_base = (void *)closingBrace, .iov_len = 1 };
```

Call the bounded writev loop synchronously and return its result.

- [ ] **Step 6: Switch RunContext persistence to the private writer**

Import `KSCrashRunSummary+Private.h`. Remove the pre-open `[g_summary jsonData]` allocation. After opening the same destination path, use:

```objc
if (![g_summary writeJSONToFileDescriptor:fd]) {
    KSLOG_ERROR(@"Failed to write run summary to %s: errno=%d", path, errno);
}
close(fd);
```

Do not add `dispatch_async`, `dispatch_sync`, `fsync`, a cap, a temporary file, or a format conversion.

- [ ] **Step 7: Test interrupted and partial vector advancement**

Import the private header in `KSCrashRunContext_Summary_Tests.m` and add:

```objc
- (void)test_writeAllVectors_retriesEINTRAndAdvancesPartialWrites
{
    char first[] = "abc";
    char second[] = "defg";
    struct iovec vectors[] = {
        { .iov_base = first, .iov_len = 3 },
        { .iov_base = second, .iov_len = 4 },
    };
    __block NSInteger call = 0;
    __block NSMutableData *written = [NSMutableData data];
    BOOL ok = [KSCrashRunSummary testcode_writeAllVectors:vectors
                                                    count:2
                                                       fd:-1
                                                   writer:^ssize_t(int fd, const struct iovec *iov, int iovCount) {
                                                       (void)fd;
                                                       call++;
                                                       if (call == 1) {
                                                           errno = EINTR;
                                                           return -1;
                                                       }
                                                       size_t allowance = call == 2 ? 2 : SIZE_MAX;
                                                       size_t consumed = 0;
                                                       for (int i = 0; i < iovCount && consumed < allowance; i++) {
                                                           size_t length = MIN(iov[i].iov_len, allowance - consumed);
                                                           [written appendBytes:iov[i].iov_base length:length];
                                                           consumed += length;
                                                       }
                                                       return (ssize_t)consumed;
                                                   }];
    XCTAssertTrue(ok);
    XCTAssertEqualObjects([[NSString alloc] initWithData:written encoding:NSUTF8StringEncoding], @"abcdefg");
    XCTAssertGreaterThanOrEqual(call, 3);
}
```

- [ ] **Step 8: Run RunContext and RunSummary focused suites**

Run:

```bash
swift test --filter '(KSCrashRunContext_Summary_Tests|KSCrashRunSummary_Tests)'
```

Expected: all tests pass; persisted output decodes and `_sessions` remains nil.

- [ ] **Step 9: Commit synchronous scatter-write persistence**

```bash
git add Sources/KSCrashRecording/KSCrashRunSummary+Private.h Sources/KSCrashRecording/KSCrashRunSummary.m Sources/KSCrashRecording/KSCrashRunContext.m Tests/KSCrashRecordingTests/KSCrashRunContext_Summary_Tests.m
git commit -m "Stream lazy run summaries synchronously"
```

### Task 5: Apply the Repository Formatter

**Files:**
- Modify: `Tests/KSCrashRecordingTests/KSCrashMonitor_Lifecycle_Tests.m`

- [ ] **Step 1: Format only the failing file with the repository's required formatter**

Run:

```bash
clang-format-20 -style=file -i Tests/KSCrashRecordingTests/KSCrashMonitor_Lifecycle_Tests.m
```

Expected: only formatting changes, including the previously reported area around line 748.

- [ ] **Step 2: Verify clang formatting**

Run:

```bash
make check-format
```

Expected: `All clean!`.

- [ ] **Step 3: Commit the format correction**

```bash
git add Tests/KSCrashRecordingTests/KSCrashMonitor_Lifecycle_Tests.m
git commit -m "Format lifecycle session tests"
```

### Task 6: Verify Correctness and Startup Performance

**Files:**
- Verify: all files changed above

- [ ] **Step 1: Run the accepted-finding regression suites**

Run:

```bash
swift test --filter '(KSCrashSessionLog_Tests|KSCrashRunSummary_Tests|KSCrashRunContext_Summary_Tests|KSCrashMonitor_Lifecycle_Tests|KSCrashReportStore_RunSummary_Tests|RunSummaryCodableTests)'
```

Expected: all selected tests pass with zero failures.

- [ ] **Step 2: Run namespace and whitespace checks**

Run:

```bash
make namespace-check
git diff develop...HEAD --check
```

Expected: namespace tests and generated-header comparison pass; diff check has no output.

- [ ] **Step 3: Run the startup benchmarks again**

Run:

```bash
swift test --filter 'KSCrashRunSummaryBenchmarks/(testBenchmarkPersistWithSmallSessionLog|testBenchmarkPersistWithLargeSessionLog|testBenchmarkBuildAndPersistWithLargeSessionLog)'
```

Expected: all pass. Compare medians/averages with Task 1; repeat once if variance is high. Do not accept a repeatable regression in small-log, large-log, or full build-and-persist time. Large-log persistence should improve because it no longer copies the mmap into a proportional mutable buffer.

- [ ] **Step 4: Run final formatting and repository-state checks**

Run:

```bash
make check-format
git status --short
git log --oneline develop..HEAD
```

Expected: clang-format passes; the worktree is clean except for this implementation-plan document if it has not yet been committed; the log contains the design and focused implementation commits.

- [ ] **Step 5: Commit the implementation plan if it remains uncommitted**

```bash
git add docs/superpowers/plans/2026-07-15-session-detail-review-fixes.md
git commit -m "Add session detail fix implementation plan"
```

- [ ] **Step 6: Report verification without claiming the known unrelated Swift-format issue was introduced here**

Summarize the exact passing test counts, namespace result, clang-format result, benchmark comparison, and clean worktree. If `make check-swift-format` is run, identify the existing unchanged `Samples/Common/Sources/IntegrationTestsHelper/CrashTriggerConfig.swift` issue separately and do not modify it as part of this work.
