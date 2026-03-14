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

#include <mach/task_policy.h>

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
extern void kscm_termination_testcode_setReason(KSTerminationReason reason);

// Global test directory for path callbacks
static char g_testDir[1024];

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
    kscm_termination_testcode_setReason(KSTerminationReasonNone);
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
    XCTAssertEqual(sizeof(KSCrash_LifecycleData), 88u);
    XCTAssertEqual(KSLIFECYCLE_MAGIC, (int32_t)0x6B736C63);
}

- (void)testRelaunchAfterCrash
{
    // Previous run did NOT shut down cleanly → crash
    kscm_termination_testcode_setReason(KSTerminationReasonCrash);
    KSCrash_LifecycleData prev = [self makePreviousSidecarWithCleanShutdown:false
                                                     launchesSinceLastCrash:5
                                                     sessionsSinceLastCrash:10
                                             activeDurationSinceLastCrashNs:1000000000ULL
                                         backgroundDurationSinceLastCrashNs:2000000000ULL];
    [self simulateRelaunchWithPreviousSidecar:prev];

    XCTAssertTrue(kstermination_producesReport(kstermination_getReason()));
    // After a crash, cumulative counters reset to 0 + this launch
    KSCrash_AppState state = kscrashstate_lifecycleAppState();
    XCTAssertEqual(state.launchesSinceLastCrash, 1);
    XCTAssertEqual(state.sessionsSinceLastCrash, 1);
    XCTAssertEqual(state.sessionsSinceLaunch, 1);
}

- (void)testRelaunchAfterCleanShutdown
{
    // Previous run shut down cleanly → no crash
    kscm_termination_testcode_setReason(KSTerminationReasonClean);
    KSCrash_LifecycleData prev = [self makePreviousSidecarWithCleanShutdown:true
                                                     launchesSinceLastCrash:3
                                                     sessionsSinceLastCrash:7
                                             activeDurationSinceLastCrashNs:1000000000ULL
                                         backgroundDurationSinceLastCrashNs:2000000000ULL];
    [self simulateRelaunchWithPreviousSidecar:prev];

    XCTAssertFalse(kstermination_producesReport(kstermination_getReason()));
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
    kscm_termination_testcode_setReason(KSTerminationReasonCrash);
    KSCrash_LifecycleData crashed = [self makePreviousSidecarWithCleanShutdown:false
                                                        launchesSinceLastCrash:10
                                                        sessionsSinceLastCrash:20
                                                activeDurationSinceLastCrashNs:5000000000ULL
                                            backgroundDurationSinceLastCrashNs:3000000000ULL];
    [self simulateRelaunchWithPreviousSidecar:crashed];

    XCTAssertTrue(kstermination_producesReport(kstermination_getReason()));
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

    kscm_termination_testcode_setReason(KSTerminationReasonClean);
    [self enableMonitor];
    state = kscrashstate_lifecycleAppState();
    XCTAssertFalse(kstermination_producesReport(kstermination_getReason()));
    XCTAssertEqual(state.launchesSinceLastCrash, 2);  // Carried forward from first crash reset
}

- (void)testNoPreviousSidecarMeansNoCrash
{
    // Set a last run ID but don't create a sidecar file for it
    kscrash_testcode_setLastRunID("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
    [self enableMonitor];

    // No previous sidecar found → treated as first launch
    XCTAssertFalse(kstermination_producesReport(kstermination_getReason()));
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

    XCTAssertFalse(kstermination_producesReport(kstermination_getReason()));
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
    // Session count: 1 (initial) + 1 (foregrounding) = 2
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
    // 1 (initial) + 3 (foregroundings) = 4
    XCTAssertEqual(state.sessionsSinceLaunch, 4);
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
    int currentRole = kslifecycle_currentTaskRole();
    XCTAssertEqual(data.taskRole, currentRole);
}

- (void)testTaskRoleUpdatedOnTransition
{
    [self enableMonitor];
    kscm_lifecycle_testcode_transitionState(KSCrashAppTransitionStateActive);

    KSCrash_LifecycleData data = { 0 };
    XCTAssertTrue(readCurrentSidecar(&data));
    int currentRole = kslifecycle_currentTaskRole();
    XCTAssertEqual(data.taskRole, currentRole);
}

- (void)testCurrentTaskRoleReturnsValidValue
{
    int role = kslifecycle_currentTaskRole();
    // The string conversion returns "UNKNOWN" for unrecognized values.
    // A valid role must produce a known string.
    const char *str = kslifecycle_stringFromTaskRole(role);
    XCTAssertTrue(strcmp(str, "UNKNOWN") != 0, @"Unexpected task role: %d", role);
}

- (void)testStringFromTaskRoleKnownValues
{
    XCTAssertEqualObjects(@(kslifecycle_stringFromTaskRole(TASK_FOREGROUND_APPLICATION)), @"FOREGROUND_APPLICATION");
    XCTAssertEqualObjects(@(kslifecycle_stringFromTaskRole(TASK_BACKGROUND_APPLICATION)), @"BACKGROUND_APPLICATION");
    XCTAssertEqualObjects(@(kslifecycle_stringFromTaskRole(TASK_UNSPECIFIED)), @"UNSPECIFIED");
    XCTAssertEqualObjects(@(kslifecycle_stringFromTaskRole(TASK_DEFAULT_APPLICATION)), @"DEFAULT_APPLICATION");
}

- (void)testStringFromTaskRoleUnknownValue
{
    XCTAssertEqualObjects(@(kslifecycle_stringFromTaskRole(9999)), @"UNKNOWN");
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
    XCTAssertNotEqual(kslifecycle_currentTaskRole(), sentinel);

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
    XCTAssertEqual(data.taskRole, kslifecycle_currentTaskRole());
}

@end

#pragma clang diagnostic pop
