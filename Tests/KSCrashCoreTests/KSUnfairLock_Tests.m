//
//  KSUnfairLock_Tests.m
//
//  Created by Alexander Cohen on 2025-12-07.
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

#import "KSUnfairLock.h"

@interface KSUnfairLock_Tests : XCTestCase
@end

@implementation KSUnfairLock_Tests

- (void)testInit
{
    KSUnfairLock *lock = [[KSUnfairLock alloc] init];
    XCTAssertNotNil(lock);
}

- (void)testLockUnlock
{
    KSUnfairLock *lock = [[KSUnfairLock alloc] init];
    [lock lock];
    [lock unlock];
}

- (void)testWithLock
{
    KSUnfairLock *lock = [[KSUnfairLock alloc] init];
    __block BOOL blockExecuted = NO;
    [lock withLock:^{
        blockExecuted = YES;
    }];
    XCTAssertTrue(blockExecuted);
}

- (void)testNSLockingProtocol
{
    KSUnfairLock *lock = [[KSUnfairLock alloc] init];
    XCTAssertTrue([lock conformsToProtocol:@protocol(NSLocking)]);
}

- (void)testConcurrentAccess
{
    KSUnfairLock *lock = [[KSUnfairLock alloc] init];
    __block NSInteger counter = 0;
    const NSInteger iterations = 1000;
    const NSInteger threadCount = 10;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    for (NSInteger t = 0; t < threadCount; t++) {
        dispatch_group_async(group, queue, ^{
            for (NSInteger i = 0; i < iterations; i++) {
                [lock lock];
                counter++;
                [lock unlock];
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    XCTAssertEqual(counter, iterations * threadCount);
}

- (void)testConcurrentAccessWithBlock
{
    KSUnfairLock *lock = [[KSUnfairLock alloc] init];
    __block NSInteger counter = 0;
    const NSInteger iterations = 1000;
    const NSInteger threadCount = 10;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    for (NSInteger t = 0; t < threadCount; t++) {
        dispatch_group_async(group, queue, ^{
            for (NSInteger i = 0; i < iterations; i++) {
                [lock withLock:^{
                    counter++;
                }];
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    XCTAssertEqual(counter, iterations * threadCount);
}

@end
