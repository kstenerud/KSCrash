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


#import <SenTestingKit/SenTestingKit.h>
#import "ARCSafe_MemMgmt.h"

#import "KSZombie.h"


@interface KSZombie_Tests : SenTestCase @end


@implementation KSZombie_Tests

- (void) setUp
{
    [super setUp];
    kszombie_install(32768);
}

- (void) tearDown
{
    kszombie_uninstall();
    [super tearDown];
}

- (void) testDoubleInstall
{
    kszombie_install(32768);
}

- (void) testDoubleUninstall
{
    kszombie_uninstall();
}

- (void) testNoLastDeallocedException
{
    const void* address = kszombie_lastDeallocedNSExceptionAddress();
    const uintptr_t* callStack = kszombie_lastDeallocedNSExceptionCallStack();
    size_t callStackLength = kszombie_lastDeallocedNSExceptionCallStackLength();
    const char* name = kszombie_lastDeallocedNSExceptionName();
    const char* reason = kszombie_lastDeallocedNSExceptionReason();
    
    STAssertTrue(address == NULL, @"");
    STAssertTrue((void*)callStack[0] == NULL, @"");
    STAssertTrue(callStackLength == 0, @"");
    STAssertTrue(name[0] == 0, @"");
    STAssertTrue(reason[0] == 0, @"");
}

- (void) testZombieClassNameNull
{
    const char* className = kszombie_className(NULL);
    STAssertTrue(className == NULL, @"");
}

- (void) testZombieClassNameNotFound
{
    const char* className = kszombie_className((void*)1);
    STAssertTrue(className == NULL, @"");
}

- (void) testZombieClass
{
    as_unsafe_unretained id object;
    as_autoreleasepool_start(POOL);
    {
        id anObject = as_autorelease([[NSObject alloc] init]);
        object = anObject;
    }
    as_autoreleasepool_end(POOL);
    
    const char* className = kszombie_className((as_bridge void*)object);
    STAssertTrue(strcmp(className, "NSObject") == 0, @"");
}

- (void) testZombieProxy
{
    as_unsafe_unretained id object;
    as_autoreleasepool_start(POOL);
    {
        id anObject = as_autorelease([NSProxy alloc]);
        object = anObject;
    }
    as_autoreleasepool_end(POOL);
    
    const char* className = kszombie_className((as_bridge void*)object);
    STAssertTrue(strcmp(className, "NSProxy") == 0, @"");
}

- (void) testZombieExeption
{
    as_unsafe_unretained id object;
    as_autoreleasepool_start(POOL);
    {
        @try {
            [NSException raise:@"name" format:@"reason"];
        }
        @catch (NSException* exception) {
            object = exception;
        }
    }
    as_autoreleasepool_end(POOL);
    
    const char* className = kszombie_className((as_bridge void*)object);
    STAssertTrue(strcmp(className, "NSException") == 0, @"");

    const void* address = kszombie_lastDeallocedNSExceptionAddress();
//    const uintptr_t* callStack = kszombie_lastDeallocedNSExceptionCallStack();
//    size_t callStackLength = kszombie_lastDeallocedNSExceptionCallStackLength();
    const char* name = kszombie_lastDeallocedNSExceptionName();
    const char* reason = kszombie_lastDeallocedNSExceptionReason();
    
    STAssertTrue(address == (as_bridge void*)object, @"");
//    STAssertTrue((void*)callStack[0] != NULL, @"");
//    STAssertTrue(callStackLength > 0, @"");
    STAssertTrue(strcmp(name, "name") == 0, @"");
    STAssertTrue(strcmp(reason, "reason") == 0, @"");
}

@end
