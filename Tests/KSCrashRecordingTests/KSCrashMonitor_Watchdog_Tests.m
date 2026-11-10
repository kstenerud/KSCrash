//
//  KSCrashMonitor_Watchdog_Tests.m
//
//  Created by Alexander Cohen on 2025-01-04.
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
#import <mach/task_policy.h>
#import <stdatomic.h>

#import "KSCrashHang.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Watchdog.h"
#import "KSHangEvent.h"
#import "KSThread.h"

// Stub callbacks for testing hang detection
static KSCrash_MonitorContext g_stubContext;

/** The offending thread the watchdog last named, or the sentinel if it has not raised
 * an event yet. MACH_PORT_NULL is a meaningful value here, so the sentinel is not it. */
static thread_t g_stubNotifyThread = (thread_t)~0u;

/** Makes the stub answer every event the way the handler answers one that yielded.
 * Atomic: the test thread sets it while the watchdog's own thread is already running. */
static _Atomic(bool) g_stubRefusesReportInFlight = false;

/** How many events reached the handler; a refused one never should. */
static _Atomic(int) g_stubHandleCount = 0;

/** The main thread's suspend count when the watchdog last called notify, or -1 before it has. */
static _Atomic(int) g_mainSuspendCountAtNotify = -1;

static KSCrash_MonitorContext *stubNotify(thread_t thread, __unused KSCrash_ExceptionHandlingRequirements requirements)
{
    struct thread_basic_info info;
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    if (thread_info((thread_t)ksthread_main(), THREAD_BASIC_INFO, (thread_info_t)&info, &count) == KERN_SUCCESS) {
        atomic_store(&g_mainSuspendCountAtNotify, info.suspend_count);
    }
    g_stubNotifyThread = thread;
    memset(&g_stubContext, 0, sizeof(g_stubContext));
    g_stubContext.requirements.refusedReportInFlight = atomic_load(&g_stubRefusesReportInFlight);
    return &g_stubContext;
}

static void stubHandle(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result, __unused bool finalize)
{
    atomic_fetch_add(&g_stubHandleCount, 1);
    strlcpy(result->reportId, "4C1B2F3E-0000-4000-8000-000000000001", sizeof(result->reportId));
    result->path[0] = '\0';
}

static void stubHandle_deprecated(KSCrash_MonitorContext *context) { stubHandle(context, NULL, false); }

@interface KSSempahore : NSObject {
    dispatch_semaphore_t _semaphore;
}

+ (instancetype)withValue:(NSInteger)value;

- (instancetype)initWithValue:(NSInteger)value NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

@end

@implementation KSSempahore

- (instancetype)init
{
    return [self initWithValue:0];
}

- (instancetype)initWithValue:(NSInteger)value
{
    if ((self = [super init])) {
        _semaphore = dispatch_semaphore_create(value);
    }
    return self;
}

+ (instancetype)withValue:(NSInteger)value
{
    return [[[self class] alloc] initWithValue:value];
}

- (BOOL)wait
{
    return dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER) == 0;
}

- (BOOL)waitForTimeInterval:(NSTimeInterval)timeout
{
    dispatch_time_t t = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    return dispatch_semaphore_wait(_semaphore, t) == 0;
}

- (void)signal
{
    dispatch_semaphore_signal(_semaphore);
}

@end

@interface KSCrashMonitor_Watchdog_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Watchdog_Tests

#pragma mark - Observer Tests

- (void)setUp
{
    [super setUp];
    setenv("KSCRASH_FORCE_ENABLE_WATCHDOG", "1", 1);
}

- (void)tearDown
{
    unsetenv("KSCRASH_FORCE_ENABLE_WATCHDOG");
    [super tearDown];
}

- (void)testIsEnabledTracksSetEnabled
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true, NULL);
    XCTAssertTrue(kshang_isEnabled());
    api->setEnabled(false, NULL);
    XCTAssertFalse(kshang_isEnabled());
}

#pragma mark - Hang Detection Tests

typedef struct {
    KSSempahore *__unsafe_unretained waiter;
    uint64_t start;
    uint64_t end;
    bool started;
} HangCapture;

// The process-wide callback has no context; tests route it through this
// pointer, set for the test's duration and cleared before it ends.
static HangCapture *g_hangCapture;

static void captureHangStart(KSHangChangeType change, uint64_t start, uint64_t end)
{
    HangCapture *capture = g_hangCapture;
    if (capture != NULL && change == KSHangChangeTypeStarted && !capture->started) {
        capture->started = true;
        capture->start = start;
        capture->end = end;
        [capture->waiter signal];
    }
}

