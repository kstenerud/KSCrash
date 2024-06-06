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

#import "KSCrashMonitor.h"

@interface KSCrashMonitor_Tests : XCTestCase
@end

@implementation KSCrashMonitor_Tests

#pragma mark - Dummy monitor -

static bool g_dummyEnabledState = false;
static const char* const g_eventID = "TestEventID";

static const char* dummyMonitorName(void) { return "Dummy Monitor"; }

static KSCrashMonitorProperty dummyMonitorProperties(void) { return KSCrashMonitorPropertyAsyncSafe; }

static void dummySetEnabled(bool isEnabled) { g_dummyEnabledState = isEnabled; }

static bool dummyIsEnabled(void) { return g_dummyEnabledState; }

static void dummyAddContextualInfoToEvent(struct KSCrash_MonitorContext* eventContext)
{
    if (eventContext != NULL)
    {
        eventContext->eventID = g_eventID;
    }
}

static void dummyNotifyPostSystemEnable(void)
{
    // No-op for this dummy implementation
}

// Create a dummy monitor API
KSCrashMonitorAPI g_dummyMonitor = {
    .name = dummyMonitorName,
    .properties = dummyMonitorProperties,
    .setEnabled = dummySetEnabled,
    .isEnabled = dummyIsEnabled,
    .addContextualInfoToEvent = dummyAddContextualInfoToEvent,
    .notifyPostSystemEnable = dummyNotifyPostSystemEnable,
};

#pragma mark - Tests -

static BOOL exceptionHandled = NO;

static void myEventCallback(struct KSCrash_MonitorContext* context) { exceptionHandled = YES; }

extern void kscm_resetState(void);

- (void)setUp
{
    [super setUp];
    g_dummyEnabledState = false;
    exceptionHandled = NO;
    kscm_resetState();
}

- (void)testAddingAndActivatingMonitors
{
    kscm_addMonitor(&g_dummyMonitor);  // Add the dummy monitor
    kscm_activateMonitors();           // Activate all monitors
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

- (void)testHandlingCrashEvent
{
    kscm_setEventCallback(myEventCallback);  // Set the event callback
    struct KSCrash_MonitorContext context = { 0 };
    context.monitorProperties = KSCrashMonitorPropertyFatal;
    kscm_handleException(&context);  // Handle the exception
    XCTAssertTrue(exceptionHandled, @"The exception should have been handled by the event callback.");
}

- (void)testCrashDuringExceptionHandling
{
    // Test detection of crash during exception handling
    XCTAssertFalse(kscm_notifyFatalExceptionCaptured(true),
                   @"First call should not detect crash during exception handling.");
    XCTAssertTrue(kscm_notifyFatalExceptionCaptured(true),
                  @"It should detect a crash during exception handling on the second call.");
    XCTAssertTrue(kscm_notifyFatalExceptionCaptured(true),
                  @"It should continue to detect a crash during exception handling.");
}

- (void)testHandleExceptionAddsContextualInfo
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    struct KSCrash_MonitorContext context = { 0 };
    context.eventID = 0;             // Initialize with a known value
    kscm_handleException(&context);  // Handle the exception
    XCTAssertEqual(strcmp(context.eventID, g_eventID), 0,
                   @"The eventID should be set to 'TestEventID' by the dummy monitor when handling exception.");
}

- (void)testHandleExceptionRestoresOriginalHandlers
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
    struct KSCrash_MonitorContext context = { 0 };
    context.currentSnapshotUserReported = false;              // Simulate that the exception is not user-reported
    context.monitorProperties = KSCrashMonitorPropertyFatal;  // Indicate that the exception is fatal
    kscm_handleException(&context);
    XCTAssertTrue(g_dummyMonitor.isEnabled(),
                  @"The monitor should still be enabled before fatal exception handling logic.");
    kscm_notifyFatalExceptionCaptured(false);  // Simulate capturing a fatal exception
    kscm_handleException(&context);            // Handle the exception again
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after handling a fatal exception.");
}

- (void)testHandleExceptionCrashedDuringExceptionHandling
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
    struct KSCrash_MonitorContext context = { 0 };
    context.crashedDuringCrashHandling = false;  // Initial state should be false
    kscm_notifyFatalExceptionCaptured(false);    // Set g_handlingFatalException to true
    kscm_notifyFatalExceptionCaptured(false);    // Set g_crashedDuringExceptionHandling to true
    kscm_handleException(&context);              // Handle the exception
    XCTAssertTrue(
        context.crashedDuringCrashHandling,
        @"The context's crashedDuringCrashHandling should be true when g_crashedDuringExceptionHandling is true.");
}

- (void)testHandleExceptionCurrentSnapshotUserReported
{
    kscm_addMonitor(&g_dummyMonitor);
    kscm_activateMonitors();
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
    struct KSCrash_MonitorContext context = { 0 };
    context.currentSnapshotUserReported = true;               // Simulate that the snapshot is user-reported
    context.monitorProperties = KSCrashMonitorPropertyFatal;  // Indicate that the exception is fatal
    kscm_notifyFatalExceptionCaptured(false);                 // Simulate capturing a fatal exception
    kscm_handleException(&context);                           // Handle the exception

    // Since we can't access g_handlingFatalException directly, we indirectly check its effect
    // by ensuring that the monitor is still enabled because g_handlingFatalException should be false now
    XCTAssertTrue(g_dummyMonitor.isEnabled(),
                  @"The monitor should still be enabled when the snapshot is user-reported.");
}

@end
