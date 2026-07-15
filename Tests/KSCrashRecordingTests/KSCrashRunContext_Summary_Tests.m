//
//  KSCrashRunContext_Summary_Tests.m
//
//  Created by Alexander Cohen on 2026-04-20.
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
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <sys/uio.h>

#import "KSCrashRunContext.h"
#import "KSCrashRunSummary+Private.h"
#import "KSCrashSessionLog.h"
#import "KSKeyValueStore.h"

// Test helpers exposed from KSCrashRunContext.m.
extern KSCrashRunSummary *ksruncontext_testcode_buildSummary(const KSCrashRunContext *ctx,
                                                             const char *userInfoSidecarPath);
extern KSCrashRunSummary *ksruncontext_testcode_buildSummaryWithSessions(const KSCrashRunContext *ctx,
                                                                         const char *userInfoSidecarPath,
                                                                         const char *sessionsSidecarPath);

// Wall-clock ns → zero-padded "<digits>.run" filename, matching the format
// written by persistPreviousRunSummary.
static NSString *runFilenameForNs(long long ns) { return [NSString stringWithFormat:@"%019lld.run", ns]; }

// Fills a context with a realistic set of values so mapping tests can assert
// on each field individually.
static void populateContext(KSCrashRunContext *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
    strlcpy(ctx->runID, "a1b2c3d4-e5f6-7890-abcd-ef1234567890", sizeof(ctx->runID));
    ctx->terminationReason = KSTerminationReasonCrash;
    ctx->producedReport = true;

    ctx->lifecycleValid = true;
    ctx->lifecycle.cleanShutdown = 0;
    ctx->lifecycle.fatalReported = 1;
    ctx->lifecycle.userPerceptible = 1;
    ctx->lifecycle.activeDurationSinceLaunchNs = 123456789000ULL;     // 123456.789 ms
    ctx->lifecycle.backgroundDurationSinceLaunchNs = 45678901000ULL;  // 45678.901 ms
    ctx->lifecycle.wallClockAtStartNs = 1744000000000000000ULL;       // arbitrary epoch ns
    ctx->lifecycle.monotonicAtStartNs = 1000ULL;
    ctx->lifecycle.perceptibleSessionsSinceLaunch = 3;
    ctx->lifecycle.imperceptibleSessionsSinceLaunch = 2;
    ctx->lifecycle.distinctPerceptibleUserCount = 4;
    ctx->lifecycle.distinctImperceptibleUserCount = 1;

    // mostRecent - monotonicAtStart = 180000000000 ns = 180000 ms.
    // ended = started + 180000 ms = 1744000000000 + 180000 = 1744000180000 ms
    ctx->mostRecentTimestampNs = ctx->lifecycle.monotonicAtStartNs + 180000000000ULL;
    // Model a terminated-at-transition state (fatal crash or clean exit path):
    // updateSidecarDurations advanced the transition time to the end, so no
    // open tail slice remains and the stored durations above are final.
    // Tests that want to exercise the abnormal-termination path (tail slice
    // added by buildSummary) override appStateTransitionTimeNs explicitly.
    ctx->lifecycle.appStateTransitionTimeNs = ctx->mostRecentTimestampNs;

    ctx->systemValid = true;
    strlcpy(ctx->system.systemName, "iOS", sizeof(ctx->system.systemName));
    strlcpy(ctx->system.systemVersion, "18.0", sizeof(ctx->system.systemVersion));
    strlcpy(ctx->system.osVersion, "22A348", sizeof(ctx->system.osVersion));
    strlcpy(ctx->system.machine, "iPhone17,1", sizeof(ctx->system.machine));
    strlcpy(ctx->system.model, "iPhone", sizeof(ctx->system.model));
    strlcpy(ctx->system.cpuArchitecture, "arm64e", sizeof(ctx->system.cpuArchitecture));
    strlcpy(ctx->system.binaryArchitecture, "arm64e", sizeof(ctx->system.binaryArchitecture));
    strlcpy(ctx->system.bundleID, "com.acme.app", sizeof(ctx->system.bundleID));
    strlcpy(ctx->system.bundleVersion, "2.6.0.1234", sizeof(ctx->system.bundleVersion));
    strlcpy(ctx->system.bundleShortVersion, "2.6.0", sizeof(ctx->system.bundleShortVersion));
    strlcpy(ctx->system.deviceAppHash, "0123456789abcdef0123456789abcdef", sizeof(ctx->system.deviceAppHash));
    ctx->system.procTranslated = 0;
    ctx->system.isJailbroken = 0;
    ctx->system.isBeingDebugged = 0;
}

@interface KSCrashRunContext_Summary_Tests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation KSCrashRunContext_Summary_Tests

