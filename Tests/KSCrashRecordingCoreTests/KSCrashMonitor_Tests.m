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

- (bool)isAnyThreadRunning:(NSArray<NSThread *> *)threads
{
    for (NSThread *thread in threads) {
        if (!thread.isFinished && !thread.isCancelled) {
            return true;
        }
    }
    return false;
}

- (NSTimeInterval)waitForThreads:(NSArray<NSThread *> *)threads maxTime:(NSTimeInterval)maxTime
{
    NSDate *startTime = [NSDate date];
    usleep(1);
    NSTimeInterval duration = 0;
    while ([self isAnyThreadRunning:threads]) {
        duration = [[NSDate date] timeIntervalSinceDate:startTime];
        if (duration > maxTime) {
            break;
        }
        usleep(100);
    }
    return duration;
}

- (void)cancelThreads:(NSArray<NSThread *> *)threads
{
    for (NSThread *thread in threads) {
        if (!thread.isFinished && !thread.isCancelled) {
            [thread cancel];
        }
    }
}

- (NSThread *)startThreadWithBlock:(void (^)(void))block
{
    NSThread *thread = [[NSThread alloc] initWithBlock:block];
    [thread start];
    return thread;
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

static int g_counter = 0;

- (bool)isCounterThreadRunning
{
    int counter = g_counter;
    usleep(1);
    return g_counter != counter;
}

#if KSCRASH_HAS_THREADS_API
- (void)testThreadsStoppedToCaptureTraces
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    KSCrash_MonitorContext *ctx = NULL;

    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        for (;;) {
            g_counter++;
            usleep(1);
        }
    }];
    [thread start];
    usleep(1);
    ctx = dummyExceptionHandlerCallbacks.notify(
        (thread_t)ksthread_self(),
        (KSCrash_ExceptionHandlingRequirements) { .shouldRecordAllThreads = true, .shouldWriteReport = true });
    XCTAssertFalse(ctx->requirements.isFatal);
    XCTAssertTrue(ctx->requirements.asyncSafetyBecauseThreadsSuspended,
                  @"asyncSafetyBecauseThreadsSuspended should be set when shouldRecordThreads is true");
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertTrue(ctx->requirements.shouldRecordAllThreads);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);

    XCTAssertFalse([self isCounterThreadRunning]);
    dummyExceptionHandlerCallbacks.handle(ctx);
    // Unfortunately, resumed threads don't always start up immediately, leading to flakes :/
    // XCTAssertTrue([self isCounterThreadRunning]);
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
    // Unrelated exceptions after a non-fatal exception should process normally.

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

    NSMutableArray *threads = [NSMutableArray new];

    [threads removeAllObjects];
    [threads addObject:[self startThreadWithBlock:^{
                 ctx = dummyExceptionHandlerCallbacks.notify(
                     (thread_t)ksthread_self(),
                     (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .shouldWriteReport = true });
             }]];
    XCTAssertLessThan([self waitForThreads:threads maxTime:0.5], 0.1,
                      "Unrelated exceptions following a non-fatal exception should not be delayed");
    [self cancelThreads:threads];
    XCTAssertFalse(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);

    [threads removeAllObjects];
    [threads addObject:[self startThreadWithBlock:^{
                 ctx = dummyExceptionHandlerCallbacks.notify(
                     (thread_t)ksthread_self(),
                     (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
             }]];
    XCTAssertLessThan([self waitForThreads:threads maxTime:0.5], 0.1,
                      "Unrelated exceptions following a non-fatal exception should not be delayed");
    [self cancelThreads:threads];
    XCTAssertTrue(ctx->requirements.isFatal);
    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
    XCTAssertFalse(ctx->requirements.asyncSafety);
    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);
}

- (void)testSimultaneousUnrelatedExceptionsFatalFirst
{
    // Unrelated exceptions after a fatal exception should be delayed.

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

    NSMutableArray *threads = [NSMutableArray new];

    [threads removeAllObjects];
    [threads addObject:[self startThreadWithBlock:^{
                 ctx = dummyExceptionHandlerCallbacks.notify(
                     (thread_t)ksthread_self(),
                     (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .shouldWriteReport = true });
             }]];
    XCTAssertGreaterThan([self waitForThreads:threads maxTime:0.5], 0.49,
                         "Unrelated exceptions following a fatal exception should be delayed");
    [self cancelThreads:threads];
    // Since we gave up waiting, ctx won't have been updated.

    [threads removeAllObjects];
    [threads addObject:[self startThreadWithBlock:^{
                 ctx = dummyExceptionHandlerCallbacks.notify(
                     (thread_t)ksthread_self(),
                     (KSCrash_ExceptionHandlingRequirements) { .isFatal = true, .shouldWriteReport = true });
             }]];
    XCTAssertGreaterThan([self waitForThreads:threads maxTime:0.5], 0.49,
                         "Unrelated exceptions following a fatal exception should be delayed");
    [self cancelThreads:threads];
    // Since we gave up waiting, ctx won't have been updated.
}

// TODO: This test is super flaky
//- (void)testOverloadThreadHandlerNonFatal
//{
//    // If too many unrelated exceptions occur simultaneously, the handler should be uninstalled and the exceptions
//    // ignored.
//
//    kscm_addMonitor(&g_dummyMonitor);
//    kscm_activateMonitors();
//    __block KSCrash_MonitorContext *ctx = NULL;
//
//    ctx = dummyExceptionHandlerCallbacks.notify((thread_t)ksthread_self(), (KSCrash_ExceptionHandlingPolicy) {
//                                                                               .isFatal = false,
//                                                                           });
//    XCTAssertFalse(ctx->requirements.isFatal);
//    XCTAssertFalse(ctx->requirements.crashedDuringExceptionHandling);
//    XCTAssertFalse(ctx->requirements.requiresAsyncSafety);
//    XCTAssertFalse(ctx->requirements.shouldExitImmediately);
//    XCTAssertFalse(ctx->requirements.shouldRecordAllThreads);
//
//    NSMutableArray *threads = [NSMutableArray new];
//
//    for (int i = 0; i < 1000; i++) {
//        [threads addObject:[self startThreadWithBlock:^{
//                     if (g_dummyEnabledState) {
//                         ctx = dummyExceptionHandlerCallbacks.notify((thread_t)ksthread_self(),
//                                                                     (KSCrash_ExceptionHandlingPolicy) {
//                                                                         .isFatal = false,
//                                                                     });
//                     }
//                 }]];
//    }
//    [self waitForThreads:threads maxTime:0.5];
//    [self cancelThreads:threads];
//    XCTAssertFalse(g_dummyEnabledState);
//    XCTAssertTrue(ctx->requirements.shouldExitImmediately);
//}

- (void)testOverloadThreadHandlerFatal
{
    // If too many unrelated exceptions occur simultaneously, the handler should be uninstalled and the exceptions
    // ignored.

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

    NSMutableArray *threads = [NSMutableArray new];

    for (int i = 0; i < 1000; i++) {
        [threads addObject:[self startThreadWithBlock:^{
                     ctx = dummyExceptionHandlerCallbacks.notify(
                         (thread_t)ksthread_self(),
                         (KSCrash_ExceptionHandlingRequirements) { .isFatal = false, .shouldWriteReport = true });
                 }]];
    }
    [self waitForThreads:threads maxTime:0.5];
    [self cancelThreads:threads];
    XCTAssertFalse(g_dummyEnabledState);
    XCTAssertTrue(ctx->requirements.shouldExitImmediately);
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
