//
//  KSMach_Tests.m
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

#import "KSMach.h"
#import <mach/mach_time.h>


@interface TestThread: NSThread

@property(nonatomic, readwrite, assign) thread_t thread;

@end

@implementation TestThread

@synthesize thread = _thread;

- (void) main
{
    self.thread = ksmach_thread_self();
    while(!self.isCancelled)
    {
        [[self class] sleepForTimeInterval:0.1];
    }
}

@end


@interface KSMach_Tests : XCTestCase @end

@implementation KSMach_Tests

- (void) testExceptionName
{
    NSString* expected = @"EXC_ARITHMETIC";
    NSString* actual = [NSString stringWithCString:ksmach_exceptionName(EXC_ARITHMETIC)
                                          encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void) testVeryHighExceptionName
{
    const char* result = ksmach_exceptionName(100000);
    XCTAssertTrue(result == NULL, @"");
}

- (void) testKernReturnCodeName
{
    NSString* expected = @"KERN_FAILURE";
    NSString* actual = [NSString stringWithCString:ksmach_kernelReturnCodeName(KERN_FAILURE)
                                          encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(actual, expected, @"");
}

- (void) testVeryHighKernReturnCodeName
{
    const char* result = ksmach_kernelReturnCodeName(100000);
    XCTAssertTrue(result == NULL, @"");
}

- (void) testFreeMemory
{
    uint64_t freeMem = ksmach_freeMemory();
    XCTAssertTrue(freeMem > 0, @"");
}

- (void) testUsableMemory
{
    uint64_t usableMem = ksmach_usableMemory();
    XCTAssertTrue(usableMem > 0, @"");
}

- (void) testSuspendThreads
{
    bool success;
    success = ksmach_suspendAllThreads();
    XCTAssertTrue(success, @"");
    success = ksmach_resumeAllThreads();
    XCTAssertTrue(success, @"");
}

- (void) testCopyMem
{
    char buff[100];
    char buff2[100] = {1,2,3,4,5};
    
    kern_return_t result = ksmach_copyMem(buff2, buff, sizeof(buff));
    XCTAssertEqual(result, KERN_SUCCESS, @"");
    int memCmpResult = memcmp(buff, buff2, sizeof(buff));
    XCTAssertEqual(memCmpResult, 0, @"");
}

- (void) testCopyMemNull
{
    char buff[100];
    char* buff2 = NULL;
    
    kern_return_t result = ksmach_copyMem(buff2, buff, sizeof(buff));
    XCTAssertTrue(result != KERN_SUCCESS, @"");
}

- (void) testCopyMemBad
{
    char buff[100];
    char* buff2 = (char*)-1;
    
    kern_return_t result = ksmach_copyMem(buff2, buff, sizeof(buff));
    XCTAssertTrue(result != KERN_SUCCESS, @"");
}

- (void) testCopyMaxPossibleMem
{
    char buff[1000];
    char buff2[5] = {1,2,3,4,5};
    
    size_t copied = ksmach_copyMaxPossibleMem(buff2, buff, sizeof(buff));
    XCTAssertTrue(copied >= 5, @"");
    int memCmpResult = memcmp(buff, buff2, sizeof(buff2));
    XCTAssertEqual(memCmpResult, 0, @"");
}

- (void) testCopyMaxPossibleMemNull
{
    char buff[1000];
    char* buff2 = NULL;
    
    size_t copied = ksmach_copyMaxPossibleMem(buff2, buff, sizeof(buff));
    XCTAssertTrue(copied == 0, @"");
}

- (void) testCopyMaxPossibleMemBad
{
    char buff[1000];
    char* buff2 = (char*)-1;
    
    size_t copied = ksmach_copyMaxPossibleMem(buff2, buff, sizeof(buff));
    XCTAssertTrue(copied == 0, @"");
}

- (void) testTimeDifferenceInSeconds
{
    uint64_t startTime = mach_absolute_time();
    [NSThread sleepForTimeInterval:0.1];
    uint64_t endTime = mach_absolute_time();
    double diff = ksmach_timeDifferenceInSeconds(endTime, startTime);
    XCTAssertTrue(diff >= 0.1 && diff < 0.2, @"");
}

- (void) testIsBeingTraced
{
    bool traced = ksmach_isBeingTraced();
    XCTAssertTrue(traced, @"");
}

// TODO: Disabling this until I figure out what's wrong with queue names.
//- (void) testGetQueueName
//{
//    kern_return_t kr;
//    const task_t thisTask = mach_task_self();
//    thread_act_array_t threads;
//    mach_msg_type_number_t numThreads;
//    
//    kr = task_threads(thisTask, &threads, &numThreads);
//    XCTAssertTrue(kr == KERN_SUCCESS, @"");
//    
//    bool success = false;
//    char buffer[100];
//    for(mach_msg_type_number_t i = 0; i < numThreads; i++)
//    {
//        thread_t thread = threads[i];
//        if(ksmach_getThreadQueueName(thread, buffer, sizeof(buffer)))
//        {
//            success = true;
//            break;
//        }
//    }
//    
//    for(mach_msg_type_number_t i = 0; i < numThreads; i++)
//    {
//        mach_port_deallocate(thisTask, threads[i]);
//    }
//    vm_deallocate(thisTask, (vm_address_t)threads, sizeof(thread_t) * numThreads);
//    
//    XCTAssertTrue(success, @"");
//}

- (void) testThreadState
{
    TestThread* thread = [[TestThread alloc] init];
    [thread start];
    [NSThread sleepForTimeInterval:0.1];
    kern_return_t kr;
    kr = thread_suspend(thread.thread);
    XCTAssertTrue(kr == KERN_SUCCESS, @"");
    
    _STRUCT_MCONTEXT machineContext;
    bool success = ksmach_threadState(thread.thread, &machineContext);
    XCTAssertTrue(success, @"");

    int numRegisters = ksmach_numRegisters();
    for(int i = 0; i < numRegisters; i++)
    {
        const char* name = ksmach_registerName(i);
        XCTAssertTrue(name != NULL, @"Register %d was NULL", i);
        ksmach_registerValue(&machineContext, i);
    }

    const char* name = ksmach_registerName(1000000);
    XCTAssertTrue(name == NULL, @"");
    uint64_t value = ksmach_registerValue(&machineContext, 1000000);
    XCTAssertTrue(value == 0, @"");
    
    uintptr_t address;
    address = ksmach_framePointer(&machineContext);
    XCTAssertTrue(address != 0, @"");
    address = ksmach_stackPointer(&machineContext);
    XCTAssertTrue(address != 0, @"");
    address = ksmach_instructionAddress(&machineContext);
    XCTAssertTrue(address != 0, @"");

    thread_resume(thread.thread);
    [thread cancel];
}

- (void) testFloatState
{
    TestThread* thread = [[TestThread alloc] init];
    [thread start];
    [NSThread sleepForTimeInterval:0.1];
    kern_return_t kr;
    kr = thread_suspend(thread.thread);
    XCTAssertTrue(kr == KERN_SUCCESS, @"");
    
    _STRUCT_MCONTEXT machineContext;
    bool success = ksmach_floatState(thread.thread, &machineContext);
    XCTAssertTrue(success, @"");
    thread_resume(thread.thread);
    [thread cancel];
}

- (void) testExceptionState
{
    TestThread* thread = [[TestThread alloc] init];
    [thread start];
    [NSThread sleepForTimeInterval:0.1];
    kern_return_t kr;
    kr = thread_suspend(thread.thread);
    XCTAssertTrue(kr == KERN_SUCCESS, @"");
    
    _STRUCT_MCONTEXT machineContext;
    bool success = ksmach_exceptionState(thread.thread, &machineContext);
    XCTAssertTrue(success, @"");
    
    int numRegisters = ksmach_numExceptionRegisters();
    for(int i = 0; i < numRegisters; i++)
    {
        const char* name = ksmach_exceptionRegisterName(i);
        XCTAssertTrue(name != NULL, @"Register %d was NULL", i);
        ksmach_exceptionRegisterValue(&machineContext, i);
    }
    
    const char* name = ksmach_exceptionRegisterName(1000000);
    XCTAssertTrue(name == NULL, @"");
    uint64_t value = ksmach_exceptionRegisterValue(&machineContext, 1000000);
    XCTAssertTrue(value == 0, @"");

    ksmach_faultAddress(&machineContext);

    thread_resume(thread.thread);
    [thread cancel];
}

- (void) testStackGrowDirection
{
    ksmach_stackGrowDirection();
}

@end
