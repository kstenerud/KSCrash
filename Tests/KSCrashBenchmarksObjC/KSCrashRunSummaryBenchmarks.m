//
//  KSCrashRunSummaryBenchmarks.m
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
#import <fcntl.h>
#import <unistd.h>

#import "KSBenchmarkTestCase.h"
#import "KSCrashMonitor_Lifecycle.h"
#import "KSCrashMonitor_System.h"
#import "KSCrashRunContext.h"
#import "KSCrashRunSummary.h"
#import "KSCrashSessionLog.h"

// Driving ksruncontext_init directly would require kscrash_getLastRunID to
// return a fake ID and g_reportStoreConfig to be set — too much wiring. Instead
// we drive the two pieces it runs (contextForRunID + buildSummary) explicitly,
// which measures the same work. testcode_* helpers set the globals that
// persistPreviousRunSummary reads, standing in for what ksruncontext_init
// would have populated in production.
extern KSCrashRunSummary *ksruncontext_testcode_buildSummary(const KSCrashRunContext *ctx,
                                                             const char *userInfoSidecarPath);
extern KSCrashRunSummary *ksruncontext_testcode_buildSummaryWithSessions(const KSCrashRunContext *ctx,
                                                                         const char *userInfoSidecarPath,
                                                                         const char *sessionsSidecarPath);
extern void ksruncontext_testcode_setCachedSummary(KSCrashRunSummary *summary, const char *runID);
extern void ksruncontext_testcode_setLifecycleData(const KSCrash_LifecycleData *data);

// C-callback-visible pointer to the temp dir for the path resolver. XCTest
// runs methods in the same class sequentially, so a single global is safe.
static NSString *g_benchTempDir = nil;

static bool benchPathForRunID(const char *monitorId, __unused const char *runID, char *pathBuffer,
                              size_t pathBufferLength)
{
    if (g_benchTempDir == nil) {
        return false;
    }
    // Seeding only Lifecycle + System + UserInfo + Sessions keeps the
    // benchmark focused on the new branch's hot path. Resource is optional
    // for buildSummary, so return false for anything we haven't seeded —
    // matches the no-sidecar branch exercised in production on a first
    // launch after the Resource monitor being disabled.
    NSString *path = nil;
    if (strcmp(monitorId, "Lifecycle") == 0) {
        path = [g_benchTempDir stringByAppendingPathComponent:@"Lifecycle.ksscr"];
    } else if (strcmp(monitorId, "System") == 0) {
        path = [g_benchTempDir stringByAppendingPathComponent:@"System.ksscr"];
    } else if (strcmp(monitorId, "UserInfo") == 0) {
        path = [g_benchTempDir stringByAppendingPathComponent:@"UserInfo.kvs"];
    } else if (strcmp(monitorId, "Sessions") == 0) {
        path = [g_benchTempDir stringByAppendingPathComponent:@"Sessions.ksscr"];
    } else {
        return false;
    }
    const char *utf8 = path.UTF8String;
    size_t len = strlen(utf8);
    if (len + 1 > pathBufferLength) {
        return false;
    }
    memcpy(pathBuffer, utf8, len + 1);
    return true;
}

// Seed a Sessions.ksscr in the benchmark's temp dir with the specified
// scale. Uses the real KSCrashSessionLog writer so the on-disk shape
// matches production (append-only, newline commit delimiters, etc.) —
// which is the whole point of the raw-splice hot path we want to time.
static NSString *seedSessionLog(NSString *tempDir, NSUInteger sessionCount, NSUInteger userChangesPerSession)
{
    NSString *path = [tempDir stringByAppendingPathComponent:@"Sessions.ksscr"];
    KSCrashSessionLog *log = [[KSCrashSessionLog alloc] initForWritingAtPath:path];
    for (NSUInteger i = 0; i < sessionCount; i++) {
        NSString *sessionID = [NSString stringWithFormat:@"%08lu-e5f6-7890-abcd-ef1234567890", (unsigned long)i];
        int64_t sessionStartMs = 1744000000000ULL + ((int64_t)i * 60000);
        [log recordSessionBeginWithID:sessionID
                          perceptible:(i % 2) == 0
                                 atMs:sessionStartMs
                               userID:i == 0 ? @"initial-user" : nil];
        for (NSUInteger j = 0; j < userChangesPerSession; j++) {
            NSString *userID = [NSString stringWithFormat:@"user-%lu-%lu", (unsigned long)i, (unsigned long)j];
            [log recordUserID:userID atMs:sessionStartMs + ((int64_t)j * 1000) + 1];
        }
    }
    [log close];
    return path;
}