- (void)setUp
{
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

#pragma mark - Mapping

- (void)test_buildSummary_populatesEveryField
{
    KSCrashRunContext ctx;
    populateContext(&ctx);

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);

    XCTAssertNotNil(summary);
    XCTAssertEqual(summary.schemaVersion, 2);
    XCTAssertTrue(summary.sdkVersion.length > 0);
    XCTAssertEqualObjects(summary.runID, @"a1b2c3d4-e5f6-7890-abcd-ef1234567890");
    XCTAssertEqualObjects(summary.deviceID, @"0123456789abcdef0123456789abcdef");
    XCTAssertNil(summary.userID);

    XCTAssertEqual(summary.startedAtMs, 1744000000000LL);
    XCTAssertEqual(summary.endedAtMs, 1744000180000LL);
    XCTAssertFalse(summary.isBeingDebugged);

    XCTAssertEqual(summary.outcome.terminationReason, KSTerminationReasonCrash);
    XCTAssertFalse(summary.outcome.cleanShutdown);
    XCTAssertTrue(summary.outcome.fatalReported);
    XCTAssertTrue(summary.outcome.userPerceptible);

    XCTAssertEqual(summary.durations.activeMs, 123456LL);
    XCTAssertEqual(summary.durations.backgroundMs, 45678LL);

    XCTAssertEqual(summary.sessionCounts.perceptibleCount, 3);
    XCTAssertEqual(summary.sessionCounts.imperceptibleCount, 2);

    XCTAssertEqual(summary.users.perceptibleCount, 4);
    XCTAssertEqual(summary.users.imperceptibleCount, 1);

    XCTAssertEqualObjects(summary.app.bundleID, @"com.acme.app");
    XCTAssertEqualObjects(summary.app.version, @"2.6.0.1234");
    XCTAssertEqualObjects(summary.app.shortVersion, @"2.6.0");
    // hostKind comes from the lifecycle sidecar's stored byte. populateContext
    // left it at 0, which maps to KSCrashRunSummaryHostKindApp (the default
    // v2-sidecar-loaded-into-v3 behavior).
    XCTAssertEqual(summary.app.hostKind, KSCrashRunSummaryHostKindApp);

    XCTAssertEqualObjects(summary.os.name, @"iOS");
    XCTAssertEqualObjects(summary.os.version, @"18.0");
    XCTAssertEqualObjects(summary.os.build, @"22A348");

    XCTAssertEqualObjects(summary.device.model, @"iPhone17,1");
    XCTAssertEqualObjects(summary.device.modelFamily, @"iPhone");
    XCTAssertEqualObjects(summary.device.architecture, @"arm64e");
    XCTAssertEqualObjects(summary.device.binaryArchitecture, @"arm64e");
    XCTAssertFalse(summary.device.isTranslated);
    XCTAssertFalse(summary.device.isJailbroken);
}

// Verifies that hostKind comes from the *previous* run's stored sidecar
// byte, not from the current bundle. This is the guarantee that matters
// when an app and an extension share one KSCrash install dir — the summary
// for the previous run gets the producer's host kind, not the current
// process's.
- (void)test_buildSummary_hostKindComesFromSidecar
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    ctx.lifecycle.hostKind = (uint8_t)KSCrashRunSummaryHostKindExtension;

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);

    XCTAssertEqual(summary.app.hostKind, KSCrashRunSummaryHostKindExtension);
}

// Like hostKind, the flag comes from the *previous* run's stored sidecar
// byte, not from the current process's debugger state.
- (void)test_buildSummary_isBeingDebuggedComesFromSidecar
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    ctx.system.isBeingDebugged = 1;

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);

    XCTAssertTrue(summary.isBeingDebugged);
}

- (void)test_buildSummary_extendsActiveWithOpenTailSlice
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    // Abnormal termination (e.g. OOM, thermal kill): the previous run died
    // foregrounded and active, without a lifecycle callback closing the slice.
    // appStateTransitionTimeNs sits back at start, so (mostRecent - transition)
    // is the tail to fold into activeDurationSinceLaunchNs.
    ctx.lifecycle.appStateTransitionTimeNs = ctx.lifecycle.monotonicAtStartNs;
    ctx.lifecycle.applicationIsActive = 1;
    ctx.lifecycle.applicationIsInForeground = 1;

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);

    // Stored activeDurationSinceLaunchNs (123456 ms) plus the 180000 ms tail.
    XCTAssertEqual(summary.durations.activeMs, 123456LL + 180000LL);
    XCTAssertEqual(summary.durations.backgroundMs, 45678LL);
}

- (void)test_buildSummary_extendsBackgroundWithOpenTailSlice
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    // Same shape as the active case, but the run was backgrounded at death.
    // Startup / foregrounding states set applicationIsInForeground false but
    // are not "background" for duration accounting — only the
    // !isActive && !isInForeground branch accumulates background time.
    ctx.lifecycle.appStateTransitionTimeNs = ctx.lifecycle.monotonicAtStartNs;
    ctx.lifecycle.applicationIsActive = 0;
    ctx.lifecycle.applicationIsInForeground = 0;

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);

    XCTAssertEqual(summary.durations.activeMs, 123456LL);
    XCTAssertEqual(summary.durations.backgroundMs, 45678LL + 180000LL);
}

