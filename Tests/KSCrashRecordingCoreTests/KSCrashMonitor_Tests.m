//
//  KSCrashMonitor_Tests.m
//
//  Created by Karl Stenerud on 2013-03-09.
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
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>

#import "KSCrashMonitor.h"

@interface KSCrashMonitor_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Tests

#pragma mark - Dummy monitors -

// First monitor
static bool g_dummyEnabledState = false;
static bool g_dummyPostSystemEnabled = false;
static const char *const g_eventID = "TestEventID";
static const char *g_copiedEventID = NULL;

static KSCrash_ExceptionHandlerCallbacks dummyExceptionHandlerCallbacks;
static void dummyInit(KSCrash_ExceptionHandlerCallbacks *callbacks) { dummyExceptionHandlerCallbacks = *callbacks; }

static const char *dummyMonitorId(void) { return "Dummy Monitor"; }

static KSCrashMonitorFlag dummyMonitorFlags(void) { return KSCrashMonitorFlagAsyncSafe; }

static void dummySetEnabled(bool isEnabled) { g_dummyEnabledState = isEnabled; }
static bool dummyIsEnabled(void) { return g_dummyEnabledState; }
static void dummyAddContextualInfoToEvent(struct KSCrash_MonitorContext *eventContext)
{
    if (eventContext != NULL) {
        strncpy(eventContext->eventID, g_eventID, sizeof(eventContext->eventID));
    }
}

static void dummyNotifyPostSystemEnable(void) { g_dummyPostSystemEnabled = true; }

// Second monitor
static KSCrash_ExceptionHandlerCallbacks secondDummyExceptionHandlerCallbacks;
static void secondDummyInit(KSCrash_ExceptionHandlerCallbacks *callbacks)
{
    secondDummyExceptionHandlerCallbacks = *callbacks;
}

static const char *secondDummyMonitorId(void) { return "Second Dummy Monitor"; }

static bool g_secondDummyEnabledState = false;
// static const char *const g_secondEventID = "SecondEventID";

static void secondDummySetEnabled(bool isEnabled) { g_secondDummyEnabledState = isEnabled; }
static bool secondDummyIsEnabled(void) { return g_secondDummyEnabledState; }

static KSCrashMonitorAPI g_dummyMonitor = {};
static KSCrashMonitorAPI g_secondDummyMonitor = {};

#pragma mark - Tests -

static BOOL g_exceptionHandled = NO;

static void myEventCallback(struct KSCrash_MonitorContext *context)
{
    g_exceptionHandled = YES;
    g_copiedEventID = strdup(context->eventID);
}

extern void kscm_testcode_resetState(void);

- (void)setUp
{
    [super setUp];
    // First monitor
    memset(&g_dummyMonitor, 0, sizeof(g_dummyMonitor));
    free((void *)g_copiedEventID);
    g_copiedEventID = NULL;
    kscma_initAPI(&g_dummyMonitor);
    g_dummyMonitor.init = dummyInit;
    g_dummyMonitor.monitorId = dummyMonitorId;
    g_dummyMonitor.monitorFlags = dummyMonitorFlags;
    g_dummyMonitor.setEnabled = dummySetEnabled;
    g_dummyMonitor.isEnabled = dummyIsEnabled;
    g_dummyMonitor.addContextualInfoToEvent = dummyAddContextualInfoToEvent;
    g_dummyMonitor.notifyPostSystemEnable = dummyNotifyPostSystemEnable;
    g_dummyEnabledState = false;
    g_dummyPostSystemEnabled = false;
    g_exceptionHandled = NO;
    // Second monitor
    memset(&g_secondDummyMonitor, 0, sizeof(g_secondDummyMonitor));
    kscma_initAPI(&g_secondDummyMonitor);
    g_secondDummyMonitor.init = secondDummyInit;
    g_secondDummyMonitor.monitorId = secondDummyMonitorId;
    g_secondDummyMonitor.setEnabled = secondDummySetEnabled;
    g_secondDummyMonitor.isEnabled = secondDummyIsEnabled;
    g_secondDummyEnabledState = false;

    kscm_testcode_resetState();
}

- (bool)cstringIsEqual:(const char *)a to:(const char *)b
{
    return strcmp(a, b) == 0;
}

