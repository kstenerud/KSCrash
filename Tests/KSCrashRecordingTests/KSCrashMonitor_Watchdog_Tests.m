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

#import "KSCrashAppState.h"
#import "KSCrashHang.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Watchdog.h"
#import "KSCrashMonitor_WatchdogSidecar.h"
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

@class KSSempahore;
/** Signalled at the end of each notify, when a test sets it. A test reading what
 * notify saw waits on this: a hang that writes no report is never announced. */
static KSSempahore *g_notifyCalled;
static void signalNotifyCalled(void);

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
    signalNotifyCalled();
    return &g_stubContext;
}

/** Where stubHandle writes its report; setUp picks a new one. */
static NSString *g_stubReportPath;

/** Writes an empty report and hands its path back, so the hang is recorded and followed. */
static void stubHandle(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result, __unused bool finalize)
{
    atomic_fetch_add(&g_stubHandleCount, 1);
    [[NSFileManager defaultManager] createFileAtPath:g_stubReportPath contents:[NSData data] attributes:nil];
    strlcpy(result->reportId, "4C1B2F3E-0000-4000-8000-000000000001", sizeof(result->reportId));
    strlcpy(result->path, g_stubReportPath.fileSystemRepresentation, sizeof(result->path));
}

/** Answers as the handler does when the app's willWriteReport skipped the report. */
static void stubHandleSkippingTheReport(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result,
                                        __unused bool finalize)
{
    result->reportId[0] = '\0';
    result->path[0] = '\0';
    result->skipped = true;
}

/** Answers as the handler does when the report could not be written. */
static void stubHandleWritingNothing(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result,
                                     __unused bool finalize)
{
    strlcpy(result->reportId, "4C1B2F3E-0000-4000-8000-000000000005", sizeof(result->reportId));
    result->path[0] = '\0';
}

static void stubHandle_deprecated(KSCrash_MonitorContext *context) { stubHandle(context, NULL, false); }

/** Where the watchdog creates its run sidecar. A hang it cannot create one for fails, so
 * every test gets a path; setUp picks a new one. */
static NSString *g_runSidecarPath;

static bool stubRunSidecarPath(__unused const char *monitorId, char *pathBuffer, size_t pathBufferLength)
{
    return strlcpy(pathBuffer, g_runSidecarPath.fileSystemRepresentation, pathBufferLength) < pathBufferLength;
}

/** The callbacks most tests run the watchdog with, writing reports with `handle`. */
static KSCrash_ExceptionHandlerCallbacks callbacksWithHandle(void (*handle)(KSCrash_MonitorContext *,
                                                                            KSCrash_ReportResult *, bool))
{
    return (KSCrash_ExceptionHandlerCallbacks) { .notify = stubNotify,
                                                 .handle = stubHandle_deprecated,
                                                 .handleWithResult = handle,
                                                 .getRunSidecarPath = stubRunSidecarPath };
}

extern bool kscm_watchdog_testcode_isRunning(void);

/** Disables the watchdog and lets the main thread go idle until the monitor has stopped.
 * A test that waits on the main thread is a hang in progress, and a hang in progress
 * finishes before a disabled monitor stops. Returns whether it stopped. */
static BOOL stopWatchdog(void)
{
    kscm_watchdog_getAPI()->setEnabled(false, NULL);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (kscm_watchdog_testcode_isRunning() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return !kscm_watchdog_testcode_isRunning();
}

/** Runs the main run loop for a moment, so the main thread goes idle and ends a hang in
 * progress. Not runMode:beforeDate:, which returns once it has handled a single source:
 * with other work queued on the main thread it can return before ever going idle. */
static void letMainThreadGoIdle(void) { CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false); }

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

static void signalNotifyCalled(void) { [g_notifyCalled signal]; }

/** Every hang change in the order it arrived, with the thread it arrived on. */
#define kMaxRecordedChanges 64
static _Atomic(int) g_recordedCount;
static KSHangChangeType g_recordedChanges[kMaxRecordedChanges];
static pthread_t g_recordedThreads[kMaxRecordedChanges];
static KSSempahore *g_recordedSignal;

// Hang events come from the watchdog thread alone, so there is one writer: it fills
// the slot, then publishes the count with release, and a reader that loads the count
// with acquire sees every slot below it.
static void recordHangChange(KSHangChangeType change, __unused uint64_t start, __unused uint64_t end)
{
    int index = atomic_load_explicit(&g_recordedCount, memory_order_relaxed);
    if (index < kMaxRecordedChanges) {
        g_recordedChanges[index] = change;
        g_recordedThreads[index] = pthread_self();
    }
    atomic_store_explicit(&g_recordedCount, index + 1, memory_order_release);
    [g_recordedSignal signal];
}

