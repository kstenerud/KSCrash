//
//  KSSystemInfo_Tests.m
//  KSCrash
//
//  Created by Karl Stenerud on 1/26/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "KSSystemInfo.h"
#import "KSSystemInfoC.h"

@interface KSSystemInfo_Tests : SenTestCase @end

@implementation KSSystemInfo_Tests

- (void) testSystemInfo
{
    NSDictionary* info = [KSSystemInfo systemInfo];
    STAssertNotNil(info, @"");
}

- (void) testSystemInfoJSON
{
    const char* json = kssysteminfo_toJSON();
    STAssertTrue(json != NULL, @"");
}

- (void) testCopyProcessName
{
    char* processName = kssystemInfo_copyProcessName();
    STAssertTrue(processName != NULL, @"");
    if(processName != NULL)
    {
        free(processName);
    }
}

@end
