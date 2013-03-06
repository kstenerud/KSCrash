//
//  KSCrashSentry_Deadlock_Tests.m
//  KSCrash
//
//  Created by Karl Stenerud on 1/26/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "KSCrashSentry_Deadlock.h"

@interface KSCrashSentry_Deadlock_Tests : SenTestCase @end

@implementation KSCrashSentry_Deadlock_Tests

- (void) testInstallAndRemove
{
    bool success;
    KSCrash_SentryContext context;
    kscrashSentry_setDeadlockHandlerWatchdogInterval(10);
    success = kscrashsentry_installDeadlockHandler(&context);
    STAssertTrue(success, @"");
    [NSThread sleepForTimeInterval:0.1];
    kscrashsentry_uninstallDeadlockHandler();
}

- (void) testDoubleInstallAndRemove
{
    bool success;
    KSCrash_SentryContext context;
    success = kscrashsentry_installDeadlockHandler(&context);
    STAssertTrue(success, @"");
    success = kscrashsentry_installDeadlockHandler(&context);
    STAssertTrue(success, @"");
    kscrashsentry_uninstallDeadlockHandler();
    kscrashsentry_uninstallDeadlockHandler();
}

@end
