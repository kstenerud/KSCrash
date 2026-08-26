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

#import "KSCrashHang.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Watchdog.h"

// Stub callbacks for testing hang detection
static KSCrash_MonitorContext g_stubContext;

static KSCrash_MonitorContext *stubNotify(__unused thread_t thread,
                                          __unused KSCrash_ExceptionHandlingRequirements requirements)
{
    memset(&g_stubContext, 0, sizeof(g_stubContext));
    return &g_stubContext;
}

static void stubHandle(__unused KSCrash_MonitorContext *context, KSCrash_ReportResult *result, __unused bool finalize)
{
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