static void writeBytes(NSString *path, const void *bytes, size_t length)
{
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    NSCAssert(fd >= 0, @"Failed to open %@", path);
    ssize_t written = write(fd, bytes, length);
    NSCAssert(written == (ssize_t)length, @"Short write to %@", path);
    close(fd);
}

// Lifecycle sidecar seeded to mimic a foregrounded run that terminated
// without a lifecycle callback (e.g. OOM). Numbers are arbitrary but realistic
// — the benchmark is insensitive to the specific values.
static KSCrash_LifecycleData makeLifecycleData(void)
{
    KSCrash_LifecycleData lc = {};
    lc.magic = KSLIFECYCLE_MAGIC;
    lc.version = KSCrash_Lifecycle_CurrentVersion;
    lc.applicationIsActive = 1;
    lc.applicationIsInForeground = 1;
    lc.userPerceptible = 1;
    lc.transitionState = (uint8_t)KSCrashAppTransitionStateActive;
    lc.launchesSinceLastCrash = 5;
    lc.sessionsSinceLastCrash = 10;
    lc.sessionsSinceLaunch = 3;
    lc.perceptibleSessionsSinceLaunch = 3;
    lc.imperceptibleSessionsSinceLaunch = 0;
    lc.distinctPerceptibleUserCount = 1;
    lc.distinctImperceptibleUserCount = 0;
    lc.activeDurationSinceLaunchNs = 60000000000ULL;
    lc.backgroundDurationSinceLaunchNs = 30000000000ULL;
    lc.activeDurationSinceLastCrashNs = 120000000000ULL;
    lc.backgroundDurationSinceLastCrashNs = 45000000000ULL;
    lc.wallClockAtStartNs = 1744000000000000000ULL;
    lc.monotonicAtStartNs = 1000;
    lc.appStateTransitionTimeNs = 1000;
    lc.hostKind = 0;  // KSCrashRunSummaryHostKindApp
    return lc;
}

static KSCrash_SystemData makeSystemData(void)
{
    KSCrash_SystemData sd = {};
    sd.magic = KSSYS_MAGIC;
    sd.version = KSCrash_System_CurrentVersion;
    strlcpy(sd.systemName, "iOS", sizeof(sd.systemName));
    strlcpy(sd.systemVersion, "18.0", sizeof(sd.systemVersion));
    strlcpy(sd.osVersion, "22A348", sizeof(sd.osVersion));
    strlcpy(sd.machine, "iPhone17,1", sizeof(sd.machine));
    strlcpy(sd.model, "iPhone", sizeof(sd.model));
    strlcpy(sd.cpuArchitecture, "arm64e", sizeof(sd.cpuArchitecture));
    strlcpy(sd.binaryArchitecture, "arm64e", sizeof(sd.binaryArchitecture));
    strlcpy(sd.bundleID, "com.acme.app", sizeof(sd.bundleID));
    strlcpy(sd.bundleVersion, "2.6.0.1234", sizeof(sd.bundleVersion));
    strlcpy(sd.bundleShortVersion, "2.6.0", sizeof(sd.bundleShortVersion));
    strlcpy(sd.deviceAppHash, "0123456789abcdef0123456789abcdef", sizeof(sd.deviceAppHash));
    return sd;
}

@interface KSCrashRunSummaryBenchmarks : KSBenchmarkTestCaseObjC
@end

@implementation KSCrashRunSummaryBenchmarks {
    NSString *_tempDir;
    NSString *_runsDir;
}

- (void)setUp
{
    [super setUp];
    _tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    _runsDir = [_tempDir stringByAppendingPathComponent:@"Runs"];

    KSCrash_LifecycleData lc = makeLifecycleData();
    writeBytes([_tempDir stringByAppendingPathComponent:@"Lifecycle.ksscr"], &lc, sizeof(lc));

    KSCrash_SystemData sd = makeSystemData();
    writeBytes([_tempDir stringByAppendingPathComponent:@"System.ksscr"], &sd, sizeof(sd));

    g_benchTempDir = _tempDir;
}

- (void)tearDown
{
    ksruncontext_testcode_setCachedSummary(nil, NULL);
    ksruncontext_testcode_setLifecycleData(NULL);
    g_benchTempDir = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_tempDir error:nil];
    [super tearDown];
}

