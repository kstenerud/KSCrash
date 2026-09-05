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

- (void)testGetThreadNameFromKernel
{
    NSString *expectedName = @"kernel-name-test";
    TestThread *thread = [TestThread new];
    thread.name = expectedName;
    [thread start];

    // Poll until the thread starts and Foundation applies its pthread name (up to 10 s).
    char buffer[64] = { 0 };
    bool found = false;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while ([deadline timeIntervalSinceNow] > 0) {
        if (thread.thread != MACH_PORT_NULL &&
            ksthread_getThreadNameFromKernel(thread.thread, buffer, sizeof(buffer))) {
            found = true;
            break;
        }
        [NSThread sleepForTimeInterval:0.05];
    }

    XCTAssertTrue(found, @"Failed to get thread name within 10 seconds");
    XCTAssertEqualObjects([NSString stringWithUTF8String:buffer], expectedName);

    // A buffer smaller than the name truncates but stays terminated.
    char small[8] = { 0 };
    XCTAssertTrue(ksthread_getThreadNameFromKernel(thread.thread, small, sizeof(small)));
    XCTAssertEqualObjects([NSString stringWithUTF8String:small], @"kernel-");

    [thread cancel];
}

- (void)testGetThreadNameFromKernelUnnamedThread
{
    TestThread *thread = [TestThread new];
    [thread start];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (thread.thread == MACH_PORT_NULL && [deadline timeIntervalSinceNow] > 0) {
        [NSThread sleepForTimeInterval:0.05];
    }
    XCTAssertNotEqual(thread.thread, MACH_PORT_NULL);

    char buffer[64];
    XCTAssertFalse(ksthread_getThreadNameFromKernel(thread.thread, buffer, sizeof(buffer)));

    [thread cancel];
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