static void startRecordingHangChanges(void)
{
    atomic_store(&g_recordedCount, 0);
    memset(g_recordedChanges, 0, sizeof(g_recordedChanges));
    memset(g_recordedThreads, 0, sizeof(g_recordedThreads));
    g_recordedSignal = [KSSempahore withValue:0];
}

/** Whether `change` was recorded within `timeout`. */
static BOOL waitForRecordedChange(KSHangChangeType change, NSTimeInterval timeout)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    for (;;) {
        int count = MIN(atomic_load_explicit(&g_recordedCount, memory_order_acquire), kMaxRecordedChanges);
        for (int i = 0; i < count; i++) {
            if (g_recordedChanges[i] == change) {
                return YES;
            }
        }
        if (deadline.timeIntervalSinceNow <= 0 ||
            ![g_recordedSignal waitForTimeInterval:deadline.timeIntervalSinceNow]) {
            return NO;
        }
    }
}

static int countRecorded(KSHangChangeType change)
{
    int found = 0;
    int count = MIN(atomic_load_explicit(&g_recordedCount, memory_order_acquire), kMaxRecordedChanges);
    for (int i = 0; i < count; i++) {
        found += g_recordedChanges[i] == change ? 1 : 0;
    }
    return found;
}

@interface KSCrashMonitor_Watchdog_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Watchdog_Tests

#pragma mark - Observer Tests

- (void)setUp
{
    [super setUp];
    setenv("KSCRASH_FORCE_ENABLE_WATCHDOG", "1", 1);
    g_runSidecarPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    g_stubReportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
}

- (void)tearDown
{
    XCTAssertTrue(stopWatchdog());
    [[NSFileManager defaultManager] removeItemAtPath:g_runSidecarPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:g_stubReportPath error:nil];
    unsetenv("KSCRASH_FORCE_ENABLE_WATCHDOG");
    [super tearDown];
}

- (void)testIsEnabledTracksSetEnabled
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true, NULL);
    XCTAssertTrue(kshang_isEnabled());
    XCTAssertTrue(stopWatchdog());
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
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandle);
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

    XCTAssertTrue(stopWatchdog());
}

- (void)testNotifyIsCalledWithTheThreadsRunning
{
    // notify() allocates before it suspends the threads, and the main thread may hold a
    // malloc lock.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandle);
    atomic_store(&g_mainSuspendCountAtNotify, -1);
    g_notifyCalled = [KSSempahore withValue:0];
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue([g_notifyCalled waitForTimeInterval:5]);

    XCTAssertEqual(atomic_load(&g_mainSuspendCountAtNotify), 0);

    XCTAssertTrue(stopWatchdog());
    g_notifyCalled = nil;
}

static KSSempahore *g_reportBeingWritten;
static KSSempahore *g_mainWentIdle;
static KSSempahore *g_hangEnded;
static NSString *g_reportPath;
static _Atomic(int) g_hangsStarted;
// The order each change arrived in, counted from 1; 0 until it arrives.
static _Atomic(int) g_changeCount;
static _Atomic(int) g_startedAt;
static _Atomic(int) g_endedAt;

static void captureHangChanges(KSHangChangeType change, __unused uint64_t start, __unused uint64_t end)
{
    int order = atomic_fetch_add(&g_changeCount, 1) + 1;
    if (change == KSHangChangeTypeStarted) {
        atomic_fetch_add(&g_hangsStarted, 1);
        atomic_store(&g_startedAt, order);
    } else if (change == KSHangChangeTypeEnded) {
        atomic_store(&g_endedAt, order);
        [g_hangEnded signal];
    }
}

static void stubHandleUntilTheHangEnds(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result,
                                       __unused bool finalize)
{
    [[NSFileManager defaultManager] createFileAtPath:g_reportPath contents:[NSData data] attributes:nil];
    [g_reportBeingWritten signal];
    [g_mainWentIdle waitForTimeInterval:5];
    strlcpy(result->reportId, "4C1B2F3E-0000-4000-8000-000000000002", sizeof(result->reportId));
    strlcpy(result->path, g_reportPath.fileSystemRepresentation, sizeof(result->path));
}

- (void)testAHangThatEndsWhileItsReportIsWrittenLeavesNoReport
{
    // The main thread goes idle while the report is written. The hang is finished
    // after the write, on the same thread, so it is Started, then Ended, and the
    // report it no longer needs is removed.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandleUntilTheHangEnds);
    g_reportBeingWritten = [KSSempahore withValue:0];
    g_mainWentIdle = [KSSempahore withValue:0];
    g_hangEnded = [KSSempahore withValue:0];
    g_reportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    atomic_store(&g_hangsStarted, 0);
    atomic_store(&g_changeCount, 0);
    atomic_store(&g_startedAt, 0);
    atomic_store(&g_endedAt, 0);
    KSHangEventCallback previous = kshang_setHangEventCallback(captureHangChanges);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue([g_reportBeingWritten waitForTimeInterval:5]);
    letMainThreadGoIdle();
    [g_mainWentIdle signal];
    XCTAssertTrue([g_hangEnded waitForTimeInterval:5]);

    XCTAssertTrue(stopWatchdog());
    kshang_setHangEventCallback(previous);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:g_reportPath]);
    XCTAssertEqual(atomic_load(&g_hangsStarted), 1);
    XCTAssertEqual(atomic_load(&g_startedAt), 1);
    XCTAssertEqual(atomic_load(&g_endedAt), 2);
    [[NSFileManager defaultManager] removeItemAtPath:g_reportPath error:nil];
}

