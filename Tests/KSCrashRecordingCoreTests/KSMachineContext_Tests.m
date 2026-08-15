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

    ksmc_resumeEnvironment(&threads2, &numThreads2);
    ksmc_resumeEnvironment(&threads1, &numThreads1);
    XCTAssertEqual(threads1, NULL);
    XCTAssertEqual(threads2, NULL);

    // These should be idempotent
    ksmc_resumeEnvironment(&threads2, &numThreads2);
    ksmc_resumeEnvironment(&threads1, &numThreads1);
    ksmc_resumeEnvironment(&threads2, &numThreads2);
    ksmc_resumeEnvironment(&threads1, &numThreads1);
    ksmc_resumeEnvironment(&threads2, &numThreads2);
    ksmc_resumeEnvironment(&threads1, &numThreads1);
}

- (void)startTheBackgroundJob
{
    sleep(5);
}

- (void)testMaxThreadsInContext
{
    KSMachineContext machineContext = { 0 };
    int threadsToCreate = MAX_CAPTURED_THREADS + 5;
    for (int i = 0; i < threadsToCreate; ++i) {
        [NSThread detachNewThreadSelector:@selector(startTheBackgroundJob) toTarget:self withObject:nil];
    }

    ksmc_getContextForThread(ksthread_self(), &machineContext, true);
    XCTAssertEqual(machineContext.threadCount, MAX_CAPTURED_THREADS);
}

#pragma mark - Task Thread Context

static uint64_t threadIDOfPort(thread_t port)
{
    thread_identifier_info_data_t info;
    mach_msg_type_number_t count = THREAD_IDENTIFIER_INFO_COUNT;
    if (thread_info(port, THREAD_IDENTIFIER_INFO, (thread_info_t)&info, &count) != KERN_SUCCESS) {
        return 0;
    }
    return info.thread_id;
}

// Validated against our own task: the same call works on a corpse port, which is the
// case it exists for (crash info identifies the crashed thread by kernel thread id).
- (void)testGetContextForTaskThreadFillsFromTask
{
    uint64_t currentThreadID = threadIDOfPort((thread_t)ksthread_self());
    XCTAssertNotEqual(currentThreadID, 0);

    KSMachineContext machineContext = { 0 };
    XCTAssertTrue(ksmc_getContextForTaskThread(mach_task_self(), NULL, currentThreadID, &machineContext));

    XCTAssertEqual(machineContext.task, mach_task_self());
    XCTAssertEqual(threadIDOfPort(machineContext.thisThread), currentThreadID);
    XCTAssertTrue(machineContext.isCrashedContext);
    XCTAssertGreaterThan(machineContext.threadCount, 0);
    bool found = false;
    for (int i = 0; i < machineContext.threadCount && !found; i++) {
        found = machineContext.allThreads[i] == machineContext.thisThread;
    }
    XCTAssertTrue(found, @"The subject thread must be in the context's thread list");
}

- (void)testGetContextForTaskThreadFailsForUnknownThreadID
{
    KSMachineContext machineContext = { 0 };
    XCTAssertFalse(ksmc_getContextForTaskThread(mach_task_self(), NULL, UINT64_MAX, &machineContext));
}

@end
