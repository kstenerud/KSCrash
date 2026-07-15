//
//  KSCrashMonitor_Lifecycle_Tests.m
//
//  Created by Karl Stenerud on 2012-02-05.
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

#import "KSCrashAppTransitionState.h"
#import "KSCrashHang.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Lifecycle.h"
#import "KSCrashMonitor_Termination.h"
#import "KSCrashRunContext.h"
#import "KSCrashRunSummary.h"
#import "KSCrashSessionLog.h"

#include <mach/task_policy.h>
#include <objc/runtime.h>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfloat-equal"

// Test helpers declared extern (defined in production code with __attribute__((unused)))
extern void kscm_testcode_resetState(void);
extern void kscrash_testcode_setLastRunID(const char *runID);
extern void kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionState state);
extern void kscm_lifecycle_testcode_hangChange(KSHangChangeType change);
extern void kscm_lifecycle_testcode_setTaskRole(int32_t role);
extern void ksruncontext_testcode_setReason(KSTerminationReason reason);
extern void ksruncontext_testcode_setLifecycleData(const KSCrash_LifecycleData *data);

// Global test directory for path callbacks
static char g_testDir[1024];

typedef BOOL (*SessionBeginIMP)(id, SEL, NSString *, BOOL, int64_t, NSString *);
static SessionBeginIMP g_originalSessionBegin = NULL;
static dispatch_semaphore_t g_sessionBeginEntered;
static dispatch_semaphore_t g_sessionBeginRelease;

typedef void (*ForgetLastUserIDIMP)(id, SEL);
static ForgetLastUserIDIMP g_originalForgetLastUserID = NULL;
static dispatch_semaphore_t g_forgetLastUserIDEntered;
static dispatch_semaphore_t g_forgetLastUserIDRelease;

static BOOL blockingSessionBegin(id self, SEL command, NSString *sessionID, BOOL perceptible, int64_t atMs,
                                 NSString *userID)
{
    if (g_sessionBeginEntered != nil) {
        dispatch_semaphore_signal(g_sessionBeginEntered);
        dispatch_semaphore_wait(g_sessionBeginRelease, DISPATCH_TIME_FOREVER);
    }
    return g_originalSessionBegin(self, command, sessionID, perceptible, atMs, userID);
}

static void blockingForgetLastUserID(id self, SEL command)
{
    if (g_forgetLastUserIDEntered != nil) {
        dispatch_semaphore_signal(g_forgetLastUserIDEntered);
        dispatch_semaphore_wait(g_forgetLastUserIDRelease, DISPATCH_TIME_FOREVER);
    }
    g_originalForgetLastUserID(self, command);
}

static bool testGetRunSidecarPath(const char *monitorId, char *pathBuffer, size_t pathBufferLength)
{
    char dir[1024];
    snprintf(dir, sizeof(dir), "%s/current", g_testDir);
    mkdir(dir, 0755);
    return snprintf(pathBuffer, pathBufferLength, "%s/%s.ksscr", dir, monitorId) < (int)pathBufferLength;
}

static bool testGetRunSidecarPathForRunID(const char *monitorId, const char *runID, char *pathBuffer,
                                          size_t pathBufferLength)
{
    return snprintf(pathBuffer, pathBufferLength, "%s/%s/%s.ksscr", g_testDir, runID, monitorId) <
           (int)pathBufferLength;
}

/** Write a KSCrash_LifecycleData struct to a file at the given path. */
static bool writeSidecar(const char *path, const KSCrash_LifecycleData *data)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd == -1) return false;
    ssize_t written = write(fd, data, sizeof(*data));
    close(fd);
    return written == (ssize_t)sizeof(*data);
}

static bool readCurrentSidecar(KSCrash_LifecycleData *outData)
{
    if (outData == NULL) {
        return false;
    }
    char sidecarPath[1024];
    snprintf(sidecarPath, sizeof(sidecarPath), "%s/current/Lifecycle.ksscr", g_testDir);
    int fd = open(sidecarPath, O_RDONLY);
    if (fd < 0) {
        return false;
    }
    ssize_t bytesRead = read(fd, outData, sizeof(*outData));
    close(fd);
    return bytesRead == (ssize_t)sizeof(*outData);
}

@interface KSCrashMonitor_Lifecycle_Tests : XCTestCase
@property(nonatomic, copy) NSString *tempPath;
@end

@implementation KSCrashMonitor_Lifecycle_Tests

- (void)setUp
{
    [super setUp];
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.tempPath = tempDir;
    strncpy(g_testDir, [tempDir UTF8String], sizeof(g_testDir) - 1);
    g_testDir[sizeof(g_testDir) - 1] = '\0';

    // Reset the monitor infrastructure and provide test callbacks
    kscm_testcode_resetState();
    kscm_setRunSidecarPathProvider(testGetRunSidecarPath);
    kscm_setRunSidecarPathForRunIDProvider(testGetRunSidecarPathForRunID);

    // No previous run by default
    kscrash_testcode_setLastRunID(NULL);
    ksruncontext_testcode_setReason(KSTerminationReasonNone);
    ksruncontext_testcode_setLifecycleData(NULL);
}