static KSSempahore *g_reportWriteStarted;
static KSSempahore *g_mayFinishTheReport;

/** Holds the report write open until the test lets it go, the way a slow write or a slow
 * Started listener keeps the watchdog thread busy after the hang has ended. */
static void stubHandleHeldOpen(KSCrash_MonitorContext *context, KSCrash_ReportResult *result, bool finalize)
{
    [g_reportWriteStarted signal];
    [g_mayFinishTheReport waitForTimeInterval:5];
    stubHandle(context, result, finalize);
}

/** The hang sidecar as it is on disk right now, or a zeroed one when it cannot be read. */
static KSHangSidecar sidecarOnDisk(void)
{
    KSHangSidecar sidecar = { 0 };
    NSData *data = [NSData dataWithContentsOfFile:g_runSidecarPath];
    if (data.length >= sizeof(sidecar)) {
        memcpy(&sidecar, data.bytes, sizeof(sidecar));
    }
    return sidecar;
}

- (void)testAHangIsMarkedEndedOnDiskAsSoonAsTheMainThreadGoesIdle
{
    // The watchdog thread is still writing the hang's report when the main thread goes
    // idle. A process ending then must find a hang that ended, not one in progress, or the
    // next launch reports a watchdog kill for it.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandleHeldOpen);
    g_reportWriteStarted = [KSSempahore withValue:0];
    g_mayFinishTheReport = [KSSempahore withValue:0];
    startRecordingHangChanges();
    KSHangEventCallback previous = kshang_setHangEventCallback(recordHangChange);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue([g_reportWriteStarted waitForTimeInterval:5]);
    XCTAssertEqual(sidecarOnDisk().magic, KSHANG_SIDECAR_MAGIC);
    XCTAssertFalse(sidecarOnDisk().recovered, @"the hang is still in progress");
    letMainThreadGoIdle();
    KSHangSidecar whileTheReportIsWritten = sidecarOnDisk();
    [g_mayFinishTheReport signal];

    XCTAssertTrue(waitForRecordedChange(KSHangChangeTypeEnded, 5));
    XCTAssertTrue(stopWatchdog());
    kshang_setHangEventCallback(previous);
    g_reportWriteStarted = nil;
    g_mayFinishTheReport = nil;

    XCTAssertEqual(whileTheReportIsWritten.magic, KSHANG_SIDECAR_MAGIC);
    XCTAssertTrue(whileTheReportIsWritten.recovered, @"the ended hang still read as in progress");
    XCTAssertGreaterThan(whileTheReportIsWritten.endTimestamp, whileTheReportIsWritten.startTimestamp);
}

static _Atomic(bool) g_sidecarExistedWhenReportStarted;
static KSSempahore *g_reportStarted;

static void stubHandleCheckingTheSidecar(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result,
                                         __unused bool finalize)
{
    atomic_store(&g_sidecarExistedWhenReportStarted,
                 [[NSFileManager defaultManager] fileExistsAtPath:g_runSidecarPath]);
    strlcpy(result->reportId, "4C1B2F3E-0000-4000-8000-000000000003", sizeof(result->reportId));
    result->path[0] = '\0';
    [g_reportStarted signal];
}

- (void)testTheHangIsRecordedBeforeItsReportIsWritten
{
    // The process can end while the report is being written. The sidecar has to
    // be there by then, or the report left behind has no hang to stitch.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandleCheckingTheSidecar);
    g_reportStarted = [KSSempahore withValue:0];
    atomic_store(&g_sidecarExistedWhenReportStarted, false);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue([g_reportStarted waitForTimeInterval:5]);
    XCTAssertTrue(atomic_load(&g_sidecarExistedWhenReportStarted));

    XCTAssertTrue(stopWatchdog());
    g_reportStarted = nil;
}

static NSString *g_fatalTestReportPath;
static KSSempahore *g_hangUpdated;
static KSSempahore *g_reportedHangEnded;
static _Atomic(int) g_reportedHangsStarted;

static void stubHandleWritingAReport(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result,
                                     __unused bool finalize)
{
    [[NSFileManager defaultManager] createFileAtPath:g_fatalTestReportPath contents:[NSData data] attributes:nil];
    strlcpy(result->reportId, "4C1B2F3E-0000-4000-8000-000000000004", sizeof(result->reportId));
    strlcpy(result->path, g_fatalTestReportPath.fileSystemRepresentation, sizeof(result->path));
}

