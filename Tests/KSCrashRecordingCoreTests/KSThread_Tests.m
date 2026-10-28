//
//  KSThread_Tests.m
//
//  Created by Karl Stenerud on 2012-03-03.
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

#import "KSThread.h"
#import "TestThread.h"

@interface KSThread_Tests : XCTestCase
@end

@implementation KSThread_Tests

- (void)testGetQueueNameReadsTheQueuesOwnLabel
{
    // Pins the derived label offset. Reading the label from the wrong offset either finds nothing
    // readable or finds some other field, and neither spells out the label this queue was given.
    static const char *const kLabel = "com.kscrash.test.queue-label";
    dispatch_queue_t queue = dispatch_queue_create(kLabel, DISPATCH_QUEUE_SERIAL);
    XCTestExpectation *expectation = [self expectationWithDescription:@"read the queue label"];
    __block NSString *queueName = nil;

    dispatch_async(queue, ^{
        char buffer[256] = { 0 };
        if (ksthread_getQueueName(ksthread_self(), buffer, sizeof(buffer))) {
            queueName = @(buffer);
        }
        [expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:5 handler:nil];
    XCTAssertEqualObjects(queueName, @(kLabel));
}

- (void)testGetQueueName
{
    kern_return_t kr;
    const task_t thisTask = mach_task_self();
    thread_act_array_t threads;
    mach_msg_type_number_t numThreads;

    kr = task_threads(thisTask, &threads, &numThreads);
    XCTAssertTrue(kr == KERN_SUCCESS, @"");

    bool success = false;
    char buffer[100];
    for (mach_msg_type_number_t i = 0; i < numThreads; i++) {
        thread_t thread = threads[i];
        if (ksthread_getQueueName(thread, buffer, sizeof(buffer))) {
            success = true;
            break;
        }
    }

    for (mach_msg_type_number_t i = 0; i < numThreads; i++) {
        mach_port_deallocate(thisTask, threads[i]);
    }
    vm_deallocate(thisTask, (vm_address_t)threads, sizeof(thread_t) * numThreads);

    XCTAssertTrue(success, @"");
}

- (void)testMainThread
{
    KSThread mainThread = ksthread_main();
    XCTAssertNotEqual(mainThread, 0);
}

- (void)testMainThreadMatchesActualMainThread
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"captured main thread"];
    __block KSThread capturedThread = 0;

    dispatch_async(dispatch_get_main_queue(), ^{
        capturedThread = ksthread_self();
        [expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(ksthread_main(), capturedThread, @"ksthread_main should match the actual main thread");
}

- (void)testStateName
{
    int state = 0;
    const char *stateName = ksthread_state_name(state);
    XCTAssertEqual(stateName, NULL);

    state = 8;
    stateName = ksthread_state_name(state);
    XCTAssertEqual(stateName, NULL);

    state = 2;
    stateName = ksthread_state_name(state);
    NSString *stateString = @"TH_STATE_STOPPED";
    XCTAssertEqual(strcmp(stateName, stateString.UTF8String), 0);
}

- (void)testGetQueueNameOnThreadsThatKeepExiting
{
    // The reported crash: the queue slot lives in the target thread's pthread structure, so
    // reading it races that thread's exit. Read every thread in the process, the way the
    // cache's polling thread does, while a bounded number of short-lived threads come and
    // go underneath. A faulting read takes the test process down, so finishing is the pass.
    const int kRounds = 40;
    const int kThreadsPerRound = 4;

    char buffer[256];
    for (int round = 0; round < kRounds; round++) {
        NSMutableArray<NSThread *> *threadsThisRound = [NSMutableArray array];
        for (int i = 0; i < kThreadsPerRound; i++) {
            NSThread *thread = [[NSThread alloc] initWithBlock:^{
                [NSThread sleepForTimeInterval:0.001];
            }];
            [thread start];
            [threadsThisRound addObject:thread];
        }

        thread_act_array_t threads = NULL;
        mach_msg_type_number_t threadCount = 0;
        if (task_threads(mach_task_self(), &threads, &threadCount) == KERN_SUCCESS) {
            for (mach_msg_type_number_t i = 0; i < threadCount; i++) {
                // Whatever it answers is fine; not faulting is the point.
                (void)ksthread_getQueueName((KSThread)threads[i], buffer, sizeof(buffer));
                mach_port_deallocate(mach_task_self(), threads[i]);
            }
            vm_deallocate(mach_task_self(), (vm_address_t)threads, sizeof(thread_t) * threadCount);
        }

        // Let this round's threads finish before starting the next, so the test cannot
        // outrun the thread pool.
        for (NSThread *thread in threadsThisRound) {
            while (!thread.isFinished) {
                [NSThread sleepForTimeInterval:0.001];
            }
        }
    }
}

- (void)testGetQueueNameTruncatesALabelLongerThanTheBuffer
{
    // A label longer than the buffer keeps what fits beside its NUL, and a buffer with exactly
    // room for the NUL takes the label whole.
    static const char *const kLabel = "com.kscrash.test.a-queue-label-longer-than-the-buffer";
    dispatch_queue_t queue = dispatch_queue_create(kLabel, DISPATCH_QUEUE_SERIAL);
    XCTestExpectation *expectation = [self expectationWithDescription:@"read the queue label"];
    __block BOOL truncatedFound = NO;
    __block BOOL exactFound = NO;
    __block NSString *truncated = nil;
    __block NSString *exact = nil;

    dispatch_async(queue, ^{
        char buffer[16];
        memset(buffer, 'x', sizeof(buffer));
        truncatedFound = ksthread_getQueueName(ksthread_self(), buffer, sizeof(buffer));
        truncated = truncatedFound ? @(buffer) : nil;

        char wide[128];
        exactFound = ksthread_getQueueName(ksthread_self(), wide, (int)strlen(kLabel) + 1);
        exact = exactFound ? @(wide) : nil;
        [expectation fulfill];
    });

    [self waitForExpectationsWithTimeout:5 handler:nil];
    XCTAssertTrue(truncatedFound);
    XCTAssertEqualObjects(truncated, [@(kLabel) substringToIndex:15]);
    XCTAssertTrue(exactFound);
    XCTAssertEqualObjects(exact, @(kLabel));
}

- (void)testGetQueueNameRejectsNonPositiveBufferLengths
{
    // bufLength is cast to size_t for the copy, so a non-positive length would become enormous
    // and the copy unbounded. The guard for a real buffer with a bogus length must come before
    // any writing, so pass a real buffer and check it is untouched.
    char buffer[64];
    memset(buffer, 'x', sizeof(buffer));

    XCTAssertFalse(ksthread_getQueueName(ksthread_self(), buffer, 0));
    XCTAssertFalse(ksthread_getQueueName(ksthread_self(), buffer, -1));

    for (size_t i = 0; i < sizeof(buffer); i++) {
        XCTAssertEqual(buffer[i], 'x', @"a rejected call must not write to the buffer");
    }
}

@end