- (void)tearDown
{
    KSCrashMonitorAPI *api = kscm_lifecycle_getAPI();
    if (api->isEnabled(api->context)) {
        api->setEnabled(false, api->context);
    }
    kscrash_testcode_setLastRunID(NULL);
    [[NSFileManager defaultManager] removeItemAtPath:self.tempPath error:nil];
    [super tearDown];
}

/** Initialize the Lifecycle monitor via the monitor API. */
- (void)enableMonitor
{
    KSCrashMonitorAPI *api = kscm_lifecycle_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { 0 };
    callbacks.getRunSidecarPath = testGetRunSidecarPath;
    callbacks.getRunSidecarPathForRunID = testGetRunSidecarPathForRunID;
    api->init(&callbacks, api->context);
    api->setEnabled(true, api->context);
    // Counter carry-forward is deferred to notifyPostSystemEnable (runs after
    // all monitors are enabled). In tests we call it explicitly.
    api->notifyPostSystemEnable(api->context);
}

- (void)disableMonitor
{
    KSCrashMonitorAPI *api = kscm_lifecycle_getAPI();
    api->setEnabled(false, api->context);
}

/** Write a previous sidecar with the given settings, set last run ID, then re-enable. */
- (void)simulateRelaunchWithPreviousSidecar:(KSCrash_LifecycleData)prev
{
    NSString *prevRunID = @"00000000-0000-0000-0000-000000000001";
    NSString *prevDir = [NSString stringWithFormat:@"%@/%@", self.tempPath, prevRunID];
    [[NSFileManager defaultManager] createDirectoryAtPath:prevDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    char prevPath[1024];
    snprintf(prevPath, sizeof(prevPath), "%s/%s/Lifecycle.ksscr", g_testDir, [prevRunID UTF8String]);
    XCTAssertTrue(writeSidecar(prevPath, &prev));

    kscrash_testcode_setLastRunID([prevRunID UTF8String]);
    ksruncontext_testcode_setLifecycleData(&prev);

    // Remove current sidecar so the new run starts fresh
    [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/current", self.tempPath]
                                               error:nil];

    [self enableMonitor];
}

/** Build a valid previous sidecar struct with clean or crash state. */
- (KSCrash_LifecycleData)makePreviousSidecarWithCleanShutdown:(bool)clean
                                       launchesSinceLastCrash:(int32_t)launches
                                       sessionsSinceLastCrash:(int32_t)sessions
                               activeDurationSinceLastCrashNs:(uint64_t)activeNs
                           backgroundDurationSinceLastCrashNs:(uint64_t)bgNs
{
    KSCrash_LifecycleData prev = { 0 };
    prev.magic = KSLIFECYCLE_MAGIC;
    prev.version = KSCrash_Lifecycle_CurrentVersion;
    prev.cleanShutdown = clean;
    prev.launchesSinceLastCrash = launches;
    prev.sessionsSinceLastCrash = sessions;
    prev.activeDurationSinceLastCrashNs = activeNs;
    prev.backgroundDurationSinceLastCrashNs = bgNs;
    prev.activeDurationSinceLaunchNs = 500000000ULL;      // 0.5s per-launch active
    prev.backgroundDurationSinceLaunchNs = 200000000ULL;  // 0.2s per-launch bg
    prev.sessionsSinceLaunch = 1;
    return prev;
}

#pragma mark - Tests -

- (void)testFirstLaunchState
{
    [self enableMonitor];
    KSCrash_AppState state = kscrashstate_lifecycleAppState();

    XCTAssertEqual(state.launchesSinceLastCrash, 1);
    XCTAssertEqual(state.sessionsSinceLastCrash, 1);
    XCTAssertEqual(state.sessionsSinceLaunch, 1);
    // Durations may be slightly > 0 due to time elapsed since enable
    XCTAssertTrue(state.activeDurationSinceLastCrash >= 0.0);
    XCTAssertTrue(state.activeDurationSinceLaunch >= 0.0);
}

- (void)testCurrentStateBeforeEnable
{
    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertFalse(state.applicationIsActive);
    XCTAssertFalse(state.applicationIsInForeground);
    XCTAssertEqual(state.activeDurationSinceLaunch, 0.0);
    XCTAssertEqual(state.backgroundDurationSinceLaunch, 0.0);
    XCTAssertEqual(state.launchesSinceLastCrash, 0);
    XCTAssertEqual(state.sessionsSinceLastCrash, 0);
}

- (void)testLifecycleDataStructLayout
{
    XCTAssertEqual(sizeof(KSCrash_LifecycleData), 184u);
    XCTAssertEqual(KSLIFECYCLE_MAGIC, (int32_t)0x6B736C63);
    XCTAssertEqual(KSCrash_Lifecycle_CurrentVersion, 4);
}

- (void)testRelaunchAfterCrash
{
    // Previous run did NOT shut down cleanly → crash
    ksruncontext_testcode_setReason(KSTerminationReasonCrash);
    KSCrash_LifecycleData prev = [self makePreviousSidecarWithCleanShutdown:false
                                                     launchesSinceLastCrash:5
                                                     sessionsSinceLastCrash:10
                                             activeDurationSinceLastCrashNs:1000000000ULL
                                         backgroundDurationSinceLastCrashNs:2000000000ULL];
    [self simulateRelaunchWithPreviousSidecar:prev];

    XCTAssertTrue(ksruncontext_previousRunContext()->producedReport);
    // After a crash, cumulative counters reset to 0 + this launch
    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertEqual(state.launchesSinceLastCrash, 1);
    XCTAssertEqual(state.sessionsSinceLastCrash, 1);
    XCTAssertEqual(state.sessionsSinceLaunch, 1);
}

- (void)testRelaunchAfterCleanShutdown
{
    // Previous run shut down cleanly → no crash
    ksruncontext_testcode_setReason(KSTerminationReasonClean);
    KSCrash_LifecycleData prev = [self makePreviousSidecarWithCleanShutdown:true
                                                     launchesSinceLastCrash:3
                                                     sessionsSinceLastCrash:7
                                             activeDurationSinceLastCrashNs:1000000000ULL
                                         backgroundDurationSinceLastCrashNs:2000000000ULL];
    [self simulateRelaunchWithPreviousSidecar:prev];

    XCTAssertFalse(ksruncontext_previousRunContext()->producedReport);
    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    // Cumulative = previous cumulatives + previous per-launch, plus this launch
    // launches: 3 + 1 = 4
    XCTAssertEqual(state.launchesSinceLastCrash, 4);
    // sessions: 7 + 1 = 8 (previous cumulatives + previous per-launch sessions carried forward, plus this launch)
    XCTAssertEqual(state.sessionsSinceLastCrash, 8);
    // Per-launch resets
    XCTAssertEqual(state.sessionsSinceLaunch, 1);

    // sinceLastCrashNs already includes the previous run's per-launch durations
    // (updateSidecarDurations adds elapsed to both fields), so we just carry it forward.
    // Active: previous cumulative 1.0s, plus a tiny amount since enable
    XCTAssertTrue(state.activeDurationSinceLastCrash >= 1.0);
    // Background: previous cumulative 2.0s
    XCTAssertTrue(state.backgroundDurationSinceLastCrash >= 2.0);
}

- (void)testRelaunchCrashThenClean
{
    // First: crash relaunch
    ksruncontext_testcode_setReason(KSTerminationReasonCrash);
    KSCrash_LifecycleData crashed = [self makePreviousSidecarWithCleanShutdown:false
                                                        launchesSinceLastCrash:10
                                                        sessionsSinceLastCrash:20
                                                activeDurationSinceLastCrashNs:5000000000ULL
                                            backgroundDurationSinceLastCrashNs:3000000000ULL];
    [self simulateRelaunchWithPreviousSidecar:crashed];

    XCTAssertTrue(ksruncontext_previousRunContext()->producedReport);
    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertEqual(state.launchesSinceLastCrash, 1);  // Reset after crash

    [self disableMonitor];

    // Second: clean shutdown relaunch — read the sidecar we just wrote
    // Manually patch the current sidecar to mark it as clean
    char currentPath[1024];
    snprintf(currentPath, sizeof(currentPath), "%s/current/Lifecycle.ksscr", g_testDir);
    KSCrash_LifecycleData current = { 0 };
    int fd = open(currentPath, O_RDONLY);
    XCTAssertTrue(fd >= 0);
    ssize_t bytesRead = read(fd, &current, sizeof(current));
    close(fd);
    XCTAssertEqual(bytesRead, (ssize_t)sizeof(current));

    // Verify it was a valid sidecar
    XCTAssertEqual(current.magic, KSLIFECYCLE_MAGIC);

    // Mark it as clean shutdown
    current.cleanShutdown = true;

    // Write as previous
    NSString *prevRunID2 = @"00000000-0000-0000-0000-000000000002";
    NSString *prevDir = [NSString stringWithFormat:@"%@/%@", self.tempPath, prevRunID2];
    [[NSFileManager defaultManager] createDirectoryAtPath:prevDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    char prevPath[1024];
    snprintf(prevPath, sizeof(prevPath), "%s/%s/Lifecycle.ksscr", g_testDir, [prevRunID2 UTF8String]);
    XCTAssertTrue(writeSidecar(prevPath, &current));

    kscrash_testcode_setLastRunID([prevRunID2 UTF8String]);
    [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@/current", self.tempPath]
                                               error:nil];

    ksruncontext_testcode_setReason(KSTerminationReasonClean);
    ksruncontext_testcode_setLifecycleData(&current);
    [self enableMonitor];
    state = kscrashstate_lifecycleAppState();
    XCTAssertFalse(ksruncontext_previousRunContext()->producedReport);
    XCTAssertEqual(state.launchesSinceLastCrash, 2);  // Carried forward from first crash reset
}

- (void)testNoPreviousSidecarMeansNoCrash
{
    // Set a last run ID but don't create a sidecar file for it
    kscrash_testcode_setLastRunID("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
    [self enableMonitor];

    // No previous sidecar found → treated as first launch
    XCTAssertFalse(ksruncontext_previousRunContext()->producedReport);
    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertEqual(state.launchesSinceLastCrash, 1);
}

- (void)testCorruptPreviousSidecarIgnored
{
    // Write garbage data as a previous sidecar
    NSString *corruptRunID = @"11111111-2222-3333-4444-555555555555";
    NSString *prevDir = [NSString stringWithFormat:@"%@/%@", self.tempPath, corruptRunID];
    [[NSFileManager defaultManager] createDirectoryAtPath:prevDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    char prevPath[1024];
    snprintf(prevPath, sizeof(prevPath), "%s/%s/Lifecycle.ksscr", g_testDir, [corruptRunID UTF8String]);
    char garbage[sizeof(KSCrash_LifecycleData)] = { 0xFF };
    int fd = open(prevPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    XCTAssertTrue(fd >= 0);
    ssize_t written = write(fd, garbage, sizeof(garbage));
    close(fd);
    XCTAssertEqual(written, (ssize_t)sizeof(garbage));

    kscrash_testcode_setLastRunID([corruptRunID UTF8String]);
    [self enableMonitor];

    XCTAssertFalse(ksruncontext_previousRunContext()->producedReport);
    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertEqual(state.launchesSinceLastCrash, 1);
}

#pragma mark - Transition Tests -

- (void)testActiveTransitionSetsFlag
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertTrue(state.applicationIsActive);
    XCTAssertTrue(state.applicationIsInForeground);
}

- (void)testDeactivatingTransitionClearsActiveFlag
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);

    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertFalse(state.applicationIsActive);
    // Still in foreground after deactivating
    XCTAssertTrue(state.applicationIsInForeground);
}

- (void)testBackgroundTransitionClearsForegroundFlag
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);

    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertFalse(state.applicationIsActive);
    XCTAssertFalse(state.applicationIsInForeground);
}