static void signalHangUpdated(KSHangChangeType change, __unused uint64_t start, __unused uint64_t end)
{
    if (change == KSHangChangeTypeStarted) {
        atomic_fetch_add(&g_reportedHangsStarted, 1);
    } else if (change == KSHangChangeTypeUpdated) {
        [g_hangUpdated signal];
    } else if (change == KSHangChangeTypeEnded) {
        [g_reportedHangEnded signal];
    }
}

/** Enables the watchdog with a handler that writes a real report, and waits for the
 *  hang's first Updated: it comes from the tick after the one that wrote the report, so
 *  by then the report's path is attached. Returns whether the hang got that far. */
static BOOL startHangWithReport(BOOL reportsHangs, KSHangEventCallback *previous)
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandleWritingAReport);
    g_fatalTestReportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    g_hangUpdated = [KSSempahore withValue:0];
    g_reportedHangEnded = [KSSempahore withValue:0];
    atomic_store(&g_reportedHangsStarted, 0);
    *previous = kshang_setHangEventCallback(signalHangUpdated);
    kscm_watchdog_setReportsHangs(reportsHangs);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);
    return [g_hangUpdated waitForTimeInterval:5];
}

static void endHangTest(KSHangEventCallback previous)
{
    kshang_setHangEventCallback(previous);
    kscm_watchdog_setReportsHangs(false);
    g_hangUpdated = nil;
    [[NSFileManager defaultManager] removeItemAtPath:g_fatalTestReportPath error:nil];
}

typedef struct {
    BOOL updated;
    BOOL stopped;
    BOOL reportSurvived;
    BOOL sidecarSurvived;
} FatalEventOutcome;

/** What is left of the hang's record after a fatal event during the hang. */
static FatalEventOutcome fatalEventDuringAHang(BOOL reportsHangs)
{
    KSHangEventCallback previous = NULL;
    FatalEventOutcome outcome = { 0 };
    outcome.updated = startHangWithReport(reportsHangs, &previous);
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_MonitorContext fatalEvent = { 0 };
    fatalEvent.requirements.isFatal = true;
    api->addContextualInfoToEvent(&fatalEvent, NULL);
    outcome.reportSurvived = [[NSFileManager defaultManager] fileExistsAtPath:g_fatalTestReportPath];
    outcome.sidecarSurvived = [[NSFileManager defaultManager] fileExistsAtPath:g_runSidecarPath];

    // Cleaned up before anything is asserted, so a failure here leaves no hang callback
    // or reporting setting behind for the tests after it.
    outcome.stopped = stopWatchdog();
    endHangTest(previous);
    return outcome;
}

- (void)testAFatalEventDuringAHangRemovesItsReportWhenHangReportingIsOff
{
    // The hang did not end the process, and with hang reporting off only a hang that
    // does is reported on its own. The sidecar stays, so the fatal event's report still
    // carries the hang.
    FatalEventOutcome outcome = fatalEventDuringAHang(NO);
    XCTAssertTrue(outcome.updated);
    XCTAssertTrue(outcome.stopped);
    XCTAssertFalse(outcome.reportSurvived);
    XCTAssertTrue(outcome.sidecarSurvived);
}

- (void)testAFatalEventDuringAHangKeepsItsReportWhenHangReportingIsOn
{
    FatalEventOutcome outcome = fatalEventDuringAHang(YES);
    XCTAssertTrue(outcome.updated);
    XCTAssertTrue(outcome.stopped);
    XCTAssertTrue(outcome.reportSurvived);
    XCTAssertTrue(outcome.sidecarSurvived);
}

extern void kscm_watchdog_testcode_runExitHandler(void);

/** Whether the hang's report, and its sidecar, are still there after a normal exit during it. */
static FatalEventOutcome normalExitDuringAHang(BOOL reportsHangs)
{
    KSHangEventCallback previous = NULL;
    FatalEventOutcome outcome = { 0 };
    outcome.updated = startHangWithReport(reportsHangs, &previous);
    kscm_watchdog_testcode_runExitHandler();
    outcome.reportSurvived = [[NSFileManager defaultManager] fileExistsAtPath:g_fatalTestReportPath];
    outcome.sidecarSurvived = [[NSFileManager defaultManager] fileExistsAtPath:g_runSidecarPath];
    outcome.stopped = stopWatchdog();
    endHangTest(previous);
    return outcome;
}

- (void)testANormalExitDuringAHangRemovesItsReportWhenHangReportingIsOff
{
    // A normal exit did not end the app because of the hang, so with reporting off the
    // hang has no report of its own. The sidecar stays: the run still had a hang going.
    FatalEventOutcome outcome = normalExitDuringAHang(NO);
    XCTAssertTrue(outcome.updated);
    XCTAssertTrue(outcome.stopped);
    XCTAssertFalse(outcome.reportSurvived);
    XCTAssertTrue(outcome.sidecarSurvived);
}

