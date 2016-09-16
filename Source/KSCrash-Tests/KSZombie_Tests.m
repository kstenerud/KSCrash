//
//  KSZombie_Tests.m
//
//  Created by Karl Stenerud on 2013-01-26.
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

#import "KSZombie.h"


@interface KSZombie_Tests : XCTestCase @end


@implementation KSZombie_Tests

- (void) setUp
{
    [super setUp];
    kszombie_install();
}

- (void) tearDown
{
    [super tearDown];
}

- (void) testDoubleInstall
{
    kszombie_install();
}

- (void) testNoLastDeallocedException
{
    const void* address = kszombie_lastDeallocedNSExceptionAddress();
    const char* name = kszombie_lastDeallocedNSExceptionName();
    const char* reason = kszombie_lastDeallocedNSExceptionReason();
    
    XCTAssertTrue(address == NULL, @"");
    XCTAssertTrue(name[0] == 0, @"");
    XCTAssertTrue(reason[0] == 0, @"");
}

- (void) testZombieClassNameNull
{
    const char* className = kszombie_className(NULL);
    XCTAssertTrue(className == NULL, @"");
}

- (void) testZombieClassNameNotFound
{
    // TODO: Figure out why this causes an endless call loop.
//    const char* className = kszombie_className((void*)1);
//    XCTAssertTrue(className == NULL, @"");
}

- (void) testZombieClass
{
    __unsafe_unretained id object;
    @autoreleasepool {
        id anObject = [[NSObject alloc] init];
        object = anObject;
    }
    
    const char* className = kszombie_className((__bridge void*)object);
    XCTAssertTrue(strcmp(className, "NSObject") == 0, @"");
}

- (void) testZombieProxy
{
    __unsafe_unretained id object;
    @autoreleasepool {
        id anObject = [NSProxy alloc];
        object = anObject;
    }
    
    const char* className = kszombie_className((__bridge void*)object);
    XCTAssertTrue(strcmp(className, "NSProxy") == 0, @"");
}

- (void) testZombieExeption
{
    __unsafe_unretained id object;
    @autoreleasepool {
        @try {
            [NSException raise:@"name" format:@"reason"];
        }
        @catch (NSException* exception) {
            object = exception;
        }
    }
    
    const char* className = kszombie_className((__bridge void*)object);
    XCTAssertTrue(strcmp(className, "NSException") == 0, @"");

    const void* address = kszombie_lastDeallocedNSExceptionAddress();
    const char* name = kszombie_lastDeallocedNSExceptionName();
    const char* reason = kszombie_lastDeallocedNSExceptionReason();
    
    XCTAssertTrue(address == (__bridge void*)object, @"");
    XCTAssertTrue(strcmp(name, "name") == 0, @"");
    XCTAssertTrue(strcmp(reason, "reason") == 0, @"");
}

@end