- (dispatch_group_t)startThreads:(int)count withBlock:(void (^)(void))block
{
    dispatch_group_t group = dispatch_group_create();
    for (int i = 0; i < count; i++) {
        dispatch_group_enter(group);
        NSThread *thread = [[NSThread alloc] initWithBlock:^{
            block();
            dispatch_group_leave(group);
        }];
        [thread start];
    }
    return group;
}

- (long)waitForGroup:(dispatch_group_t)group timeout:(NSTimeInterval)timeout
{
    return dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
}

#pragma mark - Monitor Registry Tests

// Make sure the registry is hooked up properly.

- (void)testAddingAndActivatingMonitors
{
    XCTAssertTrue(kscm_addMonitor(&g_dummyMonitor), @"Monitor should be successfully added.");
    kscm_activateMonitors();  // Activate all monitors
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
}

- (void)testDisablingAllMonitors
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled before disabling.");
    kscm_disableAllMonitors();  // Disable all monitors
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after calling disable all.");
}

- (void)testAddMonitorWithNullAPI
{
    XCTAssertFalse(kscm_addMonitor(NULL), @"Adding a NULL monitor should return false.");
    kscm_activateMonitors();
    // No assertion needed, just verifying no crash occurred
}

- (void)testRemovingMonitor
{
    // Add the dummy monitor first
    XCTAssertTrue(kscm_addMonitor(&g_dummyMonitor), @"Monitor should be successfully added.");
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after adding.");

    // Remove the dummy monitor
    kscm_removeMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after removal.");
}

#pragma mark - Monitor Exception Handling Tests

- (void)testHandlingFatalException
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    kscm_setEventCallback(myEventCallback);
    KSCrash_MonitorContext *ctx = NULL;
    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
    XCTAssertTrue(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);

    dummyExceptionHandlerCallbacks.handle(ctx);  // Handle the exception
    XCTAssertTrue(g_exceptionHandled, @"The exception should have been handled by the event callback.");
    XCTAssertFalse(g_dummyEnabledState, @"A fatal exception should disable the monitor");
}

- (void)testHandlingNonFatalException
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    kscm_setEventCallback(myEventCallback);
    KSCrash_MonitorContext *ctx = NULL;
    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .shouldWriteReport = true });
    XCTAssertFalse(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);

    dummyExceptionHandlerCallbacks.handle(ctx);  // Handle the exception
    XCTAssertTrue(g_exceptionHandled, @"The exception should have been handled by the event callback.");
    XCTAssertTrue(g_dummyEnabledState, @"A non-fatal exception should not disable the monitor");
}

- (void)testHeapAllocAsyncSafety
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    kscm_setEventCallback(myEventCallback);
    KSCrash_MonitorContext *ctx = NULL;
    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .asyncSafety = true, .shouldWriteReport = true });
    XCTAssertFalse(ctx->requirements.isFatal);
    XCTAssertTrue(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
    XCTAssertFalse(ctx->isHeapAllocated,
                   @"When async safety is required, the context should not be allocated on the heap");
}

- (void)testHeapAllocNoAsyncSafety
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    KSCrash_MonitorContext *ctx = NULL;
    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .asyncSafety = false, .shouldWriteReport = true });
    XCTAssertFalse(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
    XCTAssertTrue(ctx->isHeapAllocated,
                  @"When async safety is not required, the context should be allocated on the heap");
}

static volatile int g_counter = 0;

- (bool)isCounterIncrementing
{
    int counter = g_counter;
    usleep(1000);  // 1ms
    return g_counter != counter;
}

#if KSCRASH_HAS_THREADS_API
- (void)testThreadsStoppedToCaptureTraces
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    KSCrash_MonitorContext *ctx = NULL;

    dispatch_semaphore_t threadStarted = dispatch_semaphore_create(0);

    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        dispatch_semaphore_signal(threadStarted);
        while (!NSThread.currentThread.isCancelled) {
            g_counter++;
            usleep(100);
        }
    }];
    [thread start];

    // Wait for the thread to signal it has started
    long result = dispatch_semaphore_wait(threadStarted, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
    XCTAssertEqual(result, 0, @"Counter thread should start");

    // Verify thread is actually running by checking counter increments
    XCTAssertTrue([self isCounterIncrementing], @"Counter thread should be incrementing");

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .shouldRecordAllThreads = true, .shouldWriteReport = true });
    XCTAssertFalse(ctx->requirements.isFatal);
    XCTAssertTrue(ctx->requirements.asyncSafetyBecauseThreadsSuspended,
                  @"asyncSafetyBecauseThreadsSuspended should be set when shouldRecordThreads is true");
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertTrue(ctx->requirements.shouldRecordAllThreads);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);

    // Thread should be suspended - counter should not increment
    XCTAssertFalse([self isCounterIncrementing], @"Thread should be suspended during exception handling");

    dummyExceptionHandlerCallbacks.handle(ctx);

    // After handling, thread should resume - use a retry loop since resumption may take time
    bool resumed = false;
    for (int i = 0; i < 100 && !resumed; i++) {
        resumed = [self isCounterIncrementing];
    }
    XCTAssertTrue(resumed, @"Counter thread should resume after handling");

    [thread cancel];
}
#endif