- (void)test_buildSummary_ignoresTailWhenTransitionAlreadyCurrent
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    // Fatal crash / clean exit path: updateSidecarDurations advances
    // appStateTransitionTimeNs to now, so the stored durations already cover
    // the slice up to termination and no tail should be added.
    ctx.lifecycle.appStateTransitionTimeNs = ctx.mostRecentTimestampNs;
    ctx.lifecycle.applicationIsActive = 1;

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);

    XCTAssertEqual(summary.durations.activeMs, 123456LL);
    XCTAssertEqual(summary.durations.backgroundMs, 45678LL);
}

- (void)test_buildSummary_usesStartWhenMostRecentIsBeforeStart
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    // Defensively, if mostRecent < monotonicAtStart (corrupt sidecar), the
    // ended timestamp falls back to started.
    ctx.mostRecentTimestampNs = 0;
    ctx.lifecycle.monotonicAtStartNs = 1000000;

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);

    XCTAssertNotNil(summary);
    XCTAssertEqual(summary.endedAtMs, summary.startedAtMs);
}

#pragma mark - Invalid Context

- (void)test_buildSummary_returnsNilForNullContext
{
    XCTAssertNil(ksruncontext_testcode_buildSummary(NULL, NULL));
}

- (void)test_buildSummary_returnsNilWhenLifecycleInvalid
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    ctx.lifecycleValid = false;

    XCTAssertNil(ksruncontext_testcode_buildSummary(&ctx, NULL));
}

- (void)test_buildSummary_returnsNilWhenSystemInvalid
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    ctx.systemValid = false;

    XCTAssertNil(ksruncontext_testcode_buildSummary(&ctx, NULL));
}

#pragma mark - UserInfo Reader

- (NSString *)sidecarPath
{
    return [self.tempDir stringByAppendingPathComponent:@"UserInfo.ksscr"];
}

- (void)test_buildSummary_userIDFromSidecar_livesLastWriteWins
{
    NSString *path = [self sidecarPath];
    KSKVSConfig cfg = {
        .initialCapacity = 4096,
        .maxKeyLength = 256,
        .maxStringLength = 1024,
    };
    KSKeyValueStore *store = kskvs_create(path.UTF8String, KSKVSModeReadWriteCreate, &cfg);
    XCTAssertTrue(store != NULL);
    kskvs_setString(store, "com.kscrash.userid", "alice");
    kskvs_setString(store, "other.key", "ignored");
    kskvs_setString(store, "com.kscrash.userid", "bob");
    kskvs_destroy(store);

    KSCrashRunContext ctx;
    populateContext(&ctx);

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, path.UTF8String);

    XCTAssertNotNil(summary);
    XCTAssertEqualObjects(summary.userID, @"bob");
}

- (void)test_buildSummary_userIDFromSidecar_tombstoneClears
{
    NSString *path = [self sidecarPath];
    KSKVSConfig cfg = {
        .initialCapacity = 4096,
        .maxKeyLength = 256,
        .maxStringLength = 1024,
    };
    KSKeyValueStore *store = kskvs_create(path.UTF8String, KSKVSModeReadWriteCreate, &cfg);
    XCTAssertTrue(store != NULL);
    kskvs_setString(store, "com.kscrash.userid", "alice");
    kskvs_removeValue(store, "com.kscrash.userid");
    kskvs_destroy(store);

    KSCrashRunContext ctx;
    populateContext(&ctx);

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, path.UTF8String);

    XCTAssertNotNil(summary);
    XCTAssertNil(summary.userID);
}

- (void)test_buildSummary_userIDFromSidecar_missingFileYieldsNilUserID
{
    KSCrashRunContext ctx;
    populateContext(&ctx);

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, "/nonexistent/path/to/userinfo.ksscr");

    XCTAssertNotNil(summary);
    XCTAssertNil(summary.userID);
}

#pragma mark - Persistence

extern void ksruncontext_testcode_setCachedSummary(KSCrashRunSummary *summary, const char *runID);
extern void ksruncontext_testcode_setLifecycleData(const KSCrash_LifecycleData *data);

- (NSString *)runsDir
{
    return [self.tempDir stringByAppendingPathComponent:@"Runs"];
}

// Seed `count` fake summary files named "<i>.run" so that the numeric prefix
// encodes age (lower = older). pruneOldSummaries sorts by this prefix, so the
// ordering is deterministic without touching file mtimes.
- (void)seedSummariesCount:(NSInteger)count
{
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:self.runsDir withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSInteger i = 0; i < count; i++) {
        NSString *name = [NSString stringWithFormat:@"%ld.run", (long)i];
        NSString *path = [self.runsDir stringByAppendingPathComponent:name];
        [[NSData data] writeToFile:path atomically:YES];
    }
}

- (NSArray<NSString *> *)runsDirContents
{
    NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.runsDir error:nil];
    return [entries sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b];
    }];
}

