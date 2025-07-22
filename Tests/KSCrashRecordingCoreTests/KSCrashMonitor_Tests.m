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

static KSCrash_ExceptionHandlerCallbacks dummyExceptionHandlerCallbacks;
static void dummyInit(KSCrash_ExceptionHandlerCallbacks *callbacks) { dummyExceptionHandlerCallbacks = *callbacks; }

static const char *dummyMonitorId(void) { return "Dummy Monitor"; }
static const char *newMonitorId(void) { return "New Monitor"; }

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

static void myEventCallback(__unused struct KSCrash_MonitorContext *context) { g_exceptionHandled = YES; }

extern void kscm_resetState(void);

- (void)setUp
{
    [super setUp];
    // First monitor
    memset(&g_dummyMonitor, 0, sizeof(g_dummyMonitor));
    kscm_initAPI(&g_dummyMonitor);
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
    kscm_initAPI(&g_secondDummyMonitor);
    g_secondDummyMonitor.init = secondDummyInit;
    g_secondDummyMonitor.monitorId = secondDummyMonitorId;
    g_secondDummyMonitor.setEnabled = secondDummySetEnabled;
    g_secondDummyMonitor.isEnabled = secondDummyIsEnabled;
    g_secondDummyEnabledState = false;

    kscm_resetState();
}

#pragma mark - Monitor Activation Tests

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

- (void)testActivateMonitorsReturnsTrue
{
    XCTAssertTrue(kscm_addMonitor(&g_dummyMonitor), @"Monitor should be successfully added.");
    XCTAssertTrue(kscm_activateMonitors(),
                  @"activateMonitors should return true when at least one monitor is activated.");
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
}

- (void)testActivateMonitorsReturnsFalseWhenNoMonitorsActive
{
    // Don't add any monitors
    XCTAssertFalse(kscm_activateMonitors(), @"activateMonitors should return false when no monitors are active.");
}

- (void)testActivateMonitorsReturnsFalseWhenAllMonitorsDisabled
{
    KSCrashMonitorAPI alwaysDisabledMonitor = g_dummyMonitor;
    alwaysDisabledMonitor.setEnabled = (void (*)(bool))imp_implementationWithBlock(^(__unused bool isEnabled) {
        // pass
    });
    alwaysDisabledMonitor.isEnabled = (bool (*)(void))imp_implementationWithBlock(^{
        return false;
    });

    XCTAssertTrue(kscm_addMonitor(&alwaysDisabledMonitor), @"Monitor should be successfully added.");
    XCTAssertFalse(kscm_activateMonitors(), @"activateMonitors should return false when all monitors are disabled.");
}

#pragma mark - Monitor API Null Checks

- (void)testAddMonitorWithNullAPI
{
    XCTAssertFalse(kscm_addMonitor(NULL), @"Adding a NULL monitor should return false.");
    kscm_activateMonitors();
    // No assertion needed, just verifying no crash occurred
}

#pragma mark - Monitor Exception Handling Tests

- (void)testHandlingCrashEvent
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    kscm_setEventCallback(myEventCallback);  // Set the event callback
    struct KSCrash_MonitorContext context = { 0 };
    dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
        .asyncSafety = false,
        .isFatal = true,
    });
    dummyExceptionHandlerCallbacks.handle(&context);  // Handle the exception
    XCTAssertTrue(g_exceptionHandled, @"The exception should have been handled by the event callback.");
}

- (void)testCrashDuringExceptionHandling
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();

    // Test detection of crash during exception handling
    XCTAssertFalse(dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
                       .asyncSafety = false,
                       .isFatal = true,
                   }),
                   @"First call should not detect crash during exception handling.");

    XCTAssertTrue(dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
                      .asyncSafety = false,
                      .isFatal = true,
                  }),
                  @"It should detect a crash during exception handling on the second call.");

    XCTAssertTrue(dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
                      .asyncSafety = false,
                      .isFatal = true,
                  }),
                  @"It should continue to detect a crash during exception handling.");
}

- (void)testHandleExceptionAddsContextualInfo
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    struct KSCrash_MonitorContext context = { 0 };
    memset(context.eventID, 0, sizeof(context.eventID));  // Initialize with a known value
    dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
        .asyncSafety = false,
        .isFatal = false,
    });
    dummyExceptionHandlerCallbacks.handle(&context);  // Handle the exception
    XCTAssertEqual(strcmp(context.eventID, g_eventID), 0,
                   @"The eventID should be set to 'TestEventID' by the dummy monitor when handling exception.");
}

- (void)testHandleExceptionRestoresOriginalHandlers
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
    struct KSCrash_MonitorContext context = { 0 };
    dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
        .asyncSafety = false,
        .isFatal = true,
    });
    XCTAssertTrue(g_dummyMonitor.isEnabled(),
                  @"The monitor should still be enabled before fatal exception handling logic.");
    dummyExceptionHandlerCallbacks.handle(&context);
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after handling a fatal exception.");
}

