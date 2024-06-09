//
//  KSCrashMonitor_DiscSpace_Tests.m
//
//
//  Created by Gleb Linnik on 10.06.2024.
//

#import <XCTest/XCTest.h>
#import "KSCrashMonitorContext.h"

#import "KSCrashMonitor_DiscSpace.h"

// Function to reset global state for tests
extern void kscm_discSpace_resetState(void);

@interface KSCrashMonitorDiscSpaceTests : XCTestCase
@end

@implementation KSCrashMonitorDiscSpaceTests

- (void)setUp
{
    [super setUp];
    kscm_discSpace_resetState();
}

- (void)testMonitorActivation
{
    KSCrashMonitorAPI* discSpaceMonitor = kscm_discspace_getAPI();

    XCTAssertFalse(discSpaceMonitor->isEnabled(), @"Disc space monitor should be initially disabled.");
    discSpaceMonitor->setEnabled(true);
    XCTAssertTrue(discSpaceMonitor->isEnabled(), @"Disc space monitor should be enabled after setting.");
    discSpaceMonitor->setEnabled(false);
    XCTAssertFalse(discSpaceMonitor->isEnabled(), @"Disc space monitor should be disabled after setting.");
}

- (void)testAddContextualInfoWhenEnabled
{
    KSCrashMonitorAPI* discSpaceMonitor = kscm_discspace_getAPI();
    discSpaceMonitor->setEnabled(true);

    KSCrash_MonitorContext context = { 0 };
    discSpaceMonitor->addContextualInfoToEvent(&context);

    // Check that storage size is added to the context
    XCTAssertFalse(context.System.storageSize == 0,
                   @"Storage size should be added to the context when the monitor is enabled.");
}

- (void)testNoContextualInfoWhenDisabled
{
    KSCrashMonitorAPI* discSpaceMonitor = kscm_discspace_getAPI();
    discSpaceMonitor->setEnabled(false);

    KSCrash_MonitorContext context = { 0 };
    discSpaceMonitor->addContextualInfoToEvent(&context);

    XCTAssertTrue(context.System.storageSize == 0,
                  @"Storage size should not be added to the context when the monitor is disabled.");
}

- (void)testMonitorName
{
    KSCrashMonitorAPI* discSpaceMonitor = kscm_discspace_getAPI();
    XCTAssertEqual(strcmp(discSpaceMonitor->name(), "KSCrashMonitorTypeDiscSpace"), 0,
                   @"The monitor name should be 'KSCrashMonitorTypeDiscSpace'.");
}

@end