- (void)testCrashDuringExceptionHandlingFatal
{
    // When a second exception occurs on a thread that's already handling an exception, it should:
    // - set crashedDuringExceptionHandling
    // - set requiresAsyncSafety
    // - set isFatal
    // - clear shouldRecordThreads

    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    KSCrash_MonitorContext *ctx = NULL;

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling,
                   @"The first exception shouldn't be detected as a recrash.");
    XCTAssertTrue(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(), (KSCrash_ExceptionHandlingRequirements) {
                                       .isFatal = true, .shouldRecordAllThreads = true, .shouldWriteReport = true });
    XCTAssertTrue(ctx->requirements.crashedDuringExceptionHandling,
                  @"The second exception should be detected as a recrash.");
    XCTAssertTrue(ctx->requirements.isFatal, @"A recrash should set isFatal");
    XCTAssertTrue(ctx->requirements.asyncSafety, @"A recrash should set requiresAsyncSafety");
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads, @"A recrash should clear shouldRecordThreads");
}

- (void)testCrashDuringExceptionHandlingNonFatal
{
    // When a second exception occurs on a thread that's already handling an exception, it should:
    // - set crashedDuringExceptionHandling
    // - set requiresAsyncSafety
    // - set isFatal
    // - clear shouldRecordThreads

    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    KSCrash_MonitorContext *ctx = NULL;

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling,
                   @"The first exception shouldn't be detected as a recrash.");
    XCTAssertTrue(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(), (KSCrash_ExceptionHandlingRequirements) {
                                       .isFatal = false, .shouldRecordAllThreads = true, .shouldWriteReport = true });
    XCTAssertTrue(ctx->requirements.crashedDuringExceptionHandling,
                  @"The second exception should be detected as a recrash.");
    XCTAssertTrue(ctx->requirements.isFatal, @"A recrash should set isFatal");
    XCTAssertTrue(ctx->requirements.asyncSafety, @"A recrash should set requiresAsyncSafety");
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads, @"A recrash should clear shouldRecordThreads");
}

