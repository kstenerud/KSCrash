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

#import "KSCrashRunContext.h"
#import "KSCrashRunSummary.h"
#import "KSKeyValueStore.h"

// Test helper exposed from KSCrashRunContext.m.
extern KSCrashRunSummary *ksruncontext_testcode_buildSummary(const KSCrashRunContext *ctx,
                                                             const char *userInfoSidecarPath);

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
    XCTAssertEqual(summary.schemaVersion, 1);
    XCTAssertTrue(summary.sdkVersion.length > 0);
    XCTAssertEqualObjects(summary.runID, @"a1b2c3d4-e5f6-7890-abcd-ef1234567890");
    XCTAssertEqualObjects(summary.deviceID, @"0123456789abcdef0123456789abcdef");
    XCTAssertNil(summary.userID);

    XCTAssertEqual(summary.startedAtMs, 1744000000000LL);
    XCTAssertEqual(summary.endedAtMs, 1744000180000LL);

    XCTAssertEqual(summary.outcome.terminationReason, KSTerminationReasonCrash);
    XCTAssertFalse(summary.outcome.cleanShutdown);
    XCTAssertTrue(summary.outcome.fatalReported);
    XCTAssertTrue(summary.outcome.userPerceptible);

    XCTAssertEqual(summary.durations.activeMs, 123456LL);
    XCTAssertEqual(summary.durations.backgroundMs, 45678LL);

    XCTAssertEqual(summary.sessions.perceptibleCount, 3);
    XCTAssertEqual(summary.sessions.imperceptibleCount, 2);

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
    return [entries sortedArrayUsingSelector:@selector(compare:)];
}

- (void)test_persistPreviousRunSummary_writesFile
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);
    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);

    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String, 50);

    // Filename is <startedAtMs>.run. populateContext gives startedAtMs = 1744000000000.
    NSString *expectedPath = [self.tempDir stringByAppendingPathComponent:@"Runs/1744000000000.run"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:expectedPath]);

    NSData *data = [NSData dataWithContentsOfFile:expectedPath];
    XCTAssertNotNil(data);
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    XCTAssertEqualObjects(json[@"run_id"], @"a1b2c3d4-e5f6-7890-abcd-ef1234567890");
    XCTAssertEqualObjects(json[@"os"][@"name"], @"iOS");
    XCTAssertEqualObjects(json[@"outcome"][@"termination_reason"], @"crash");

    ksruncontext_testcode_setCachedSummary(nil, NULL);
}

- (void)test_persistPreviousRunSummary_noOpWhenSummaryMissing
{
    ksruncontext_testcode_setCachedSummary(nil, NULL);

    // Shouldn't crash, shouldn't create the Runs/ directory.
    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String, 50);

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:self.runsDir]);
}

- (void)test_persistPreviousRunSummary_noOpWhenBacklogCapIsZero
{
    KSCrashRunContext ctx;
    populateContext(&ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);
    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);

    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String, 0);

    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:self.runsDir]);

    ksruncontext_testcode_setCachedSummary(nil, NULL);
}

#pragma mark - Backlog cap

- (void)test_persistPreviousRunSummary_dropsOldestWhenOverCap
{
    // Seed 5 fake summaries, lowest filename = oldest.
    [self seedSummariesCount:5];

    KSCrashRunContext ctx;
    populateContext(&ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);
    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);

    // Cap 3 → prune to 2, then write the new one → total 3.
    // The new file lands at <startedAtMs>.run which is numerically larger than
    // any seed, so it sorts as newest on subsequent prunes.
    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String, 3);

    NSArray<NSString *> *contents = [self runsDirContents];
    XCTAssertEqual(contents.count, 3u);
    XCTAssertTrue([contents containsObject:@"3.run"]);
    XCTAssertTrue([contents containsObject:@"4.run"]);
    XCTAssertTrue([contents containsObject:@"1744000000000.run"]);
    XCTAssertFalse([contents containsObject:@"0.run"]);
    XCTAssertFalse([contents containsObject:@"1.run"]);
    XCTAssertFalse([contents containsObject:@"2.run"]);

    ksruncontext_testcode_setCachedSummary(nil, NULL);
}

- (void)test_persistPreviousRunSummary_noPruneWhenUnderCap
{
    [self seedSummariesCount:2];

    KSCrashRunContext ctx;
    populateContext(&ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);
    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);

    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String, 5);

    NSArray<NSString *> *contents = [self runsDirContents];
    XCTAssertEqual(contents.count, 3u);  // 2 seeded + 1 new, all survive.

    ksruncontext_testcode_setCachedSummary(nil, NULL);
}

- (void)test_persistPreviousRunSummary_ignoresNonRunFiles
{
    // Seed one .run and a couple of files that don't match our naming. They
    // must not be counted toward the cap or deleted.
    [self seedSummariesCount:1];
    NSString *tmpPath = [self.runsDir stringByAppendingPathComponent:@"scratch.tmp"];
    [[NSData data] writeToFile:tmpPath atomically:YES];
    // A .run file whose prefix isn't numeric — doesn't match parseRunFilename
    // and must be ignored by the prune.
    NSString *oddPath = [self.runsDir stringByAppendingPathComponent:@"not-a-number.run"];
    [[NSData data] writeToFile:oddPath atomically:YES];

    KSCrashRunContext ctx;
    populateContext(&ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);
    ksruncontext_testcode_setCachedSummary(summary, ctx.runID);

    // Cap 1 → prune the single seed, keep the others, write the new summary.
    ksruncontext_persistPreviousRunSummary(self.runsDir.UTF8String, 1);

    NSArray<NSString *> *contents = [self runsDirContents];
    XCTAssertTrue([contents containsObject:@"scratch.tmp"]);
    XCTAssertTrue([contents containsObject:@"not-a-number.run"]);
    XCTAssertTrue([contents containsObject:@"1744000000000.run"]);
    XCTAssertFalse([contents containsObject:@"0.run"]);

    ksruncontext_testcode_setCachedSummary(nil, NULL);
}

@end