- (void)test_persistPreviousRunSummary_writesFile
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);
    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);
    // The filename is derived from g_context.lifecycle.wallClockAtStartNs, so
    // seed lifecycle too. In production ksruncontext_init populates both in
    // lockstep; tests drive them separately via these helpers.
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);

    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String);

    // Filename is <wallClockAtStartNs>.run, zero-padded. populateContext sets
    // wallClockAtStartNs = 1744000000000000000.
    NSString *expectedPath = [self.runsDir stringByAppendingPathComponent:runFilenameForNs(1744000000000000000LL)];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:expectedPath]);

    NSData *data = [NSData dataWithContentsOfFile:expectedPath];
    XCTAssertNotNil(data);
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    XCTAssertEqualObjects(json[@"run_id"], @"a1b2c3d4-e5f6-7890-abcd-ef1234567890");
    XCTAssertEqualObjects(json[@"os"][@"name"], @"iOS");
    XCTAssertEqualObjects(json[@"outcome"][@"termination_reason"], @"crash");

    ksruncontext_testcode_setCachedSummary(nil, NULL);
    ksruncontext_testcode_setLifecycleData(NULL);
}

- (void)test_persistPreviousRunSummary_lazyValidSessionsStayLazy
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    int64_t startedAtMs = (int64_t)(ctx.lifecycle.wallClockAtStartNs / 1000000ULL);
    NSString *sessionsPath = [self.tempDir stringByAppendingPathComponent:@"Sessions-valid"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:sessionsPath];
    XCTAssertTrue([log recordSessionBeginWithID:@"session-A" perceptible:YES atMs:startedAtMs userID:@"alice"]);
    XCTAssertTrue([log recordUserID:@"bob" atMs:startedAtMs + 500]);
    [log close];

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, sessionsPath.UTF8String);
    XCTAssertNil([summary valueForKey:@"_sessions"]);
    NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:summary.jsonData options:0 error:nil];
    XCTAssertNotNil(expected);
    XCTAssertNil([summary valueForKey:@"_sessions"]);

    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);
    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String);

    NSString *outputPath =
        [self.runsDir stringByAppendingPathComponent:runFilenameForNs((long long)ctx.lifecycle.wallClockAtStartNs)];
    NSData *output = [NSData dataWithContentsOfFile:outputPath];
    NSDictionary *actual = [NSJSONSerialization JSONObjectWithData:output options:0 error:nil];
    XCTAssertEqualObjects(actual, expected);
    XCTAssertNil([summary valueForKey:@"_sessions"]);

    ksruncontext_testcode_setCachedSummary(nil, NULL);
    ksruncontext_testcode_setLifecycleData(NULL);
}

- (void)test_persistPreviousRunSummary_committedGarbageWritesEmptySessions
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    NSString *sessionsPath = [self.tempDir stringByAppendingPathComponent:@"Sessions-garbage"];
    [@"[committed garbage\n" writeToFile:sessionsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, sessionsPath.UTF8String);
    NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:summary.jsonData options:0 error:nil];
    XCTAssertEqualObjects(expected[@"sessions"], @[]);
    XCTAssertNil([summary valueForKey:@"_sessions"]);

    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);
    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String);

    NSString *outputPath =
        [self.runsDir stringByAppendingPathComponent:runFilenameForNs((long long)ctx.lifecycle.wallClockAtStartNs)];
    NSData *output = [NSData dataWithContentsOfFile:outputPath];
    NSDictionary *actual = [NSJSONSerialization JSONObjectWithData:output options:0 error:nil];
    XCTAssertEqualObjects(actual, expected);
    XCTAssertEqualObjects(actual[@"sessions"], @[]);
    XCTAssertNil([summary valueForKey:@"_sessions"]);

    ksruncontext_testcode_setCachedSummary(nil, NULL);
    ksruncontext_testcode_setLifecycleData(NULL);
}

- (void)test_persistPreviousRunSummary_emptyLazyLogMatchesPublicJSON
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    NSString *sessionsPath = [self.tempDir stringByAppendingPathComponent:@"Sessions-empty"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:sessionsPath];
    XCTAssertNotNil(log);
    [log close];

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, sessionsPath.UTF8String);
    NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:summary.jsonData options:0 error:nil];
    XCTAssertEqualObjects(expected[@"sessions"], @[]);
    XCTAssertNil([summary valueForKey:@"_sessions"]);

    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);
    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String);

    NSString *outputPath =
        [self.runsDir stringByAppendingPathComponent:runFilenameForNs((long long)ctx.lifecycle.wallClockAtStartNs)];
    NSData *output = [NSData dataWithContentsOfFile:outputPath];
    NSDictionary *actual = [NSJSONSerialization JSONObjectWithData:output options:0 error:nil];
    XCTAssertEqualObjects(actual, expected);
    XCTAssertNil([summary valueForKey:@"_sessions"]);

    ksruncontext_testcode_setCachedSummary(nil, NULL);
    ksruncontext_testcode_setLifecycleData(NULL);
}