- (void)testForegroundingTransitionSetsFlagAndIncrementsSession
{
    [self enableMonitor];
    // Simulate a full background → foreground cycle
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);

    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertTrue(state.applicationIsInForeground);
    // Backgrounding bumps only the imperceptible bucket, not the public
    // counters: 1 (initial) + 1 (foregrounding) = 2 — the historical semantics.
    XCTAssertEqual(state.sessionsSinceLaunch, 2);
    XCTAssertEqual(state.sessionsSinceLastCrash, 2);
}

- (void)testMultipleForegroundCyclesIncrementSessions
{
    [self enableMonitor];

    for (int i = 0; i < 3; i++) {
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);
    }

    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    // 1 (initial) + 3 cycles × foregrounding = 4. Backgrounding bumps only the
    // imperceptible bucket, never the public sessionsSinceLaunch.
    XCTAssertEqual(state.sessionsSinceLaunch, 4);
}

#pragma mark - Perceptible / imperceptible session counts (v2)

- (void)testLaunchAloneDoesNotCountPerceptibleSession
{
    // A launch that has not actually reached the foreground owes a perceptible
    // session but must not have counted one yet — regardless of the transient
    // install-time transition state. (The public sessionsSinceLaunch keeps its
    // historical launch == 1 meaning.)
    [self enableMonitor];

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.perceptibleSessionsSinceLaunch, 0u);
    XCTAssertEqual(data.imperceptibleSessionsSinceLaunch, 0u);
    XCTAssertEqual(data.sessionsSinceLaunch, 1);
}

