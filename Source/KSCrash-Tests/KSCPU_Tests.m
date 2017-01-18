//
//  KSCPU_Tests.m
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

#import "KSCPU.h"
#import "KSMachineContext.h"
#import "TestThread.h"

#import <mach/mach.h>


@interface KSCPU_Tests : XCTestCase @end

@implementation KSCPU_Tests

- (void) testCPUState
{
    TestThread* thread = [[TestThread alloc] init];
    [thread start];
    [NSThread sleepForTimeInterval:0.1];
    kern_return_t kr;
    kr = thread_suspend(thread.thread);
    XCTAssertTrue(kr == KERN_SUCCESS, @"");
    
    KSMC_NEW_CONTEXT(machineContext);
    ksmc_getContextForThread(thread.thread, machineContext, NO);
    kscpu_getState(machineContext);
    
    int numRegisters = kscpu_numRegisters();
    for(int i = 0; i < numRegisters; i++)
    {
        const char* name = kscpu_registerName(i);
        XCTAssertTrue(name != NULL, @"Register %d was NULL", i);
        kscpu_registerValue(machineContext, i);
    }
    
    const char* name = kscpu_registerName(1000000);
    XCTAssertTrue(name == NULL, @"");
    uint64_t value = kscpu_registerValue(machineContext, 1000000);
    XCTAssertTrue(value == 0, @"");

    uintptr_t address;
    address = kscpu_framePointer(machineContext);
    XCTAssertTrue(address != 0, @"");
    address = kscpu_stackPointer(machineContext);
    XCTAssertTrue(address != 0, @"");
    address = kscpu_instructionAddress(machineContext);
    XCTAssertTrue(address != 0, @"");

    numRegisters = kscpu_numExceptionRegisters();
    for(int i = 0; i < numRegisters; i++)
    {
        name = kscpu_exceptionRegisterName(i);
        XCTAssertTrue(name != NULL, @"Register %d was NULL", i);
        kscpu_exceptionRegisterValue(machineContext, i);
    }
    
    name = kscpu_exceptionRegisterName(1000000);
    XCTAssertTrue(name == NULL, @"");
    value = kscpu_exceptionRegisterValue(machineContext, 1000000);
    XCTAssertTrue(value == 0, @"");
    
    kscpu_faultAddress(machineContext);

    thread_resume(thread.thread);
    [thread cancel];
}

- (void) testStackGrowDirection
{
    kscpu_stackGrowDirection();
}

@end