- (void)testANormalExitDuringAHangKeepsItsReportWhenHangReportingIsOn
{
    FatalEventOutcome outcome = normalExitDuringAHang(YES);
    XCTAssertTrue(outcome.updated);
    XCTAssertTrue(outcome.stopped);
    XCTAssertTrue(outcome.reportSurvived);
    XCTAssertTrue(outcome.sidecarSurvived);
}

- (void)testDisablingTheWatchdogDuringAHangLetsTheHangFinish
{
    // The hang started with the watchdog enabled, so it finishes as though it still
    // were: its report stays until the hang ends, the hang ends with Ended, and only
    // then does the monitor stop.
    KSHangEventCallback previous = NULL;
    XCTAssertTrue(startHangWithReport(NO, &previous));

    kscm_watchdog_getAPI()->setEnabled(false, NULL);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:g_fatalTestReportPath]);
    XCTAssertTrue(kscm_watchdog_getAPI()->isEnabled(NULL), @"still following the hang");

    XCTAssertTrue(stopWatchdog());
    XCTAssertTrue([g_reportedHangEnded waitForTimeInterval:0]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:g_fatalTestReportPath],
                   @"hang reporting was off when the hang started");
    XCTAssertFalse(kscm_watchdog_getAPI()->isEnabled(NULL));
    endHangTest(previous);
}

- (void)testReenablingDuringAHangKeepsFollowingTheSameHang
{
    KSHangEventCallback previous = NULL;
    XCTAssertTrue(startHangWithReport(NO, &previous));

    kscm_watchdog_getAPI()->setEnabled(false, NULL);
    kscm_watchdog_getAPI()->setEnabled(true, NULL);
    letMainThreadGoIdle();
    XCTAssertTrue([g_reportedHangEnded waitForTimeInterval:5]);

    // Let a stop posted for the finished hang run, if one was: it must not stop the
    // monitor that was enabled again.
    letMainThreadGoIdle();
    XCTAssertTrue(kscm_watchdog_testcode_isRunning());
    XCTAssertEqual(atomic_load(&g_reportedHangsStarted), 1, @"one hang, followed once");

    XCTAssertTrue(stopWatchdog());
    endHangTest(previous);
}

- (void)testAHangFollowsTheHangReportingSettingItStartedWith
{
    // Hang reporting is turned off during a hang that started with it on. A fatal event
    // during the hang removes the report only when reporting is off for that hang, so the
    // report surviving shows the hang kept the setting it started with.
    KSHangEventCallback previous = NULL;
    XCTAssertTrue(startHangWithReport(YES, &previous));
    kscm_watchdog_setReportsHangs(false);

    KSCrash_MonitorContext fatalEvent = { 0 };
    fatalEvent.requirements.isFatal = true;
    kscm_watchdog_getAPI()->addContextualInfoToEvent(&fatalEvent, NULL);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:g_fatalTestReportPath]);

    XCTAssertTrue(stopWatchdog());
    endHangTest(previous);
}

- (void)testEveryHangEventComesFromTheWatchdogThread
{
    // One thread for every event, so a listener sees them in order and needs no lock.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandleWritingAReport);
    g_fatalTestReportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    startRecordingHangChanges();
    KSHangEventCallback previous = kshang_setHangEventCallback(recordHangChange);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue(waitForRecordedChange(KSHangChangeTypeUpdated, 5));
    letMainThreadGoIdle();
    XCTAssertTrue(waitForRecordedChange(KSHangChangeTypeEnded, 5));
    XCTAssertTrue(stopWatchdog());
    kshang_setHangEventCallback(previous);
    [[NSFileManager defaultManager] removeItemAtPath:g_fatalTestReportPath error:nil];

    int count = MIN(atomic_load(&g_recordedCount), kMaxRecordedChanges);
    XCTAssertGreaterThanOrEqual(count, 3);
    XCTAssertEqual(g_recordedChanges[0], KSHangChangeTypeStarted);
    XCTAssertEqual(countRecorded(KSHangChangeTypeEnded), 1);
    pthread_t mainThread = pthread_self();
    for (int i = 0; i < count; i++) {
        XCTAssertTrue(pthread_equal(g_recordedThreads[i], g_recordedThreads[0]), @"change %d", i);
        XCTAssertFalse(pthread_equal(g_recordedThreads[i], mainThread), @"change %d arrived on the main thread", i);
    }
}

static _Atomic(int) g_startedBeforeTheWrite = -1;

static void stubHandleNotingStarted(KSCrash_MonitorContext *context, KSCrash_ReportResult *result, bool finalize)
{
    atomic_store(&g_startedBeforeTheWrite, countRecorded(KSHangChangeTypeStarted));
    stubHandle(context, result, finalize);
}

