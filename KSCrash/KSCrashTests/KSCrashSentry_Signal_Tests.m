//
//  KSCrashSentry_Signal_Tests.m
//  KSCrash
//
//  Created by Karl Stenerud on 1/26/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "KSCrashSentry_Signal.h"

@interface KSCrashSentry_Signal_Tests : SenTestCase @end

@implementation KSCrashSentry_Signal_Tests

- (void) testInstallAndRemove
{
    bool success;
    KSCrash_SentryContext context;
    success = kscrashsentry_installSignalHandler(&context);
    STAssertTrue(success, @"");
    [NSThread sleepForTimeInterval:0.1];
    kscrashsentry_uninstallSignalHandler();
}

- (void) testDoubleInstallAndRemove
{
    bool success;
    KSCrash_SentryContext context;
    success = kscrashsentry_installSignalHandler(&context);
    STAssertTrue(success, @"");
    success = kscrashsentry_installSignalHandler(&context);
    STAssertTrue(success, @"");
    kscrashsentry_uninstallSignalHandler();
    kscrashsentry_uninstallSignalHandler();
}

@end