- (void)test_persistPreviousRunSummary_lazySummaryDoesNotCallJSONData
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    int64_t startedAtMs = (int64_t)(ctx.lifecycle.wallClockAtStartNs / 1000000ULL);
    NSString *sessionsPath = [self.tempDir stringByAppendingPathComponent:@"Sessions-no-json-data"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:sessionsPath];
    XCTAssertTrue([log recordSessionBeginWithID:@"session-A" perceptible:YES atMs:startedAtMs userID:nil]);
    [log close];
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, sessionsPath.UTF8String);
    XCTAssertNil([summary valueForKey:@"_sessions"]);

    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);

    Method method = class_getInstanceMethod(KSCrashRunSummary.class, @selector(jsonData));
    IMP original = method_getImplementation(method);
    __block NSUInteger callCount = 0;
    IMP replacement = imp_implementationWithBlock(^NSData *(KSCrashRunSummary *object) {
        (void)object;
        callCount++;
        return nil;
    });
    @try {
        method_setImplementation(method, replacement);
        ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String);
        NSString *outputPath =
            [self.runsDir stringByAppendingPathComponent:runFilenameForNs((long long)ctx.lifecycle.wallClockAtStartNs)];
        NSData *output = [NSData dataWithContentsOfFile:outputPath];
        XCTAssertEqual(callCount, 0u);
        XCTAssertNotNil(output);
        id outputObject = output != nil ? [NSJSONSerialization JSONObjectWithData:output options:0 error:nil] : nil;
        XCTAssertNotNil(outputObject);
        XCTAssertNil([summary valueForKey:@"_sessions"]);
    } @finally {
        method_setImplementation(method, original);
        imp_removeBlock(replacement);
        ksruncontext_testcode_setCachedSummary(nil, NULL);
        ksruncontext_testcode_setLifecycleData(NULL);
    }
}

- (void)test_writeAllVectors_retriesInterruptedAndAdvancesPartialWrite
{
    const char first[] = "abc";
    const char second[] = "defgh";
    const char third[] = "ij";
    struct iovec vectors[] = {
        { .iov_base = (void *)first, .iov_len = sizeof(first) - 1 },
        { .iov_base = (void *)second, .iov_len = sizeof(second) - 1 },
        { .iov_base = (void *)third, .iov_len = sizeof(third) - 1 },
    };
    __block NSUInteger calls = 0;
    __block NSMutableData *written = [NSMutableData data];
    KSCrashRunSummaryWritevBlock writevBlock = ^ssize_t(int fileDescriptor, const struct iovec *current, int count) {
        XCTAssertEqual(fileDescriptor, 42);
        calls++;
        if (calls == 1) {
            errno = EINTR;
            return -1;
        }

        size_t permitted = calls == 2 ? 5 : SIZE_MAX;
        size_t emitted = 0;
        for (int i = 0; i < count && emitted < permitted; i++) {
            size_t length = MIN(current[i].iov_len, permitted - emitted);
            [written appendBytes:current[i].iov_base length:length];
            emitted += length;
        }
        if (calls == 2) {
            XCTAssertEqual(emitted, 5u);
        } else {
            XCTAssertEqual(count, 2);
            XCTAssertEqual(current[0].iov_len, 3u);
            XCTAssertEqual(memcmp(current[0].iov_base, "fgh", 3), 0);
            XCTAssertEqual(current[1].iov_len, 2u);
            XCTAssertEqual(memcmp(current[1].iov_base, "ij", 2), 0);
        }
        return (ssize_t)emitted;
    };

    XCTAssertTrue([KSCrashRunSummary testcode_writeAllVectors:vectors
                                                        count:(int)(sizeof(vectors) / sizeof(vectors[0]))
                                               fileDescriptor:42
                                                  writevBlock:writevBlock]);
    XCTAssertEqual(calls, 3u);
    XCTAssertEqualObjects([[NSString alloc] initWithData:written encoding:NSUTF8StringEncoding], @"abcdefghij");
}

- (void)test_writeAllVectors_skipsZeroLengthVectors
{
    const char first[] = "ab";
    const char second[] = "cd";
    struct iovec vectors[] = {
        { .iov_base = (void *)first, .iov_len = sizeof(first) - 1 },
        { .iov_base = NULL, .iov_len = 0 },
        { .iov_base = (void *)second, .iov_len = sizeof(second) - 1 },
    };
    __block NSUInteger calls = 0;
    KSCrashRunSummaryWritevBlock writevBlock = ^ssize_t(int fileDescriptor, const struct iovec *current, int count) {
        XCTAssertEqual(fileDescriptor, 42);
        calls++;
        XCTAssertEqual(count, 2);
        XCTAssertEqual(current[0].iov_len, 2u);
        XCTAssertEqual(current[1].iov_len, 2u);
        return 4;
    };

    XCTAssertTrue([KSCrashRunSummary testcode_writeAllVectors:vectors
                                                        count:(int)(sizeof(vectors) / sizeof(vectors[0]))
                                               fileDescriptor:42
                                                  writevBlock:writevBlock]);
    XCTAssertEqual(calls, 1u);
}

- (void)test_writeAllVectors_rejectsZeroProgress
{
    const char bytes[] = "ab";
    struct iovec vector = { .iov_base = (void *)bytes, .iov_len = sizeof(bytes) - 1 };

    errno = 0;
    XCTAssertFalse([KSCrashRunSummary
        testcode_writeAllVectors:&vector
                           count:1
                  fileDescriptor:42
                     writevBlock:^ssize_t(__unused int fd, __unused const struct iovec *iov, __unused int count) {
                         return 0;
                     }]);
    XCTAssertEqual(errno, EIO);
}