- (void)testAHangIsAnnouncedOnlyOnceItsReportIsWritten
{
    // A listener runs arbitrary code. Announcing the hang before the main thread is
    // captured would let the main thread recover meanwhile, and the report would keep
    // a stack from after the hang.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandleNotingStarted);
    atomic_store(&g_startedBeforeTheWrite, -1);
    startRecordingHangChanges();
    KSHangEventCallback previous = kshang_setHangEventCallback(recordHangChange);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue(waitForRecordedChange(KSHangChangeTypeStarted, 5));
    XCTAssertTrue(stopWatchdog());
    kshang_setHangEventCallback(previous);

    XCTAssertEqual(atomic_load(&g_startedBeforeTheWrite), 0, @"Started came before the report was written");
}

#pragma mark - A Hang That Cannot Be Recorded

static bool stubUnwritableRunSidecarPath(__unused const char *monitorId, char *pathBuffer, size_t pathBufferLength)
{
    return strlcpy(pathBuffer, "/nonexistent-kscrash-test-dir/Watchdog.ksscr", pathBufferLength) < pathBufferLength;
}

- (void)testAHangWhoseSidecarCannotBeCreatedFailsWithoutAReport
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandle);
    callbacks.getRunSidecarPath = stubUnwritableRunSidecarPath;
    atomic_store(&g_stubHandleCount, 0);
    startRecordingHangChanges();
    KSHangEventCallback previous = kshang_setHangEventCallback(recordHangChange);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue(waitForRecordedChange(KSHangChangeTypeFailed, 5));
    // A few more thresholds: the failed hang is neither updated nor started again.
    XCTAssertFalse(waitForRecordedChange(KSHangChangeTypeUpdated, 0.8));
    XCTAssertTrue(stopWatchdog());
    kshang_setHangEventCallback(previous);

    XCTAssertEqual(countRecorded(KSHangChangeTypeStarted), 0);
    XCTAssertEqual(countRecorded(KSHangChangeTypeFailed), 1);
    XCTAssertEqual(countRecorded(KSHangChangeTypeEnded), 0, @"Failed ends the hang's events");
    XCTAssertEqual(atomic_load(&g_stubHandleCount), 0, @"no report for a hang that is not followed");
}

- (void)testAHangWhoseReportCannotBeWrittenFailsAndRemovesItsSidecar
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandleWritingNothing);
    startRecordingHangChanges();
    KSHangEventCallback previous = kshang_setHangEventCallback(recordHangChange);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue(waitForRecordedChange(KSHangChangeTypeFailed, 5));
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:g_runSidecarPath]);
    XCTAssertFalse(waitForRecordedChange(KSHangChangeTypeUpdated, 0.8));
    XCTAssertTrue(stopWatchdog());
    kshang_setHangEventCallback(previous);

    XCTAssertEqual(countRecorded(KSHangChangeTypeStarted), 0, @"Started waits for the report");
    XCTAssertEqual(g_recordedChanges[0], KSHangChangeTypeFailed, @"Failed in place of Started");
    XCTAssertEqual(countRecorded(KSHangChangeTypeFailed), 1);
    XCTAssertEqual(countRecorded(KSHangChangeTypeEnded), 0);
}

- (void)testAHangWhoseReportTheAppSkipsIsStillFollowed
{
    // Skipping the report is the app's choice, not a failure to record the hang: the hang
    // keeps its sidecar and its events, without a report.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandleSkippingTheReport);
    startRecordingHangChanges();
    KSHangEventCallback previous = kshang_setHangEventCallback(recordHangChange);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue(waitForRecordedChange(KSHangChangeTypeStarted, 5));
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:g_runSidecarPath]);
    letMainThreadGoIdle();
    XCTAssertTrue(waitForRecordedChange(KSHangChangeTypeEnded, 5));
    XCTAssertTrue(stopWatchdog());
    kshang_setHangEventCallback(previous);

    XCTAssertEqual(countRecorded(KSHangChangeTypeFailed), 0, @"a skipped report is not a failed hang");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:g_runSidecarPath],
                   @"the sidecar goes once the hang has ended");
}

static KSSempahore *g_notifyEntered;
static KSSempahore *g_mainIdleBeforeCapture;
static _Atomic(int) g_reportsAskedFor = -1;

/** Holds the event at the point the threads are suspended until the main thread has gone
 * idle, the way a slow sidecar write lets a short hang end before the capture. */
static KSCrash_MonitorContext *stubNotifyUntilTheMainThreadIsIdle(thread_t thread,
                                                                  KSCrash_ExceptionHandlingRequirements requirements)
{
    memset(&g_stubContext, 0, sizeof(g_stubContext));
    g_stubContext.requirements = requirements;
    [g_notifyEntered signal];
    [g_mainIdleBeforeCapture waitForTimeInterval:5];
    (void)thread;
    return &g_stubContext;
}

