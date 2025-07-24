//
//  KSMachineContext_Tests.m
//
//  Created by Gleb Linnik on 06.06.2024.
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

#import "KSCrashMonitorContext.h"

@interface KSMachineContext_Tests : XCTestCase
@end

@implementation KSMachineContext_Tests

- (void)testSuspendResumeThreads
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

- (void)startTheBackgroundJob
{
    sleep(5);
}

- (void)testMaxThreadsInContext
{
    KSMachineContext machineContext = { 0 };
    for (int i = 0; i < 1005; ++i) {
        [NSThread detachNewThreadSelector:@selector(startTheBackgroundJob) toTarget:self withObject:nil];
    }

    ksmc_getContextForThread(ksthread_self(), &machineContext, true);
    XCTAssertEqual(machineContext.threadCount, MAX_CAPTURED_THREADS);
}

@end