- (void)testForegroundAfterLaunchCountsOnePerceptibleSession
{
    // Plain (non-scene) cold launch: reaches the foreground via Active with no
    // Foregrounding. The owed launch session is counted exactly once.
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.perceptibleSessionsSinceLaunch, 1u);
    XCTAssertEqual(data.imperceptibleSessionsSinceLaunch, 0u);
}

- (void)testLaunchTimeForegroundingCountsOnce
{
    // Scene-style launch: Foregrounding then Active during the launch itself,
    // no preceding background. The owed launch session is counted exactly once
    // (on Foregrounding); the following Active does not double it. The public
    // sessionsSinceLaunch retains its historical launch + foreground-resume
    // semantics (1 launch + 1 foregrounding = 2) and is intentionally
    // unchanged by this fix.
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.perceptibleSessionsSinceLaunch, 1u);
    XCTAssertEqual(data.imperceptibleSessionsSinceLaunch, 0u);
    XCTAssertEqual(data.sessionsSinceLaunch, 2);
}

- (void)testTransientDeactivateReactivateDoesNotRecount
{
    // Control Center / app switcher: Active -> Deactivating -> Active with no
    // Background in between is the same perceptible session, not a new one.
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.perceptibleSessionsSinceLaunch, 1u);
    XCTAssertEqual(data.imperceptibleSessionsSinceLaunch, 0u);
}

- (void)testRealResumeAfterForegroundCountsAgain
{
    // A launch-time foreground counts once; a later real background -> foreground
    // counts a second perceptible session and one imperceptible session.
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);  // launch fg
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);  // real resume

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.perceptibleSessionsSinceLaunch, 2u);
    XCTAssertEqual(data.imperceptibleSessionsSinceLaunch, 1u);
    XCTAssertEqual(data.sessionsSinceLaunch, 3);
}