- (void)testHandleExceptionCrashedDuringExceptionHandling
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
    struct KSCrash_MonitorContext context = { 0 };
    context.crashedDuringCrashHandling = false;  // Initial state should be false
    dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
        // Set g_handlingFatalException to true
        .asyncSafety = false,
        .isFatal = true,
    });
    dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
        // Set g_crashedDuringExceptionHandling to true
        .asyncSafety = false,
        .isFatal = true,
    });
    dummyExceptionHandlerCallbacks.handle(&context);  // Handle the exception
    XCTAssertTrue(
        context.crashedDuringCrashHandling,
        @"The context's crashedDuringCrashHandling should be true when g_crashedDuringExceptionHandling is true.");
}

- (void)testExceptionHandlingWithNonFatalMonitor
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");

    struct KSCrash_MonitorContext context = { 0 };
    context.monitorFlags = 0;  // Indicate that the exception is non-fatal
    dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
        .asyncSafety = false,
        .isFatal = false,
    });
    dummyExceptionHandlerCallbacks.handle(&context);

    XCTAssertTrue(g_dummyMonitor.isEnabled(),
                  @"The monitor should remain enabled after handling a non-fatal exception.");
}

- (void)testEventCallbackWithNonFatalException
{
    kscm_setEventCallback(myEventCallback);
    struct KSCrash_MonitorContext context = { 0 };
    context.monitorFlags = 0;  // Indicate non-fatal exception
    dummyExceptionHandlerCallbacks.notify((KSCrash_ExceptionHandlingPolicy) {
        .asyncSafety = false,
        .isFatal = false,
    });
    dummyExceptionHandlerCallbacks.handle(&context);
    XCTAssertTrue(g_exceptionHandled, @"The event callback should handle the non-fatal exception.");
}

#pragma mark - Monitor Removal Tests

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

- (void)testRemoveMonitorNotAdded
{
    KSCrashMonitorAPI newMonitor = g_dummyMonitor;
    newMonitor.monitorId = newMonitorId;  // Set monitorId as a function pointer

    kscm_removeMonitor(&newMonitor);  // Remove without adding
    kscm_activateMonitors();

    // Verify that no crash occurred and the state remains unchanged
    XCTAssertFalse(newMonitor.isEnabled ? newMonitor.isEnabled() : NO,
                   @"The new monitor should not be enabled, as it was never added.");
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The dummy monitor should still be disabled as it's not related.");
}

- (void)testRemoveMonitorTwice
{
    // Add and then remove the dummy monitor
    XCTAssertTrue(kscm_addMonitor(&g_dummyMonitor), @"Monitor should be successfully added.");
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after adding.");

    kscm_removeMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after the first removal.");

    // Try to remove the dummy monitor again
    kscm_removeMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should remain disabled after a second removal attempt.");
}

- (void)testRemoveMonitorAndReAdd
{
    // Add, remove, and then re-add the dummy monitor
    XCTAssertTrue(kscm_addMonitor(&g_dummyMonitor), @"Monitor should be successfully added.");
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after adding.");

    kscm_removeMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after removal.");

    XCTAssertTrue(kscm_addMonitor(&g_dummyMonitor), @"Monitor should be successfully re-added.");
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled again after re-adding.");
}

#pragma mark - Monitor Deduplication Tests

- (void)testAddingMonitorsWithUniqueIds
{
    XCTAssertTrue(kscm_addMonitor(&g_dummyMonitor), @"First monitor should be successfully added.");
    XCTAssertTrue(kscm_addMonitor(&g_secondDummyMonitor), @"Second monitor should be successfully added.");

    kscm_activateMonitors();

    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The first monitor should be enabled.");
    XCTAssertTrue(g_secondDummyMonitor.isEnabled(), @"The second monitor should be enabled.");
}

- (void)testAddMonitorMultipleTimes
{
    XCTAssertTrue(kscm_addMonitor(&g_dummyMonitor), @"Monitor should be successfully added the first time.");
    XCTAssertFalse(kscm_addMonitor(&g_dummyMonitor), @"Monitor should not be added again if it's already present.");
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after multiple additions.");
}

- (void)testAddingAndRemovingMonitorsWithUniqueIds
{
    XCTAssertTrue(kscm_addMonitor(&g_dummyMonitor), @"First monitor should be successfully added.");
    XCTAssertTrue(kscm_addMonitor(&g_secondDummyMonitor), @"Second monitor should be successfully added.");

    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The dummy monitor should be enabled.");
    XCTAssertTrue(g_secondDummyMonitor.isEnabled(), @"The second dummy monitor should be enabled.");

    kscm_removeMonitor(&g_dummyMonitor);

    kscm_disableAllMonitors();
    kscm_activateMonitors();
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The dummy monitor should be disabled after removal.");
    XCTAssertTrue(g_secondDummyMonitor.isEnabled(), @"The second dummy monitor should remain enabled.");
}

@end
