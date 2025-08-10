//
//  KSCrashMonitorRegistry_Tests.m
//
//  Created by Karl Stenerud on 2025-08-09.
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

#import "KSCrashMonitorRegistry.h"

@interface KSCrashMonitorRegistry_Tests : XCTestCase
@end

@implementation KSCrashMonitorRegistry_Tests

#pragma mark - Dummy monitors -

// First monitor
static bool g_dummyEnabledState = false;
static bool g_dummyPostSystemEnabled = false;
static const char *const g_eventID = "TestEventID";
static const char *g_copiedEventID = NULL;

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
    // Second monitor
    memset(&g_secondDummyMonitor, 0, sizeof(g_secondDummyMonitor));
    kscma_initAPI(&g_secondDummyMonitor);
    g_secondDummyMonitor.init = secondDummyInit;
    g_secondDummyMonitor.monitorId = secondDummyMonitorId;
    g_secondDummyMonitor.setEnabled = secondDummySetEnabled;
    g_secondDummyMonitor.isEnabled = secondDummyIsEnabled;
    g_secondDummyEnabledState = false;
}

#pragma mark - Monitor Activation Tests

- (void)testAddingAndActivatingMonitors
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");
    kscmr_activateMonitors(&list);  // Activate all monitors
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
}

- (void)testDisablingAllMonitors
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    kscmr_addMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled before disabling.");
    kscmr_disableAllMonitors(&list);  // Disable all monitors
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after calling disable all.");
}

- (void)testActivateMonitorsReturnsTrue
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");
    XCTAssertTrue(kscmr_activateMonitors(&list),
                  @"activateMonitors should return true when at least one monitor is activated.");
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after activation.");
}

- (void)testActivateMonitorsReturnsFalseWhenNoMonitorsActive
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    // Don't add any monitors
    XCTAssertFalse(kscmr_activateMonitors(&list), @"activateMonitors should return false when no monitors are active.");
}

- (void)testActivateMonitorsReturnsFalseWhenAllMonitorsDisabled
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    KSCrashMonitorAPI alwaysDisabledMonitor = g_dummyMonitor;
    alwaysDisabledMonitor.setEnabled = (void (*)(bool))imp_implementationWithBlock(^(__unused bool isEnabled) {
        // pass
    });
    alwaysDisabledMonitor.isEnabled = (bool (*)(void))imp_implementationWithBlock(^{
        return false;
    });

    XCTAssertTrue(kscmr_addMonitor(&list, &alwaysDisabledMonitor), @"Monitor should be successfully added.");
    XCTAssertFalse(kscmr_activateMonitors(&list),
                   @"activateMonitors should return false when all monitors are disabled.");
}

#pragma mark - Monitor API Null Checks

- (void)testAddMonitorWithNullAPI
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertFalse(kscmr_addMonitor(&list, NULL), @"Adding a NULL monitor should return false.");
    kscmr_activateMonitors(&list);
    // No assertion needed, just verifying no crash occurred
}

#pragma mark - Monitor Removal Tests

- (void)testRemovingMonitor
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    // Add the dummy monitor first
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after adding.");

    // Remove the dummy monitor
    kscmr_removeMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after removal.");
}

- (void)testRemoveMonitorNotAdded
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    KSCrashMonitorAPI newMonitor = g_dummyMonitor;
    newMonitor.monitorId = newMonitorId;  // Set monitorId as a function pointer

    kscmr_removeMonitor(&list, &newMonitor);  // Remove without adding
    kscmr_activateMonitors(&list);

    // Verify that no crash occurred and the state remains unchanged
    XCTAssertFalse(newMonitor.isEnabled ? newMonitor.isEnabled() : NO,
                   @"The new monitor should not be enabled, as it was never added.");
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The dummy monitor should still be disabled as it's not related.");
}

- (void)testRemoveMonitorTwice
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    // Add and then remove the dummy monitor
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after adding.");

    kscmr_removeMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after the first removal.");

    // Try to remove the dummy monitor again
    kscmr_removeMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should remain disabled after a second removal attempt.");
}

- (void)testRemoveMonitorAndReAdd
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    // Add, remove, and then re-add the dummy monitor
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after adding.");

    kscmr_removeMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The monitor should be disabled after removal.");

    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully re-added.");
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled again after re-adding.");
}

#pragma mark - Monitor Deduplication Tests

- (void)testAddingMonitorsWithUniqueIds
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"First monitor should be successfully added.");
    XCTAssertTrue(kscmr_addMonitor(&list, &g_secondDummyMonitor), @"Second monitor should be successfully added.");

    kscmr_activateMonitors(&list);

    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The first monitor should be enabled.");
    XCTAssertTrue(g_secondDummyMonitor.isEnabled(), @"The second monitor should be enabled.");
}

- (void)testAddMonitorMultipleTimes
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added the first time.");
    XCTAssertFalse(kscmr_addMonitor(&list, &g_dummyMonitor),
                   @"Monitor should not be added again if it's already present.");
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The monitor should be enabled after multiple additions.");
}

- (void)testAddingAndRemovingMonitorsWithUniqueIds
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"First monitor should be successfully added.");
    XCTAssertTrue(kscmr_addMonitor(&list, &g_secondDummyMonitor), @"Second monitor should be successfully added.");

    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(), @"The dummy monitor should be enabled.");
    XCTAssertTrue(g_secondDummyMonitor.isEnabled(), @"The second dummy monitor should be enabled.");

    kscmr_removeMonitor(&list, &g_dummyMonitor);

    kscmr_disableAllMonitors(&list);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(), @"The dummy monitor should be disabled after removal.");
    XCTAssertTrue(g_secondDummyMonitor.isEnabled(), @"The second dummy monitor should remain enabled.");
}

@end