- (void)testObserverReceivesHangStarted
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify,
                                                    .handle = stubHandle_deprecated,
                                                    .handleWithResult = stubHandle };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    KSSempahore *waiter = [KSSempahore withValue:0];
    HangCapture capture = { .waiter = waiter };
    g_hangCapture = &capture;
    KSHangEventCallback previous = kshang_setHangEventCallback(captureHangStart);

    XCTAssertTrue([waiter waitForTimeInterval:5]);
    kshang_setHangEventCallback(previous);
    g_hangCapture = NULL;

    XCTAssertGreaterThan(capture.start, 0ULL);
    XCTAssertGreaterThanOrEqual(capture.end, capture.start);

    api->setEnabled(false, NULL);
}

- (void)testNotifyIsCalledWithTheThreadsRunning
{
    // notify() allocates before it suspends the threads, and the main thread may hold a
    // malloc lock.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify,
                                                    .handle = stubHandle_deprecated,
                                                    .handleWithResult = stubHandle };
    atomic_store(&g_mainSuspendCountAtNotify, -1);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    KSSempahore *waiter = [KSSempahore withValue:0];
    HangCapture capture = { .waiter = waiter };
    g_hangCapture = &capture;
    KSHangEventCallback previous = kshang_setHangEventCallback(captureHangStart);

    XCTAssertTrue([waiter waitForTimeInterval:5]);
    kshang_setHangEventCallback(previous);
    g_hangCapture = NULL;

    XCTAssertEqual(atomic_load(&g_mainSuspendCountAtNotify), 0);

    api->setEnabled(false, NULL);
}

static KSSempahore *g_reportBeingWritten;
static KSSempahore *g_hangEnded;
static NSString *g_reportPath;
static _Atomic(int) g_hangsStarted;

static void captureHangChanges(KSHangChangeType change, __unused uint64_t start, __unused uint64_t end)
{
    if (change == KSHangChangeTypeStarted) {
        atomic_fetch_add(&g_hangsStarted, 1);
    } else if (change == KSHangChangeTypeEnded) {
        [g_hangEnded signal];
    }
}

static void stubHandleUntilTheHangEnds(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result,
                                       __unused bool finalize)
{
    [[NSFileManager defaultManager] createFileAtPath:g_reportPath contents:[NSData data] attributes:nil];
    [g_reportBeingWritten signal];
    [g_hangEnded waitForTimeInterval:5];
    strlcpy(result->reportId, "4C1B2F3E-0000-4000-8000-000000000002", sizeof(result->reportId));
    strlcpy(result->path, g_reportPath.fileSystemRepresentation, sizeof(result->path));
}

- (void)testAHangThatEndsWhileItsReportIsWrittenLeavesNoReport
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify,
                                                    .handle = stubHandle_deprecated,
                                                    .handleWithResult = stubHandleUntilTheHangEnds };
    g_reportBeingWritten = [KSSempahore withValue:0];
    g_hangEnded = [KSSempahore withValue:0];
    g_reportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    atomic_store(&g_hangsStarted, 0);
    KSHangEventCallback previous = kshang_setHangEventCallback(captureHangChanges);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue([g_reportBeingWritten waitForTimeInterval:5]);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while ([[NSFileManager defaultManager] fileExistsAtPath:g_reportPath] && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    api->setEnabled(false, NULL);
    kshang_setHangEventCallback(previous);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:g_reportPath]);
    XCTAssertEqual(atomic_load(&g_hangsStarted), 0);
    [[NSFileManager defaultManager] removeItemAtPath:g_reportPath error:nil];
}

- (void)testAHangThatYieldsStillReportsThatItStarted
{
    // A yielded hang writes no report, but the hang happened. The lifecycle notifications
    // describe the hang, not the report, and the hang is already active by now, so later
    // ticks take the update path and never come back here. Without Started, an observer
    // would see an Updated for a hang it was never told about and an Ended clearing it.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify,
                                                    .handle = stubHandle_deprecated,
                                                    .handleWithResult = stubHandle };
    atomic_store(&g_stubRefusesReportInFlight, true);
    atomic_store(&g_stubHandleCount, 0);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    KSSempahore *waiter = [KSSempahore withValue:0];
    HangCapture capture = { .waiter = waiter };
    g_hangCapture = &capture;
    KSHangEventCallback previous = kshang_setHangEventCallback(captureHangStart);

    XCTAssertTrue([waiter waitForTimeInterval:5], @"A yielded hang must still report that it started");
    kshang_setHangEventCallback(previous);
    g_hangCapture = NULL;
    atomic_store(&g_stubRefusesReportInFlight, false);

    XCTAssertGreaterThan(capture.start, 0ULL);
    XCTAssertEqual(atomic_load(&g_stubHandleCount), 0, @"A refused event must never reach the handler");

    api->setEnabled(false, NULL);
}