- (void)test_writeAllVectors_rejectsResultLargerThanOffered
{
    const char bytes[] = "ab";
    struct iovec vector = { .iov_base = (void *)bytes, .iov_len = sizeof(bytes) - 1 };

    errno = 0;
    XCTAssertFalse([KSCrashRunSummary
        testcode_writeAllVectors:&vector
                           count:1
                  fileDescriptor:42
                     writevBlock:^ssize_t(__unused int fd, __unused const struct iovec *iov, __unused int count) {
                         return 3;
                     }]);
    XCTAssertEqual(errno, EIO);
}

- (void)test_writeAllVectors_preservesNonInterruptedError
{
    const char bytes[] = "ab";
    struct iovec vector = { .iov_base = (void *)bytes, .iov_len = sizeof(bytes) - 1 };
    __block NSUInteger calls = 0;

    errno = 0;
    XCTAssertFalse([KSCrashRunSummary
        testcode_writeAllVectors:&vector
                           count:1
                  fileDescriptor:42
                     writevBlock:^ssize_t(__unused int fd, __unused const struct iovec *iov, __unused int count) {
                         calls++;
                         errno = ENOSPC;
                         return -1;
                     }]);
    XCTAssertEqual(calls, 1u);
    XCTAssertEqual(errno, ENOSPC);
}

- (void)test_writeAllVectors_batchesMoreVectorsThanItsStackView
{
    const char byte = 'x';
    struct iovec vectors[20];
    for (NSUInteger i = 0; i < sizeof(vectors) / sizeof(vectors[0]); i++) {
        vectors[i] = (struct iovec) { .iov_base = (void *)&byte, .iov_len = 1 };
    }
    __block NSUInteger calls = 0;
    __block NSUInteger offered = 0;
    KSCrashRunSummaryWritevBlock writevBlock =
        ^ssize_t(__unused int fileDescriptor, __unused const struct iovec *current, int count) {
            XCTAssertLessThanOrEqual(count, 16);
            calls++;
            offered += (NSUInteger)count;
            return count;
        };

    XCTAssertTrue([KSCrashRunSummary testcode_writeAllVectors:vectors
                                                        count:(int)(sizeof(vectors) / sizeof(vectors[0]))
                                               fileDescriptor:42
                                                  writevBlock:writevBlock]);
    XCTAssertEqual(calls, 2u);
    XCTAssertEqual(offered, 20u);
}

- (void)test_writeAllVectors_capsOfferedBytesAtSSIZEMax
{
    const char byte = 'x';
    struct iovec vector = { .iov_base = (void *)&byte, .iov_len = SIZE_MAX };

    errno = 0;
    XCTAssertFalse([KSCrashRunSummary
        testcode_writeAllVectors:&vector
                           count:1
                  fileDescriptor:42
                     writevBlock:^ssize_t(__unused int fd, const struct iovec *iov, int count) {
                         XCTAssertEqual(count, 1);
                         XCTAssertEqual(iov[0].iov_len, (size_t)SSIZE_MAX);
                         errno = EFBIG;
                         return -1;
                     }]);
    XCTAssertEqual(errno, EFBIG);
}

- (void)test_persistPreviousRunSummary_noOpWhenSummaryMissing
{
    ksruncontext_testcode_setCachedSummary(nil, NULL);

    // Shouldn't crash, shouldn't create the Runs/ directory.
    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String);

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:self.runsDir]);
}

#pragma mark - Prune

- (void)test_pruneRunSummaries_dropsOldestWhenOverKeep
{
    // Seed 5 fake summaries, lowest filename = oldest.
    [self seedSummariesCount:5];

    ksruncontext_pruneRunSummaries(self.runsDir.UTF8String, 3);

    NSArray<NSString *> *contents = [self runsDirContents];
    XCTAssertEqual(contents.count, 3u);
    XCTAssertTrue([contents containsObject:@"2.run"]);
    XCTAssertTrue([contents containsObject:@"3.run"]);
    XCTAssertTrue([contents containsObject:@"4.run"]);
    XCTAssertFalse([contents containsObject:@"0.run"]);
    XCTAssertFalse([contents containsObject:@"1.run"]);
}

- (void)test_pruneRunSummaries_noOpWhenUnderKeep
{
    [self seedSummariesCount:2];

    ksruncontext_pruneRunSummaries(self.runsDir.UTF8String, 5);

    NSArray<NSString *> *contents = [self runsDirContents];
    XCTAssertEqual(contents.count, 2u);
}

