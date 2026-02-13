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
static void dummyInit(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    dummyExceptionHandlerCallbacks = *callbacks;
}

static const char *dummyMonitorId(__unused void *context) { return "Dummy Monitor"; }
static const char *newMonitorId(__unused void *context) { return "New Monitor"; }

static KSCrashMonitorFlag dummyMonitorFlags(__unused void *context) { return KSCrashMonitorFlagAsyncSafe; }

static void dummySetEnabled(bool isEnabled, __unused void *context) { g_dummyEnabledState = isEnabled; }
static bool dummyIsEnabled(__unused void *context) { return g_dummyEnabledState; }
static void dummyAddContextualInfoToEvent(struct KSCrash_MonitorContext *eventContext, __unused void *context)
{
    if (eventContext != NULL) {
        strncpy(eventContext->eventID, g_eventID, sizeof(eventContext->eventID));
    }
}

static void dummyNotifyPostSystemEnable(__unused void *context) { g_dummyPostSystemEnabled = true; }

// Second monitor
static KSCrash_ExceptionHandlerCallbacks secondDummyExceptionHandlerCallbacks;
static void secondDummyInit(KSCrash_ExceptionHandlerCallbacks *callbacks, __unused void *context)
{
    secondDummyExceptionHandlerCallbacks = *callbacks;
}

static const char *secondDummyMonitorId(__unused void *context) { return "Second Dummy Monitor"; }

static bool g_secondDummyEnabledState = false;
// static const char *const g_secondEventID = "SecondEventID";

static void secondDummySetEnabled(bool isEnabled, __unused void *context) { g_secondDummyEnabledState = isEnabled; }
static bool secondDummyIsEnabled(__unused void *context) { return g_secondDummyEnabledState; }

static KSCrashMonitorFlag combinedMonitorFlags(__unused void *context)
{
    return KSCrashMonitorFlagDebuggerUnsafe | KSCrashMonitorFlagAsyncSafe;
}

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
    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The monitor should be enabled after activation.");
}

- (void)testDisablingAllMonitors
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    kscmr_addMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The monitor should be enabled before disabling.");
    kscmr_disableAllMonitors(&list);  // Disable all monitors
    XCTAssertFalse(g_dummyMonitor.isEnabled(NULL), @"The monitor should be disabled after calling disable all.");
}

- (void)testActivateMonitorsReturnsTrue
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");
    XCTAssertTrue(kscmr_activateMonitors(&list),
                  @"activateMonitors should return true when at least one monitor is activated.");
    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The monitor should be enabled after activation.");
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
    alwaysDisabledMonitor.setEnabled =
        (void (*)(bool, void *))(void *)imp_implementationWithBlock(^(__unused bool isEnabled, __unused void *ctx) {
            // pass
        });
    alwaysDisabledMonitor.isEnabled = (bool (*)(void *))(void *)imp_implementationWithBlock(^(__unused void *ctx) {
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
    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The monitor should be enabled after adding.");

    // Remove the dummy monitor
    kscmr_removeMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(NULL), @"The monitor should be disabled after removal.");
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
    XCTAssertFalse(newMonitor.isEnabled ? newMonitor.isEnabled(NULL) : NO,
                   @"The new monitor should not be enabled, as it was never added.");
    XCTAssertFalse(g_dummyMonitor.isEnabled(NULL), @"The dummy monitor should still be disabled as it's not related.");
}

- (void)testRemoveMonitorTwice
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    // Add and then remove the dummy monitor
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The monitor should be enabled after adding.");

    kscmr_removeMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(NULL), @"The monitor should be disabled after the first removal.");

    // Try to remove the dummy monitor again
    kscmr_removeMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(NULL),
                   @"The monitor should remain disabled after a second removal attempt.");
}

- (void)testRemoveMonitorAndReAdd
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    // Add, remove, and then re-add the dummy monitor
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The monitor should be enabled after adding.");

    kscmr_removeMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(NULL), @"The monitor should be disabled after removal.");

    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully re-added.");
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The monitor should be enabled again after re-adding.");
}

