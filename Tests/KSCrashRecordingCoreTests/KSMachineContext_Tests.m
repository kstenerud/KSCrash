//
//  KSMachineContext_Tests.m
//  
//
//  Created by Gleb Linnik on 06.06.2024.
//

#import <XCTest/XCTest.h>

#import "KSCrashMonitorContext.h"

@interface KSMachineContext_Tests : XCTestCase @end

@implementation KSMachineContext_Tests

- (void) testSuspendResumeThreads
{
    thread_act_array_t threads1 = NULL;
    mach_msg_type_number_t numThreads1 = 0;
    ksmc_suspendEnvironment(&threads1, &numThreads1);

    thread_act_array_t threads2 = NULL;
    mach_msg_type_number_t numThreads2 = 0;
    ksmc_suspendEnvironment(&threads2, &numThreads2);

    ksmc_resumeEnvironment(threads2, numThreads2);
    ksmc_resumeEnvironment(threads1, numThreads1);
}

@end
