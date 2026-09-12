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
    [thread start];

    // Poll until the cache reports the name the thread was given (up to 10 s).
    // NSThread applies the name as the thread starts, and the cache reads it
    // with pthread_getname_np from another thread, so a read that wins that
    // race sees the name absent or part way written. Only the settled value
    // answers the question, so stopping at the first non-NULL read is what
    // made this test fail on a loaded machine with a truncated name.
    NSString *name = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    for (;;) {
        kstc_freeze();
        const char *cName = kstc_getThreadName(thread.thread);
        // Copy while frozen; the cache owns the buffer.
        name = cName != NULL ? [NSString stringWithUTF8String:cName] : nil;
        kstc_unfreeze();
        if ([name isEqualToString:expectedName] || [deadline timeIntervalSinceNow] <= 0) {
            break;
        }
        [NSThread sleepForTimeInterval:0.05];
    }

    XCTAssertEqualObjects(name, expectedName, @"Thread name didn't match expected name");

    [thread cancel];
}

@end