#pragma mark - Monitor Deduplication Tests

- (void)testAddingMonitorsWithUniqueIds
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"First monitor should be successfully added.");
    XCTAssertTrue(kscmr_addMonitor(&list, &g_secondDummyMonitor), @"Second monitor should be successfully added.");

    kscmr_activateMonitors(&list);

    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The first monitor should be enabled.");
    XCTAssertTrue(g_secondDummyMonitor.isEnabled(NULL), @"The second monitor should be enabled.");
}

- (void)testAddMonitorMultipleTimes
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added the first time.");
    XCTAssertFalse(kscmr_addMonitor(&list, &g_dummyMonitor),
                   @"Monitor should not be added again if it's already present.");
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The monitor should be enabled after multiple additions.");
}

- (void)testAddingAndRemovingMonitorsWithUniqueIds
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"First monitor should be successfully added.");
    XCTAssertTrue(kscmr_addMonitor(&list, &g_secondDummyMonitor), @"Second monitor should be successfully added.");

    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyMonitor.isEnabled(NULL), @"The dummy monitor should be enabled.");
    XCTAssertTrue(g_secondDummyMonitor.isEnabled(NULL), @"The second dummy monitor should be enabled.");

    kscmr_removeMonitor(&list, &g_dummyMonitor);

    kscmr_disableAllMonitors(&list);
    kscmr_activateMonitors(&list);
    XCTAssertFalse(g_dummyMonitor.isEnabled(NULL), @"The dummy monitor should be disabled after removal.");
    XCTAssertTrue(g_secondDummyMonitor.isEnabled(NULL), @"The second dummy monitor should remain enabled.");
}

#pragma mark - Monitor Lookup Tests

- (void)testGetMonitorById
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");

    const KSCrashMonitorAPI *result = kscmr_getMonitor(&list, "Dummy Monitor");
    XCTAssertTrue(result == &g_dummyMonitor, @"Should return the correct monitor.");
}

- (void)testGetMonitorByIdNotFound
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");

    const KSCrashMonitorAPI *result = kscmr_getMonitor(&list, "Nonexistent Monitor");
    XCTAssertTrue(result == NULL, @"Should return NULL for nonexistent monitor.");
}

- (void)testGetMonitorByIdFromEmptyList
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));

    const KSCrashMonitorAPI *result = kscmr_getMonitor(&list, "Dummy Monitor");
    XCTAssertTrue(result == NULL, @"Should return NULL when list is empty.");
}

- (void)testGetMonitorByIdWithNullId
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");

    const KSCrashMonitorAPI *result = kscmr_getMonitor(&list, NULL);
    XCTAssertTrue(result == NULL, @"Should return NULL when searching for NULL id.");
}

- (void)testGetMonitorByIdWithMultipleMonitors
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"First monitor should be successfully added.");
    XCTAssertTrue(kscmr_addMonitor(&list, &g_secondDummyMonitor), @"Second monitor should be successfully added.");

    const KSCrashMonitorAPI *result1 = kscmr_getMonitor(&list, "Dummy Monitor");
    const KSCrashMonitorAPI *result2 = kscmr_getMonitor(&list, "Second Dummy Monitor");

    XCTAssertTrue(result1 == &g_dummyMonitor, @"Should return the first monitor.");
    XCTAssertTrue(result2 == &g_secondDummyMonitor, @"Should return the second monitor.");
}

- (void)testGetMonitorByIdAfterRemoval
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    XCTAssertTrue(kscmr_addMonitor(&list, &g_dummyMonitor), @"Monitor should be successfully added.");

    const KSCrashMonitorAPI *resultBefore = kscmr_getMonitor(&list, "Dummy Monitor");
    XCTAssertTrue(resultBefore == &g_dummyMonitor, @"Should find monitor before removal.");

    kscmr_removeMonitor(&list, &g_dummyMonitor);

    const KSCrashMonitorAPI *resultAfter = kscmr_getMonitor(&list, "Dummy Monitor");
    XCTAssertTrue(resultAfter == NULL, @"Should return NULL after monitor is removed.");
}