- (void)test_pruneRunSummaries_ignoresNonRunFiles
{
    [self seedSummariesCount:3];
    NSString *tmpPath = [self.runsDir stringByAppendingPathComponent:@"scratch.tmp"];
    [[NSData data] writeToFile:tmpPath atomically:YES];
    // A .run file whose prefix isn't numeric — doesn't match parseRunFilename
    // and must be ignored by the prune.
    NSString *oddPath = [self.runsDir stringByAppendingPathComponent:@"not-a-number.run"];
    [[NSData data] writeToFile:oddPath atomically:YES];

    ksruncontext_pruneRunSummaries(self.runsDir.UTF8String, 1);

    NSArray<NSString *> *contents = [self runsDirContents];
    XCTAssertTrue([contents containsObject:@"scratch.tmp"]);
    XCTAssertTrue([contents containsObject:@"not-a-number.run"]);
    XCTAssertTrue([contents containsObject:@"2.run"]);
    XCTAssertFalse([contents containsObject:@"0.run"]);
    XCTAssertFalse([contents containsObject:@"1.run"]);
}

- (void)test_pruneRunSummaries_keepZeroOrNegativeIsNoOp
{
    // A disabled retention cap (keepCount <= 0) must never delete the backlog.
    [self seedSummariesCount:3];

    ksruncontext_pruneRunSummaries(self.runsDir.UTF8String, 0);
    XCTAssertEqual([self runsDirContents].count, 3u);

    ksruncontext_pruneRunSummaries(self.runsDir.UTF8String, -1);
    XCTAssertEqual([self runsDirContents].count, 3u);
}

- (void)test_pruneRunSummaries_noOpWhenPathInvalid
{
    ksruncontext_pruneRunSummaries(NULL, 5);
    ksruncontext_pruneRunSummaries("", 5);
    // No crash = pass.
}

#pragma mark - Session List

- (void)test_buildSummary_assemblesSessionListFromLog
{
    // Two sessions; the first crosses a user change (alice → bob).
    KSCrashRunContext ctx;
    populateContext(&ctx);

    // Writers hand at_ms values directly to the log — the caller has the anchor
    // (lifecycle sidecar's wall / monotonic pair) and does the conversion.
    int64_t startedAtMs = (int64_t)(ctx.lifecycle.wallClockAtStartNs / 1000000ULL);
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"Sessions"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:path];
    XCTAssertNotNil(log);
    XCTAssertTrue([log recordSessionBeginWithID:@"session-A" perceptible:YES atMs:startedAtMs userID:nil]);
    XCTAssertTrue([log recordUserID:@"alice" atMs:startedAtMs + 500]);
    XCTAssertTrue([log recordUserID:@"bob" atMs:startedAtMs + 10000]);
    XCTAssertTrue([log recordSessionBeginWithID:@"session-B" perceptible:NO atMs:startedAtMs + 100000 userID:@"bob"]);
    [log close];

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, path.UTF8String);

    XCTAssertNotNil(summary);
    XCTAssertEqual(summary.sessions.count, 2u);

    KSCrashRunSummarySession *a = summary.sessions[0];
    XCTAssertEqualObjects(a.sessionID, @"session-A");
    XCTAssertTrue(a.perceptible);
    XCTAssertEqual(a.startedAtMs, startedAtMs);
    XCTAssertEqual(a.endedAtMs, startedAtMs + 100000);  // closed at session-B's start
    XCTAssertEqual(a.users.count, 2u);
    XCTAssertEqualObjects(a.users[0].userID, @"alice");
    XCTAssertEqual(a.users[0].atMs, startedAtMs + 500);
    XCTAssertEqualObjects(a.users[1].userID, @"bob");

    KSCrashRunSummarySession *b = summary.sessions[1];
    XCTAssertEqualObjects(b.sessionID, @"session-B");
    XCTAssertFalse(b.perceptible);
    XCTAssertEqual(b.startedAtMs, startedAtMs + 100000);
    XCTAssertEqual(b.endedAtMs, summary.endedAtMs);  // final session closes at the run's best-known end
    XCTAssertEqual(b.users.count, 1u);
    XCTAssertEqualObjects(b.users[0].userID, @"bob");

    // The session list survives a RunSummary JSON round-trip.
    NSData *json = [summary jsonData];
    XCTAssertNotNil(json);
    KSCrashRunSummary *decoded = [KSCrashRunSummary summaryFromJSONData:json error:nil];
    XCTAssertNotNil(decoded);
    XCTAssertEqual(decoded.sessions.count, 2u);
    XCTAssertEqualObjects(decoded.sessions[0].sessionID, @"session-A");
    XCTAssertEqual(decoded.sessions[0].users.count, 2u);
    XCTAssertEqualObjects(decoded.sessions[0].users[1].userID, @"bob");
    XCTAssertEqualObjects(decoded.sessions[1].sessionID, @"session-B");
    XCTAssertEqual(decoded.sessions[1].endedAtMs, decoded.endedAtMs);
}

- (void)test_buildSummary_emptySessionListWhenNoLog
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, "/nonexistent/Sessions");
    XCTAssertNotNil(summary);
    XCTAssertEqualObjects(summary.sessions, @[]);
}