- (void)testBackgroundAndForegroundingBumpRespectiveCounters
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    // Active counts the launch perceptible session (1); Background bumps
    // imperceptible (1) and re-owes a session; the resume Foregrounding counts
    // perceptible (2). The public sessionsSinceLaunch is decoupled: launch +
    // foreground resume only, so it is 2, NOT the bucket sum (3).
    XCTAssertEqual(data.perceptibleSessionsSinceLaunch, 2u);
    XCTAssertEqual(data.imperceptibleSessionsSinceLaunch, 1u);
    XCTAssertEqual(data.sessionsSinceLaunch, 2);
}

- (void)testSessionsSinceLaunchDecoupledFromPerceptibilityBuckets
{
    [self enableMonitor];
    for (int i = 0; i < 5; i++) {
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);
    }

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    // Public counter: 1 launch + 5 foreground resumes = 6 (backgrounding does
    // not touch it). Buckets: perceptible = launch (first Active) + 5 resume
    // foregroundings = 6, imperceptible = 5 backgrounds. The public counter is
    // intentionally NOT the sum of the buckets.
    XCTAssertEqual(data.sessionsSinceLaunch, 6);
    XCTAssertEqual(data.perceptibleSessionsSinceLaunch, 6u);
    XCTAssertEqual(data.imperceptibleSessionsSinceLaunch, 5u);
    XCTAssertNotEqual((uint32_t)data.sessionsSinceLaunch,
                      data.perceptibleSessionsSinceLaunch + data.imperceptibleSessionsSinceLaunch);
}

#pragma mark - Distinct user tracking (v2)

- (void)testObserveUser_firstSeenBumpsPerceptibleCount
{
    [self enableMonitor];  // Default state is Active (perceptible).
    kscm_lifecycle_observeUser("alice");

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.distinctPerceptibleUserCount, 1u);
    XCTAssertEqual(data.distinctImperceptibleUserCount, 0u);
}

- (void)testObserveUser_duplicateDoesNotDoubleCount
{
    [self enableMonitor];
    kscm_lifecycle_observeUser("alice");
    kscm_lifecycle_observeUser("alice");
    kscm_lifecycle_observeUser("alice");

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.distinctPerceptibleUserCount, 1u);
}

- (void)testObserveUser_distinctUsersEachCountedOnce
{
    [self enableMonitor];
    kscm_lifecycle_observeUser("alice");
    kscm_lifecycle_observeUser("bob");
    kscm_lifecycle_observeUser("alice");  // already seen
    kscm_lifecycle_observeUser("carol");

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.distinctPerceptibleUserCount, 3u);
}

- (void)testObserveUser_nilAndEmptyAreNoOps
{
    [self enableMonitor];
    kscm_lifecycle_observeUser(NULL);
    kscm_lifecycle_observeUser("");

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.distinctPerceptibleUserCount, 0u);
    XCTAssertEqual(data.distinctImperceptibleUserCount, 0u);
}

- (void)testObserveUser_perceptibilityTransitionReaccountsCurrentUser
{
    [self enableMonitor];
    kscm_lifecycle_observeUser("alice");  // counted in perceptible bucket

    // Drive a transition that flips perceptibility from true → false.
    // Background is not user-perceptible.
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    // alice counted in both buckets: 1 + 1 = 2 total distinctness across buckets.
    XCTAssertEqual(data.distinctPerceptibleUserCount, 1u);
    XCTAssertEqual(data.distinctImperceptibleUserCount, 1u);
}

- (void)testSessionLog_newSessionsInheritCurrentUser
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_observeUser("alice");

    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));

    NSString *path = [NSString stringWithFormat:@"%@/current/Sessions.ksscr", self.tempPath];
    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:path];

    XCTAssertEqual(sessions.count, 3u);
    for (KSCrashRunSummarySession *session in sessions) {
        XCTAssertEqual(session.users.count, 1u);
        XCTAssertEqualObjects(session.users.firstObject.userID, @"alice");
    }
}

- (void)testObserveUser_beforeFirstSessionIsCarriedInByFirstSessionBegin
{
    // Users observed before any session begins are held in g_currentUserID
    // (not written to the log — no session to attach to). The first
    // SESSION_BEGIN attaches the current user via recordSessionBeginWithID:...:userID:.
    [self enableMonitor];
    kscm_lifecycle_observeUser("alice");
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    NSString *path = [NSString stringWithFormat:@"%@/current/Sessions.ksscr", self.tempPath];
    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqualObjects(sessions.firstObject.users.firstObject.userID, @"alice");
}

- (void)testObserveUser_logoutBreaksAdjacentUserDedup
{
    // Sign-out clears g_currentUserID but records nothing in the log.
    // A subsequent activation of the same user must land as a fresh
    // record with a new at_ms — the "when did this user become active"
    // contract — instead of being deduped against the pre-logout id.
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_observeUser("alice");
    kscm_lifecycle_observeUser(NULL);     // sign-out — no record, but breaks dedup
    kscm_lifecycle_observeUser("alice");  // must record: alice reactivated

    NSString *path = [NSString stringWithFormat:@"%@/current/Sessions.ksscr", self.tempPath];
    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions[0].users.count, 2u);
    XCTAssertEqualObjects(sessions[0].users[0].userID, @"alice");
    XCTAssertEqualObjects(sessions[0].users[1].userID, @"alice");
    // Two distinct entries prove the dedup was broken; the ms
    // timestamps may collide in fast test runs, but the second at_ms
    // is never *earlier* than the first.
    XCTAssertGreaterThanOrEqual(sessions[0].users[1].atMs, sessions[0].users[0].atMs);
}