- (void)testHangEventNamesNoOffendingThread
{
    // The main thread is this report's subject, but it did not fault, it was observed.
    // Naming it would let the recrash check match it against a live handler slot, and a
    // hung main thread is very often hung because it is writing another report; the event
    // would then be classed a recrash and rewrite that report's file in place. Passing
    // MACH_PORT_NULL is what keeps an observed subject out of that check.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify,
                                                    .handle = stubHandle_deprecated,
                                                    .handleWithResult = stubHandle };
    g_stubNotifyThread = (thread_t)~0u;
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    KSSempahore *waiter = [KSSempahore withValue:0];
    HangCapture capture = { .waiter = waiter };
    g_hangCapture = &capture;
    KSHangEventCallback previous = kshang_setHangEventCallback(captureHangStart);

    XCTAssertTrue([waiter waitForTimeInterval:5]);
    kshang_setHangEventCallback(previous);
    g_hangCapture = NULL;

    XCTAssertNotEqual(g_stubNotifyThread, (thread_t)~0u, @"the watchdog should have raised an event");
    XCTAssertEqual(g_stubNotifyThread, (thread_t)MACH_PORT_NULL,
                   @"an observed subject must not be named as the offending thread");

    api->setEnabled(false, NULL);
}

- (void)testHangStartTimestampIsReasonable
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = { .notify = stubNotify,
                                                    .handle = stubHandle_deprecated,
                                                    .handleWithResult = stubHandle };
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    KSSempahore *waiter = [KSSempahore withValue:0];
    HangCapture capture = { .waiter = waiter };
    g_hangCapture = &capture;
    KSHangEventCallback previous = kshang_setHangEventCallback(captureHangStart);

    XCTAssertTrue([waiter waitForTimeInterval:5]);
    kshang_setHangEventCallback(previous);
    g_hangCapture = NULL;

    // The hang duration at "started" time should be at least the threshold
    uint64_t durationNs = capture.end - capture.start;
    double durationSeconds = (double)durationNs / 1000000000.0;

    // Duration should be at least the threshold (249ms)
    XCTAssertGreaterThanOrEqual(durationSeconds, 0.249, @"Hang should be at least threshold duration");
    // But not excessively long
    XCTAssertLessThan(durationSeconds, 3.0, @"Hang duration shouldn't be unreasonably long");

    api->setEnabled(false, NULL);
}

- (void)testHangChangeTypeValues
{
    // Verify the enum values are as expected
    XCTAssertEqual(KSHangChangeTypeNone, 0);
    XCTAssertEqual(KSHangChangeTypeStarted, 1);
    XCTAssertEqual(KSHangChangeTypeUpdated, 2);
    XCTAssertEqual(KSHangChangeTypeEnded, 3);
}

#pragma mark - Enable/Disable Tests

- (void)testInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testDoubleInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testReenableAfterDisable
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));

    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));

    api->setEnabled(false, NULL);
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testMonitorId
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    XCTAssertTrue(strcmp(api->monitorId(NULL), "Watchdog") == 0);
}

- (void)testMonitorFlags
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    XCTAssertEqual(api->monitorFlags(NULL), KSCrashMonitorFlagNone);
}

- (void)testCleanEnableDisable
{
    // Enable and disable multiple times to verify clean lifecycle
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    for (int i = 0; i < 5; i++) {
        api->setEnabled(true, NULL);
        XCTAssertTrue(api->isEnabled(NULL));
        [NSThread sleepForTimeInterval:0.1];
        api->setEnabled(false, NULL);
        XCTAssertFalse(api->isEnabled(NULL));
    }
}

- (void)testRapidEnableDisable
{
    // Rapid enable/disable without sleep
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    for (int i = 0; i < 10; i++) {
        api->setEnabled(true, NULL);
        XCTAssertTrue(api->isEnabled(NULL));
        api->setEnabled(false, NULL);
        XCTAssertFalse(api->isEnabled(NULL));
    }
}

@end