#pragma mark - Disable Async-Safe Monitors Tests

- (void)testDisableAsyncSafeMonitorsDisablesAsyncSafeMonitor
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    kscmr_addMonitor(&list, &g_dummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyEnabledState, @"Async-safe monitor should be enabled after activation.");

    kscmr_disableAsyncSafeMonitors(&list);
    XCTAssertFalse(g_dummyEnabledState, @"Async-safe monitor should be disabled.");
}

- (void)testDisableAsyncSafeMonitorsLeavesNonAsyncSafeEnabled
{
    // g_secondDummyMonitor uses default monitorFlags (KSCrashMonitorFlagNone)
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    kscmr_addMonitor(&list, &g_secondDummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_secondDummyEnabledState, @"Non-async-safe monitor should be enabled after activation.");

    kscmr_disableAsyncSafeMonitors(&list);
    XCTAssertTrue(g_secondDummyEnabledState, @"Non-async-safe monitor should remain enabled.");
}

- (void)testDisableAsyncSafeMonitorsSelectiveFiltering
{
    // g_dummyMonitor has KSCrashMonitorFlagAsyncSafe
    // g_secondDummyMonitor has KSCrashMonitorFlagNone (default)
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    kscmr_addMonitor(&list, &g_dummyMonitor);
    kscmr_addMonitor(&list, &g_secondDummyMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyEnabledState, @"Async-safe monitor should be enabled after activation.");
    XCTAssertTrue(g_secondDummyEnabledState, @"Non-async-safe monitor should be enabled after activation.");

    kscmr_disableAsyncSafeMonitors(&list);
    XCTAssertFalse(g_dummyEnabledState, @"Async-safe monitor should be disabled.");
    XCTAssertTrue(g_secondDummyEnabledState, @"Non-async-safe monitor should remain enabled.");
}

- (void)testDisableAsyncSafeMonitorsOnEmptyList
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    // Should not crash on empty list
    kscmr_disableAsyncSafeMonitors(&list);
}

- (void)testDisableAsyncSafeMonitorsWithCombinedFlags
{
    // A monitor with both DebuggerUnsafe and AsyncSafe flags should still be disabled
    KSCrashMonitorAPI combinedMonitor = g_dummyMonitor;
    combinedMonitor.monitorFlags = combinedMonitorFlags;

    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    kscmr_addMonitor(&list, &combinedMonitor);
    kscmr_activateMonitors(&list);
    XCTAssertTrue(g_dummyEnabledState, @"Combined-flags monitor should be enabled after activation.");

    kscmr_disableAsyncSafeMonitors(&list);
    XCTAssertFalse(g_dummyEnabledState, @"Monitor with AsyncSafe flag should be disabled regardless of other flags.");
}

- (void)testDisableAsyncSafeMonitorsIdempotent
{
    KSCrashMonitorAPIList list;
    memset(&list, 0, sizeof(list));
    kscmr_addMonitor(&list, &g_dummyMonitor);
    kscmr_addMonitor(&list, &g_secondDummyMonitor);
    kscmr_activateMonitors(&list);

    kscmr_disableAsyncSafeMonitors(&list);
    XCTAssertFalse(g_dummyEnabledState);
    XCTAssertTrue(g_secondDummyEnabledState);

    // Calling again should not change anything
    kscmr_disableAsyncSafeMonitors(&list);
    XCTAssertFalse(g_dummyEnabledState, @"Async-safe monitor should still be disabled after second call.");
    XCTAssertTrue(g_secondDummyEnabledState, @"Non-async-safe monitor should still be enabled after second call.");
}

@end
