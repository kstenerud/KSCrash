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
#import "TestThread.h"


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
    
    int copied = ksmach_copyMaxPossibleMem(buff2, buff, sizeof(buff));
    XCTAssertTrue(copied >= 5, @"");
    int memCmpResult = memcmp(buff, buff2, sizeof(buff2));
    XCTAssertEqual(memCmpResult, 0, @"");
}

- (void) testCopyMaxPossibleMemNull
{
    char buff[1000];
    char* buff2 = NULL;
    
    int copied = ksmach_copyMaxPossibleMem(buff2, buff, sizeof(buff));
    XCTAssertTrue(copied == 0, @"");
}

- (void) testCopyMaxPossibleMemBad
{
    char buff[1000];
    char* buff2 = (char*)-1;
    
    int copied = ksmach_copyMaxPossibleMem(buff2, buff, sizeof(buff));
    XCTAssertTrue(copied == 0, @"");
}

- (void) testIsBeingTraced
{
    bool traced = ksmach_isBeingTraced();
    XCTAssertTrue(traced, @"");
}

@end