/** Writes the report only when the event still asks for one, as the handler does. */
static void stubHandleFollowingThePlan(KSCrash_MonitorContext *context, KSCrash_ReportResult *result, bool finalize)
{
    atomic_store(&g_reportsAskedFor, context->requirements.shouldWriteReport ? 1 : 0);
    if (!context->requirements.shouldWriteReport) {
        stubHandleSkippingTheReport(context, result, finalize);
        return;
    }
    stubHandle(context, result, finalize);
}

- (void)testAHangThatEndsBeforeItsCaptureWritesNoReport
{
    // The main thread is captured only after the sidecar's file work. A hang that ends in
    // between would be reported with a stack from after it, so it goes without a report,
    // and is still followed.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandleFollowingThePlan);
    callbacks.notify = stubNotifyUntilTheMainThreadIsIdle;
    g_notifyEntered = [KSSempahore withValue:0];
    g_mainIdleBeforeCapture = [KSSempahore withValue:0];
    atomic_store(&g_reportsAskedFor, -1);
    startRecordingHangChanges();
    KSHangEventCallback previous = kshang_setHangEventCallback(recordHangChange);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue([g_notifyEntered waitForTimeInterval:5]);
    letMainThreadGoIdle();
    [g_mainIdleBeforeCapture signal];
    XCTAssertTrue(waitForRecordedChange(KSHangChangeTypeEnded, 5));
    XCTAssertTrue(stopWatchdog());
    kshang_setHangEventCallback(previous);
    g_notifyEntered = nil;
    g_mainIdleBeforeCapture = nil;

    XCTAssertEqual(atomic_load(&g_reportsAskedFor), 0, @"a report was asked for a hang that had ended");
    XCTAssertEqual(countRecorded(KSHangChangeTypeStarted), 1);
    XCTAssertEqual(countRecorded(KSHangChangeTypeFailed), 0);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:g_stubReportPath]);
}

extern bool kscm_watchdog_testcode_staleTickStartsHang(bool mainWokeAgain);

- (void)testATimerCallbackThatRacesTheMainThreadGoingIdleStartsNoHang
{
    // A tick that saw the main thread busy, but took the lock after it went
    // idle, would start a hang from that stale enterTime while the previous
    // one may still be finishing against the same run sidecar;
    // after it also woke again, a hang the main thread is not in.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandle);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertFalse(kscm_watchdog_testcode_staleTickStartsHang(false), @"The main thread went idle");
    XCTAssertFalse(kscm_watchdog_testcode_staleTickStartsHang(true), @"The main thread went idle and woke");

    XCTAssertTrue(stopWatchdog());
}

- (void)testAHangThatYieldsStillReportsThatItStarted
{
    // A yielded hang writes no report, but the hang happened. The lifecycle notifications
    // describe the hang, not the report, and the hang is already active by now, so later
    // ticks take the update path and never come back here. Without Started, an observer
    // would see an Updated for a hang it was never told about and an Ended clearing it.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandle);
    atomic_store(&g_stubRefusesReportInFlight, true);
    atomic_store(&g_stubHandleCount, 0);
    g_notifyCalled = [KSSempahore withValue:0];

    KSSempahore *waiter = [KSSempahore withValue:0];
    HangCapture capture = { .waiter = waiter };
    g_hangCapture = &capture;
    KSHangEventCallback previous = kshang_setHangEventCallback(captureHangStart);

    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue([waiter waitForTimeInterval:5], @"A yielded hang must still report that it started");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:g_runSidecarPath],
                  @"A yielded hang is recorded, without a report");
    XCTAssertTrue([g_notifyCalled waitForTimeInterval:5]);
    kshang_setHangEventCallback(previous);
    g_hangCapture = NULL;
    atomic_store(&g_stubRefusesReportInFlight, false);

    XCTAssertGreaterThan(capture.start, 0ULL);
    XCTAssertEqual(atomic_load(&g_stubHandleCount), 0, @"A refused event must never reach the handler");

    XCTAssertTrue(stopWatchdog());
    g_notifyCalled = nil;
}

- (void)testHangEventNamesNoOffendingThread
{
    // The main thread is this report's subject, but it did not fault, it was observed.
    // Naming it would let the recrash check match it against a live handler slot, and a
    // hung main thread is very often hung because it is writing another report; the event
    // would then be classed a recrash and rewrite that report's file in place. Passing
    // MACH_PORT_NULL is what keeps an observed subject out of that check.
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandle);
    g_stubNotifyThread = (thread_t)~0u;
    g_notifyCalled = [KSSempahore withValue:0];
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    XCTAssertTrue([g_notifyCalled waitForTimeInterval:5]);

    XCTAssertNotEqual(g_stubNotifyThread, (thread_t)~0u, @"the watchdog should have raised an event");
    XCTAssertEqual(g_stubNotifyThread, (thread_t)MACH_PORT_NULL,
                   @"an observed subject must not be named as the offending thread");

    XCTAssertTrue(stopWatchdog());
    g_notifyCalled = nil;
}

