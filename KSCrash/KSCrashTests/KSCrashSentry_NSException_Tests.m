//
//  KSCrashSentry_NSException_Tests.m
//  KSCrash
//
//  Created by Karl Stenerud on 1/26/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "KSCrashSentry_NSException.h"

@interface KSCrashSentry_NSException_Tests : SenTestCase @end

@implementation KSCrashSentry_NSException_Tests

- (void) testInstallAndRemove
{
    bool success;
    KSCrash_SentryContext context;
    success = kscrashsentry_installNSExceptionHandler(&context);
    STAssertTrue(success, @"");
    [NSThread sleepForTimeInterval:0.1];
    kscrashsentry_uninstallNSExceptionHandler();
}

- (void) testDoubleInstallAndRemove
{
    bool success;
    KSCrash_SentryContext context;
    success = kscrashsentry_installNSExceptionHandler(&context);
    STAssertTrue(success, @"");
    success = kscrashsentry_installNSExceptionHandler(&context);
    STAssertTrue(success, @"");
    kscrashsentry_uninstallNSExceptionHandler();
    kscrashsentry_uninstallNSExceptionHandler();
}

@end