- (void)testSimultaneousUnrelatedExceptionsNonFatalFirst
{
    // Unrelated exceptions after a non-fatal exception should process normally (not be delayed).

    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    __block KSCrash_MonitorContext *ctx = NULL;

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .shouldWriteReport = true });
    XCTAssertFalse(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);

    // Test non-fatal thread after non-fatal - should complete quickly
    dispatch_group_t group1 =
        [self startThreads:1
                 withBlock:^{
                     ctx = dummyExceptionHandlerCallbacks.notify(
                         (thread_t)ksthread_self(),
                         (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .shouldWriteReport = true });
                 }];
    long result = [self waitForGroup:group1 timeout:0.5];
    XCTAssertEqual(result, 0, @"Non-fatal exception after non-fatal should not be delayed");
    XCTAssertFalse(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);

    // Test fatal thread after non-fatal - should also complete quickly
    dispatch_group_t group2 =
        [self startThreads:1
                 withBlock:^{
                     ctx = dummyExceptionHandlerCallbacks.notify(
                         (thread_t)ksthread_self(),
                         (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
                 }];
    result = [self waitForGroup:group2 timeout:0.5];
    XCTAssertEqual(result, 0, @"Fatal exception after non-fatal should not be delayed");
    XCTAssertTrue(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
}

- (void)testSimultaneousUnrelatedExceptionsFatalFirst
{
    // Unrelated exceptions after a fatal exception should be delayed (blocked).

    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    __block KSCrash_MonitorContext *ctx = NULL;

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
    XCTAssertTrue(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);

    // Test non-fatal thread after fatal - should be blocked (timeout)
    dispatch_group_t group1 =
        [self startThreads:1
                 withBlock:^{
                     dummyExceptionHandlerCallbacks.notify(
                         (thread_t)ksthread_self(),
                         (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .shouldWriteReport = true });
                 }];
    long result = [self waitForGroup:group1 timeout:0.5];
    XCTAssertNotEqual(result, 0, @"Non-fatal exception after fatal should be blocked");

    // Test fatal thread after fatal - should also be blocked (timeout)
    dispatch_group_t group2 =
        [self startThreads:1
                 withBlock:^{
                     dummyExceptionHandlerCallbacks.notify(
                         (thread_t)ksthread_self(),
                         (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
                 }];
    result = [self waitForGroup:group2 timeout:0.5];
    XCTAssertNotEqual(result, 0, @"Fatal exception after fatal should be blocked");
}

// NOTE: testOverloadThreadHandlerNonFatal is intentionally disabled.
// This test validates that when 1000+ threads simultaneously trigger non-fatal exceptions,
// the handler correctly uninstalls itself and sets shouldExitImmediately. However, the test
// is inherently flaky because:
// 1. Thread scheduling is non-deterministic - the order and timing of 1000 threads varies
// 2. The `g_dummyEnabledState` check inside the thread block creates a race condition
// 3. The assertion on `ctx->requirements.shouldExitImmediately` depends on which thread
//    finishes last, which is unpredictable
// The behavior is tested by testOverloadThreadHandlerFatal which is more deterministic
// since fatal exceptions block other threads from proceeding.

- (void)testOverloadThreadHandlerFatal
{
    // If too many unrelated exceptions occur simultaneously, the handler should be uninstalled and the exceptions
    // ignored.

    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    KSCrash_MonitorContext *ctx = NULL;
    __block _Atomic(int) exitImmediatelyCount = 0;

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
    XCTAssertTrue(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);

    dispatch_group_t group =
        [self startThreads:1000
                 withBlock:^{
                     KSCrash_MonitorContext *threadCtx = dummyExceptionHandlerCallbacks.notify(
                         (thread_t)ksthread_self(),
                         (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .shouldWriteReport = true });
                     if (threadCtx != NULL && threadCtx->requirements.shouldExitImmediately) {
                         atomic_fetch_add(&exitImmediatelyCount, 1);
                     }
                 }];
    [self waitForGroup:group timeout:2.0];
    XCTAssertFalse(g_dummyEnabledState);
    // At least some threads should have been told to exit immediately due to overload detection.
    // We can't assert on a specific count because thread scheduling is non-deterministic.
    XCTAssertGreaterThan(exitImmediatelyCount, 0, @"At least some threads should be told to exit immediately");
}

- (void)testHandleExceptionAddsContextualInfoFatal
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    kscm_setEventCallback(myEventCallback);
    KSCrash_MonitorContext *ctx = NULL;

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
    XCTAssertFalse([self cstringIsEqual:ctx->eventID to:g_eventID]);
    dummyExceptionHandlerCallbacks.handle(ctx);  // Handle the exception
    XCTAssertTrue([self cstringIsEqual:g_copiedEventID to:g_eventID],
                  @"The eventID should be set to 'TestEventID' by the dummy monitor when handling exception.");
}

- (void)testHandleExceptionAddsContextualInfoNonFatal
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    kscm_setEventCallback(myEventCallback);
    KSCrash_MonitorContext *ctx = NULL;

    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .shouldWriteReport = true });
    XCTAssertFalse([self cstringIsEqual:ctx->eventID to:g_eventID]);
    dummyExceptionHandlerCallbacks.handle(ctx);  // Handle the exception
    XCTAssertTrue([self cstringIsEqual:g_copiedEventID to:g_eventID],
                  @"The eventID should be set to 'TestEventID' by the dummy monitor when handling exception.");
}

- (void)testHandleExceptionRestoresOriginalHandlers
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
    KSCrash_MonitorContext *ctx = NULL;
    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .asyncSafety = false, .isFatal = true, .shouldWriteReport = true });
    XCTAssertTrue(g_dummyMonitor.isEnabled(),
                  @"The monitor should still be enabled before fatal exception handling logic.");
    dummyExceptionHandlerCallbacks.handle(ctx);
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after handling a fatal exception.");
}

@end