extern void ksapp_testcode_publishTransitionState(KSCrashAppTransitionState state);
extern void ksapp_testcode_setHasBeenActive(bool hasBeenActive);

/** Gives the app `state` for this test, and puts the real one back when it ends. */
- (void)useAppState:(KSCrashAppTransitionState)state hasBeenActive:(bool)hasBeenActive
{
    KSCrashAppTransitionState realState = ksapp_currentTransitionState();
    bool realHasBeenActive = ksapp_hasBeenActive();
    [self addTeardownBlock:^{
        ksapp_testcode_publishTransitionState(realState);
        ksapp_testcode_setHasBeenActive(realHasBeenActive);
    }];
    ksapp_testcode_publishTransitionState(state);
    ksapp_testcode_setHasBeenActive(hasBeenActive);
}

/** The sidecar of the hang the watchdog starts once enabled, read once it has started. */
static KSHangSidecar sidecarOfTheHangStartedOnEnable(void)
{
    KSSempahore *waiter = [KSSempahore withValue:0];
    HangCapture capture = { .waiter = waiter };
    g_hangCapture = &capture;
    KSHangEventCallback previous = kshang_setHangEventCallback(captureHangStart);
    BOOL started = [waiter waitForTimeInterval:5];
    kshang_setHangEventCallback(previous);
    g_hangCapture = NULL;
    return started ? sidecarOnDisk() : (KSHangSidecar) { 0 };
}

- (void)testAHangThatMakesTheAppActiveStartedDuringStartup
{
    // The main thread wakes before the app is first active, makes it active and keeps
    // working past the threshold in the same turn, as a slow first DidBecomeActive does.
    // The hang started during startup, in the state the app was in when it started.
    [self useAppState:KSCrashAppTransitionStateLaunching hasBeenActive:false];
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandle);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);
    ksapp_testcode_publishTransitionState(KSCrashAppTransitionStateActive);

    KSHangSidecar sidecar = sidecarOfTheHangStartedOnEnable();
    XCTAssertEqual(sidecar.magic, KSHANG_SIDECAR_MAGIC);
    XCTAssertTrue(sidecar.duringStartup);
    XCTAssertEqual(sidecar.startTransitionState, KSCrashAppTransitionStateLaunching);
}

- (void)testAHangInAnAppAlreadyActiveIsNotDuringStartup
{
    [self useAppState:KSCrashAppTransitionStateActive hasBeenActive:true];
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandle);
    api->init(&callbacks, NULL);
    api->setEnabled(true, NULL);

    KSHangSidecar sidecar = sidecarOfTheHangStartedOnEnable();
    XCTAssertEqual(sidecar.magic, KSHANG_SIDECAR_MAGIC);
    XCTAssertFalse(sidecar.duringStartup);
    XCTAssertEqual(sidecar.startTransitionState, KSCrashAppTransitionStateActive);
}

- (void)testHangStartTimestampIsReasonable
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    KSCrash_ExceptionHandlerCallbacks callbacks = callbacksWithHandle(stubHandle);
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

    XCTAssertTrue(stopWatchdog());
}

- (void)testHangChangeTypeValues
{
    // Verify the enum values are as expected
    XCTAssertEqual(KSHangChangeTypeNone, 0);
    XCTAssertEqual(KSHangChangeTypeStarted, 1);
    XCTAssertEqual(KSHangChangeTypeUpdated, 2);
    XCTAssertEqual(KSHangChangeTypeEnded, 3);
    XCTAssertEqual(KSHangChangeTypeFailed, 4);
}

#pragma mark - Enable/Disable Tests

- (void)testInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    XCTAssertTrue(stopWatchdog());
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testDoubleInstallAndRemove
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    XCTAssertTrue(stopWatchdog());
    XCTAssertFalse(api->isEnabled(NULL));
    XCTAssertTrue(stopWatchdog());
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testReenableAfterDisable
{
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    XCTAssertTrue(stopWatchdog());
    XCTAssertFalse(api->isEnabled(NULL));

    api->setEnabled(true, NULL);
    XCTAssertTrue(api->isEnabled(NULL));
    XCTAssertTrue(stopWatchdog());
    XCTAssertFalse(api->isEnabled(NULL));
}

- (void)testCleanEnableDisable
{
    // Enable and disable multiple times to verify clean lifecycle
    KSCrashMonitorAPI *api = kscm_watchdog_getAPI();
    for (int i = 0; i < 5; i++) {
        api->setEnabled(true, NULL);
        XCTAssertTrue(api->isEnabled(NULL));
        [NSThread sleepForTimeInterval:0.1];
        XCTAssertTrue(stopWatchdog());
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
        XCTAssertTrue(stopWatchdog());
        XCTAssertFalse(api->isEnabled(NULL));
    }
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

@end