/// Sidecar reads + termination-reason derivation + ObjC model allocation.
/// This is the work ksruncontext_init does on install before persisting.
- (void)testBenchmarkBuildSummary
{
    const char *runID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    [self measureBlock:^{
        KSCrashRunContext ctx;
        ksruncontext_contextForRunID(runID, benchPathForRunID, &ctx);
        __unused KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);
    }];
}

/// KSJSONCodec encode + file write of a pre-built summary. This is the work
/// ksruncontext_persistPreviousRunSummary does on install after
/// ksruncontext_init has built the summary.
- (void)testBenchmarkPersistSummary
{
    const char *runID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    KSCrashRunContext ctx;
    ksruncontext_contextForRunID(runID, benchPathForRunID, &ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);
    ksruncontext_testcode_setCachedSummary(summary, runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);

    NSString *runsDir = _runsDir;
    [self measureBlock:^{
        ksruncontext_persistPreviousRunSummary(runsDir.UTF8String);
    }];
}

/// End-to-end: everything the branch adds to kscrash_install — sidecar reads,
/// ObjC allocation, JSON encode, file write. Track this number against future
/// changes that might pull heavier work into the install path.
- (void)testBenchmarkBuildAndPersistEndToEnd
{
    const char *runID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    NSString *runsDir = _runsDir;
    [self measureBlock:^{
        KSCrashRunContext ctx;
        ksruncontext_contextForRunID(runID, benchPathForRunID, &ctx);
        KSCrashRunSummary *summary = ksruncontext_testcode_buildSummary(&ctx, NULL);
        ksruncontext_testcode_setCachedSummary(summary, runID);
        ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);
        ksruncontext_persistPreviousRunSummary(runsDir.UTF8String);
    }];
}

// ============================================================================
// Session-log raw-splice benchmarks
//
// The append-only session log's on-disk shape exists so the raw-splice
// path in `-[KSCrashRunSummary jsonData]` can memcpy the previous run's
// bytes into the persisted summary without parsing. These benchmarks
// exercise that path with realistic small and large logs, and the sized
// suffixes let you spot regressions the moment they show up: a jump from
// microseconds to milliseconds on `large` indicates someone introduced a
// parse or object-materialization step on the hot path.
// ============================================================================

/// Small session log: a handful of sessions and user changes — what most
/// runs look like. Expected to stay in the tens-of-µs range.
- (void)testBenchmarkPersistWithSmallSessionLog
{
    NSString *sessionsPath = seedSessionLog(_tempDir, 3, 2);
    const char *runID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    KSCrashRunContext ctx;
    ksruncontext_contextForRunID(runID, benchPathForRunID, &ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, sessionsPath.UTF8String);
    ksruncontext_testcode_setCachedSummary(summary, runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);

    NSString *runsDir = _runsDir;
    [self measureBlock:^{
        ksruncontext_persistPreviousRunSummary(runsDir.UTF8String);
    }];
}

/// Large session log: 500 sessions × 8 user changes each — well past the
/// point where any accidental parse-per-record would dominate. The
/// raw-splice should keep this at memcpy scale.
- (void)testBenchmarkPersistWithLargeSessionLog
{
    NSString *sessionsPath = seedSessionLog(_tempDir, 500, 8);
    const char *runID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    KSCrashRunContext ctx;
    ksruncontext_contextForRunID(runID, benchPathForRunID, &ctx);
    KSCrashRunSummary *summary = ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, sessionsPath.UTF8String);
    ksruncontext_testcode_setCachedSummary(summary, runID);
    ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);

    NSString *runsDir = _runsDir;
    [self measureBlock:^{
        ksruncontext_persistPreviousRunSummary(runsDir.UTF8String);
    }];
}

/// Same large log, but measured through the full install path (build
/// summary + persist). Catches a regression that pulls parsing into the
/// constructor instead of leaving it lazy behind `.sessions`.
- (void)testBenchmarkBuildAndPersistWithLargeSessionLog
{
    NSString *sessionsPath = seedSessionLog(_tempDir, 500, 8);
    const char *runID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    NSString *runsDir = _runsDir;
    [self measureBlock:^{
        KSCrashRunContext ctx;
        ksruncontext_contextForRunID(runID, benchPathForRunID, &ctx);
        KSCrashRunSummary *summary =
            ksruncontext_testcode_buildSummaryWithSessions(&ctx, NULL, sessionsPath.UTF8String);
        ksruncontext_testcode_setCachedSummary(summary, runID);
        ksruncontext_testcode_setLifecycleData(&ctx.lifecycle);
        ksruncontext_persistPreviousRunSummary(runsDir.UTF8String);
    }];
}

@end