- (void)testObserveUser_concurrentReloginWaitsForLogoutDedupReset
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_observeUser("alice");

    Method method = class_getInstanceMethod(KSCrashSessionLog.class, @selector(forgetLastUserID));
    g_originalForgetLastUserID = (ForgetLastUserIDIMP)method_setImplementation(method, (IMP)blockingForgetLastUserID);
    g_forgetLastUserIDEntered = dispatch_semaphore_create(0);
    g_forgetLastUserIDRelease = dispatch_semaphore_create(0);

    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        kscm_lifecycle_observeUser(NULL);
    });
    XCTAssertEqual(dispatch_semaphore_wait(g_forgetLastUserIDEntered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)),
                   0);

    dispatch_semaphore_t reloginStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t reloginFinished = dispatch_semaphore_create(0);
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_semaphore_signal(reloginStarted);
        kscm_lifecycle_observeUser("alice");
        dispatch_semaphore_signal(reloginFinished);
    });
    XCTAssertEqual(dispatch_semaphore_wait(reloginStarted, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    long finishedWhileLogoutResetWasPaused =
        dispatch_semaphore_wait(reloginFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10));

    dispatch_semaphore_signal(g_forgetLastUserIDRelease);
    XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    method_setImplementation(method, (IMP)g_originalForgetLastUserID);
    g_originalForgetLastUserID = NULL;
    g_forgetLastUserIDEntered = nil;
    g_forgetLastUserIDRelease = nil;

    XCTAssertNotEqual(finishedWhileLogoutResetWasPaused, 0,
                      @"Re-login must wait until logout resets the session log's adjacent-user dedup state");

    NSString *path = [NSString stringWithFormat:@"%@/current/Sessions.ksscr", self.tempPath];
    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:path];
    XCTAssertEqual(sessions.count, 1u);
    XCTAssertEqual(sessions[0].users.count, 2u);
    if (sessions[0].users.count == 2) {
        XCTAssertEqualObjects(sessions[0].users[0].userID, @"alice");
        XCTAssertEqualObjects(sessions[0].users[1].userID, @"alice");
    }
}

- (void)testSessionBeginSerializesWithConcurrentUserChange
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_observeUser("alice");

    Method method = class_getInstanceMethod(KSCrashSessionLog.class, @selector(recordSessionBeginWithID:
                                                                                            perceptible:atMs:userID:));
    g_originalSessionBegin = (SessionBeginIMP)method_setImplementation(method, (IMP)blockingSessionBegin);
    g_sessionBeginEntered = dispatch_semaphore_create(0);
    g_sessionBeginRelease = dispatch_semaphore_create(0);

    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
    });
    XCTAssertEqual(dispatch_semaphore_wait(g_sessionBeginEntered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);

    dispatch_semaphore_t userStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t userFinished = dispatch_semaphore_create(0);
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_semaphore_signal(userStarted);
        kscm_lifecycle_observeUser("bob");
        dispatch_semaphore_signal(userFinished);
    });
    XCTAssertEqual(dispatch_semaphore_wait(userStarted, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    long finishedWhileBeginWasPaused =
        dispatch_semaphore_wait(userFinished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10));

    dispatch_semaphore_signal(g_sessionBeginRelease);
    XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    method_setImplementation(method, (IMP)g_originalSessionBegin);
    g_originalSessionBegin = NULL;
    g_sessionBeginEntered = nil;
    g_sessionBeginRelease = nil;

    XCTAssertNotEqual(finishedWhileBeginWasPaused, 0,
                      @"User changes must wait while a session begin owns the shared ordering lock");

    NSString *path = [NSString stringWithFormat:@"%@/current/Sessions.ksscr", self.tempPath];
    NSArray<KSCrashRunSummarySession *> *sessions = [KSCrashSessionLog sessionsAtPath:path];
    XCTAssertEqual(sessions.count, 2u);
    XCTAssertEqualObjects(sessions[0].users.lastObject.userID, @"alice");
    XCTAssertEqualObjects(sessions[1].users.firstObject.userID, @"alice");
    XCTAssertEqualObjects(sessions[1].users.lastObject.userID, @"bob");
}

- (void)testSessionID_bothSlotsAreUsedAcrossSessions
{
    // The double-buffered layout guarantees a mid-generation crash reads
    // the *previous* slot's UUID intact. That only works if the writer
    // actually alternates slots across session begins — otherwise a new
    // session's write clobbers the very bytes the reader would fall back
    // to. Confirm both slots hold plausible UUIDs after enough cycles.
    [self enableMonitor];
    for (int i = 0; i < 3; i++) {
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
        kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);
    }

    KSCrash_LifecycleData snapshot = { 0 };
    XCTAssertTrue(readCurrentSidecar(&snapshot));
    XCTAssertLessThanOrEqual(snapshot.currentSessionIDSlot, 1);
    for (int slot = 0; slot < 2; slot++) {
        NSString *slotID = [NSString stringWithUTF8String:snapshot.currentSessionIDs[slot]];
        XCTAssertEqual(slotID.length, 36u, @"slot %d holds a full UUID", slot);
    }
    XCTAssertNotEqualObjects([NSString stringWithUTF8String:snapshot.currentSessionIDs[0]],
                             [NSString stringWithUTF8String:snapshot.currentSessionIDs[1]]);

    // The reader picks the slot the selector points at.
    NSString *reported = [NSString stringWithUTF8String:kslifecycle_currentSessionIDSnapshot(&snapshot)];
    NSString *fromSelector = [NSString stringWithUTF8String:snapshot.currentSessionIDs[snapshot.currentSessionIDSlot]];
    XCTAssertEqualObjects(reported, fromSelector);
}