- (void)test_buildSummary_faultsSessionListOnlyOnFirstAccess
{
    // The install-path build should not touch the session log — the accessor
    // faults it in on first read. Confirm by observing that _sessions is nil
    // until the accessor runs.
    KSCrashRunContext ctx;
    populateContext(&ctx);
    int64_t startedAtMs = (int64_t)(ctx.lifecycle.wallClockAtStartNs / 1000000ULL);

    NSString *path = [self.tempDir stringByAppendingPathComponent:@"Sessions"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:path];
    XCTAssertTrue([log recordSessionBeginWithID:@"session-A" perceptible:YES atMs:startedAtMs userID:nil]);
    [log close];

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, path.UTF8String);
    XCTAssertNotNil(summary);
    XCTAssertNil([summary valueForKey:@"_sessions"]);  // not faulted yet
    NSData *json = summary.jsonData;
    XCTAssertNotNil(json);
    XCTAssertNil([summary valueForKey:@"_sessions"]);  // raw splice does not materialize the session graph
    KSCrashRunSummary *decoded = [KSCrashRunSummary summaryFromJSONData:json error:nil];
    XCTAssertEqual(decoded.sessions.firstObject.endedAtMs, decoded.endedAtMs);
    XCTAssertEqual(summary.sessions.count, 1u);
    XCTAssertNotNil([summary valueForKey:@"_sessions"]);
}

- (void)test_buildSummary_jsonDataDoesNotWaitForConcurrentSessionMaterialization
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    int64_t startedAtMs = (int64_t)(ctx.lifecycle.wallClockAtStartNs / 1000000ULL);
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"Sessions-concurrent"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:path];
    XCTAssertTrue([log recordSessionBeginWithID:@"session-A" perceptible:YES atMs:startedAtMs userID:@"alice"]);
    [log close];

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, path.UTF8String);
    XCTAssertNil([summary valueForKey:@"_sessions"]);

    SEL selector = @selector(sessionsFromData:);
    Method method = class_getClassMethod(KSCrashSessionLog.class, selector);
    IMP original = method_getImplementation(method);
    NSArray *(*originalFunction)(id, SEL, NSData *) = (NSArray * (*)(id, SEL, NSData *)) original;
    dispatch_semaphore_t materializationEntered = dispatch_semaphore_create(0);
    dispatch_semaphore_t allowMaterialization = dispatch_semaphore_create(0);
    dispatch_semaphore_t materializationFinished = dispatch_semaphore_create(0);
    dispatch_semaphore_t jsonFinished = dispatch_semaphore_create(0);
    __block NSArray<KSCrashRunSummarySession *> *materializedSessions = nil;
    __block NSData *json = nil;
    IMP replacement = imp_implementationWithBlock(^NSArray *(id receiver, NSData *data) {
        dispatch_semaphore_signal(materializationEntered);
        dispatch_semaphore_wait(allowMaterialization, DISPATCH_TIME_FOREVER);
        return originalFunction(receiver, selector, data);
    });

    __block long jsonWaitResult = -1;
    @try {
        method_setImplementation(method, replacement);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            materializedSessions = summary.sessions;
            dispatch_semaphore_signal(materializationFinished);
        });
        XCTAssertEqual(dispatch_semaphore_wait(materializationEntered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)),
                       0);

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            json = summary.jsonData;
            dispatch_semaphore_signal(jsonFinished);
        });
        jsonWaitResult = dispatch_semaphore_wait(jsonFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    } @finally {
        dispatch_semaphore_signal(allowMaterialization);
        XCTAssertEqual(dispatch_semaphore_wait(materializationFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)),
                       0);
        if (jsonWaitResult != 0) {
            XCTAssertEqual(dispatch_semaphore_wait(jsonFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
        }
        method_setImplementation(method, original);
        imp_removeBlock(replacement);
    }

    XCTAssertEqual(jsonWaitResult, 0);
    XCTAssertNotNil(json);
    XCTAssertEqual(materializedSessions.count, 1u);
    XCTAssertEqualObjects(materializedSessions.firstObject.sessionID, @"session-A");
}

- (void)test_buildSummary_keepsLazySessionsAfterSidecarIsRemoved
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    int64_t startedAtMs = (int64_t)(ctx.lifecycle.wallClockAtStartNs / 1000000ULL);

    NSString *path = [self.tempDir stringByAppendingPathComponent:@"Sessions"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:path];
    XCTAssertTrue([log recordSessionBeginWithID:@"session-A" perceptible:YES atMs:startedAtMs userID:@"alice"]);
    [log close];

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, path.UTF8String);
    XCTAssertNil([summary valueForKey:@"_sessions"]);
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:path error:nil]);

    XCTAssertEqual(summary.sessions.count, 1u);
    XCTAssertEqualObjects(summary.sessions.firstObject.sessionID, @"session-A");
    XCTAssertEqual(summary.sessions.firstObject.endedAtMs, summary.endedAtMs);
}

- (void)test_buildSummary_malformedSessionSidecarPersistsEmptySessions
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    NSString *path = [self.tempDir stringByAppendingPathComponent:@"Sessions"];
    [@"[not valid JSON]" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, path.UTF8String);
    NSData *json = summary.jsonData;
    XCTAssertNotNil(json);
    KSCrashRunSummary *decoded = [KSCrashRunSummary summaryFromJSONData:json error:nil];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(decoded.sessions, @[]);
}

@end
