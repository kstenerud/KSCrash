//
//  KSThreadCache_Tests.m
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

#import "KSThreadCache.h"
#import "TestThread.h"

// Declare external function only for testing
extern void kstc_reset(void);

@interface KSThreadCache_Tests : XCTestCase
@end

@implementation KSThreadCache_Tests

- (void)setUp
{
    [super setUp];
    kstc_reset();
}

- (void)testGetThreadName
{
    NSString *expectedName = @"This is a test thread";
    TestThread *thread = [TestThread new];
    thread.name = expectedName;

    kstc_init(1);
    [NSThread sleepForTimeInterval:0.5];
    [thread start];
    [NSThread sleepForTimeInterval:1.0];
    kstc_freeze();

    const char *cName = kstc_getThreadName(thread.thread);

    if (cName != NULL) {
        NSString *name = [NSString stringWithUTF8String:cName];
        XCTAssertEqualObjects(name, expectedName, @"Thread name didn't match expected name");
    } else {
        XCTFail(@"Failed to get thread name (got NULL)");
    }

    [thread cancel];
    kstc_unfreeze();
}

@end