- (void)testSessionID_snapshotIgnoresGarbageInInactiveSlot
{
    // Simulate a mid-`ksid_generate` crash: the inactive slot's bytes get
    // clobbered before the selector flip. Reader must read from the
    // selector-pointed slot and ignore the corrupted one entirely.
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    KSCrash_LifecycleData snapshot = { 0 };
    XCTAssertTrue(readCurrentSidecar(&snapshot));
    NSString *goodID = @(kslifecycle_currentSessionIDSnapshot(&snapshot));

    uint8_t activeSlot = snapshot.currentSessionIDSlot;
    uint8_t inactiveSlot = activeSlot ^ 1;
    memset(snapshot.currentSessionIDs[inactiveSlot], 'X', sizeof(snapshot.currentSessionIDs[inactiveSlot]) - 1);
    snapshot.currentSessionIDs[inactiveSlot][sizeof(snapshot.currentSessionIDs[inactiveSlot]) - 1] = '\0';

    // Selector still points at the active slot; the reader keys off it,
    // so the garbage in the inactive slot is invisible.
    const char *afterCorruption = kslifecycle_currentSessionIDSnapshot(&snapshot);
    XCTAssertEqualObjects(@(afterCorruption), goodID);
}

- (void)testSessionID_snapshotReturnsNullForFreshSidecar
{
    // A zero-filled sidecar (fresh mmap, or v3 short-read where the
    // v4 fields default to zero) must surface as "no session yet"
    // rather than a slot-0 pointer to 37 null bytes.
    KSCrash_LifecycleData fresh = { 0 };
    XCTAssertTrue(kslifecycle_currentSessionIDSnapshot(&fresh) == NULL);
}

- (void)testReadData_v1Sidecar_zeroFillsNewFields
{
    // Construct a v1-sized (88-byte) sidecar on disk. The readData function
    // must tolerate the short file and leave the new v2 fields zero-filled.
    KSCrash_LifecycleData v2 = { 0 };
    v2.magic = KSLIFECYCLE_MAGIC;
    v2.version = 1;  // pretend this is a v1 sidecar
    v2.sessionsSinceLaunch = 7;
    v2.launchesSinceLastCrash = 3;
    v2.perceptibleSessionsSinceLaunch = 999;  // "garbage" trailing bytes we won't write
    v2.imperceptibleSessionsSinceLaunch = 999;

    NSString *path = [self.tempPath stringByAppendingPathComponent:@"v1.ksscr"];
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    XCTAssertNotEqual(fd, -1);
    const size_t v1Size = 88;  // historical v1 struct size
    ssize_t written = write(fd, &v2, v1Size);
    close(fd);
    XCTAssertEqual(written, (ssize_t)v1Size);

    KSCrash_LifecycleData out = { 0 };
    XCTAssertTrue(kslifecycle_readData(path.fileSystemRepresentation, &out));
    XCTAssertEqual(out.sessionsSinceLaunch, 7);
    XCTAssertEqual(out.launchesSinceLastCrash, 3);
    // New v2 fields weren't in the file → zero-filled, not garbage.
    XCTAssertEqual(out.perceptibleSessionsSinceLaunch, 0u);
    XCTAssertEqual(out.imperceptibleSessionsSinceLaunch, 0u);
}

- (void)testTerminatingTransitionSetsCleanShutdown
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateTerminating);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertTrue(data.cleanShutdown);
}

- (void)testNonFatalEventDoesNotClearCleanShutdown
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateTerminating);

    KSCrashMonitorAPI *api = kscm_lifecycle_getAPI();
    KSCrash_MonitorContext eventContext = { 0 };
    eventContext.requirements.isFatal = false;
    api->addContextualInfoToEvent(&eventContext, api->context);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertTrue(data.cleanShutdown);
}

- (void)testFatalEventClearsCleanShutdown
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateTerminating);

    KSCrashMonitorAPI *api = kscm_lifecycle_getAPI();
    KSCrash_MonitorContext eventContext = { 0 };
    eventContext.requirements.isFatal = true;
    api->addContextualInfoToEvent(&eventContext, api->context);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertFalse(data.cleanShutdown);
}

- (void)testFatalCleanExitSetsCleanShutdown
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    KSCrashMonitorAPI *api = kscm_lifecycle_getAPI();
    KSCrash_MonitorContext eventContext = { 0 };
    eventContext.requirements.isFatal = true;
    eventContext.requirements.isCleanExit = true;
    api->addContextualInfoToEvent(&eventContext, api->context);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertTrue(data.cleanShutdown);
}

- (void)testFatalCrashExitClearsCleanShutdown
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateTerminating);

    KSCrashMonitorAPI *api = kscm_lifecycle_getAPI();
    KSCrash_MonitorContext eventContext = { 0 };
    eventContext.requirements.isFatal = true;
    eventContext.requirements.isCleanExit = false;
    api->addContextualInfoToEvent(&eventContext, api->context);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertFalse(data.cleanShutdown);
}

- (void)testActiveDurationAccumulates
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    // Small delay to accumulate measurable active duration
    usleep(50000);  // 50ms

    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);

    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    // Should have accumulated at least 40ms of active duration (allowing for timing variance)
    XCTAssertTrue(state.activeDurationSinceLaunch >= 0.04);
    XCTAssertTrue(state.activeDurationSinceLastCrash >= 0.04);
}

- (void)testAddContextualInfoWithNullEventContext
{
    [self enableMonitor];
    KSCrashMonitorAPI *api = kscm_lifecycle_getAPI();

    // Should not crash — exercises the NULL guard in addContextualInfoToEvent
    api->addContextualInfoToEvent(NULL, api->context);

    // Verify the monitor is still functional after the NULL call
    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertEqual(state.launchesSinceLastCrash, 1);
}

- (void)testBackgroundDurationAccumulates
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateDeactivating);
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateBackground);

    // Small delay to accumulate measurable background duration
    usleep(50000);  // 50ms

    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateForegrounding);

    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertTrue(state.backgroundDurationSinceLaunch >= 0.04);
    XCTAssertTrue(state.backgroundDurationSinceLastCrash >= 0.04);
}

#pragma mark - Hang In Progress Tests -

- (void)testHangStartedSetsFlag
{
    [self enableMonitor];
    kscm_lifecycle_testcode_hangChange(KSHangChangeTypeStarted);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertTrue(data.hangInProgress);
}

- (void)testHangEndedClearsFlag
{
    [self enableMonitor];
    kscm_lifecycle_testcode_hangChange(KSHangChangeTypeStarted);
    kscm_lifecycle_testcode_hangChange(KSHangChangeTypeEnded);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertFalse(data.hangInProgress);
}

#pragma mark - Task Role Tests -

- (void)testTaskRoleSetOnEnable
{
    [self enableMonitor];
    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    // The role should be set to something valid (not left at zero unless TASK_UNSPECIFIED == 0)
    int currentRole = kstaskrole_current();
    XCTAssertEqual(data.taskRole, currentRole);
}

- (void)testTaskRoleUpdatedOnTransition
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    int currentRole = kstaskrole_current();
    XCTAssertEqual(data.taskRole, currentRole);
}

- (void)testCurrentTaskRoleReturnsValidValue
{
    int role = kstaskrole_current();
    // The string conversion returns "UNKNOWN" for unrecognized values.
    // A valid role must produce a known string.
    const char *str = kstaskrole_toString(role);
    XCTAssertTrue(strcmp(str, "UNKNOWN") != 0, @"Unexpected task role: %d", role);
}

- (void)testStringFromTaskRoleKnownValues
{
    XCTAssertEqualObjects(@(kstaskrole_toString(TASK_FOREGROUND_APPLICATION)), @"FOREGROUND_APPLICATION");
    XCTAssertEqualObjects(@(kstaskrole_toString(TASK_BACKGROUND_APPLICATION)), @"BACKGROUND_APPLICATION");
    XCTAssertEqualObjects(@(kstaskrole_toString(TASK_UNSPECIFIED)), @"UNSPECIFIED");
    XCTAssertEqualObjects(@(kstaskrole_toString(TASK_DEFAULT_APPLICATION)), @"DEFAULT_APPLICATION");
}

- (void)testStringFromTaskRoleUnknownValue
{
    XCTAssertEqualObjects(@(kstaskrole_toString(9999)), @"UNKNOWN");
}

- (void)testTaskRoleHeartbeatUpdates
{
    [self enableMonitor];

    // Write a sentinel value into the sidecar's taskRole so we can verify
    // the heartbeat overwrites it.  readCurrentSidecar reads via mmap path,
    // so we need to corrupt the live sidecar directly.
    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    int32_t sentinel = -999;
    XCTAssertNotEqual(kstaskrole_current(), sentinel);

    // Poke the sentinel through the test helper.
    kscm_lifecycle_testcode_setTaskRole(sentinel);

    // Verify it took.
    XCTAssertTrue(readCurrentSidecar(&data));
    XCTAssertEqual(data.taskRole, sentinel);

    // Poll until the heartbeat corrects it (up to 5 s).
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    bool corrected = false;
    while ([deadline timeIntervalSinceNow] > 0) {
        [NSThread sleepForTimeInterval:0.1];
        XCTAssertTrue(readCurrentSidecar(&data));
        if (data.taskRole != sentinel) {
            corrected = true;
            break;
        }
    }
    XCTAssertTrue(corrected, @"Heartbeat did not update taskRole within 5 seconds");
    XCTAssertEqual(data.taskRole, kstaskrole_current());
}

@end

#pragma clang diagnostic pop
