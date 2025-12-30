//
//  KSSpinLock_Tests.m
//
//  Created by Alexander Cohen on 2025-12-29.
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
#import <stdatomic.h>

#import "KSSpinLock.h"

@interface KSSpinLock_Tests : XCTestCase
@end

@implementation KSSpinLock_Tests

- (void)testStaticInitializer
{
    KSSpinLock lock = KSSPINLOCK_INIT;
    XCTAssertEqual(lock._opaque, 0);
}

- (void)testInit
{
    KSSpinLock lock;
    lock._opaque = 999;  // Set to non-zero
    ks_spinlock_init(&lock);
    XCTAssertEqual(lock._opaque, 0);
}

- (void)testLockUnlock
{
    KSSpinLock lock = KSSPINLOCK_INIT;
    ks_spinlock_lock(&lock);
    XCTAssertNotEqual(lock._opaque, 0);
    ks_spinlock_unlock(&lock);
    XCTAssertEqual(lock._opaque, 0);
}

- (void)testTryLockSuccess
{
    KSSpinLock lock = KSSPINLOCK_INIT;
    XCTAssertTrue(ks_spinlock_try_lock(&lock));
    XCTAssertNotEqual(lock._opaque, 0);
    ks_spinlock_unlock(&lock);
}

- (void)testTryLockFailure
{
    KSSpinLock lock = KSSPINLOCK_INIT;
    ks_spinlock_lock(&lock);
    XCTAssertFalse(ks_spinlock_try_lock(&lock));
    ks_spinlock_unlock(&lock);
}

- (void)testTryLockWithSpinSuccess
{
    KSSpinLock lock = KSSPINLOCK_INIT;
    XCTAssertTrue(ks_spinlock_try_lock_with_spin(&lock, 100));
    ks_spinlock_unlock(&lock);
}

- (void)testTryLockWithSpinFailure
{
    KSSpinLock lock = KSSPINLOCK_INIT;
    ks_spinlock_lock(&lock);
    XCTAssertFalse(ks_spinlock_try_lock_with_spin(&lock, 10));
    ks_spinlock_unlock(&lock);
}

- (void)testLockBoundedSuccess
{
    KSSpinLock lock = KSSPINLOCK_INIT;
    XCTAssertTrue(ks_spinlock_lock_bounded(&lock));
    ks_spinlock_unlock(&lock);
}

- (void)testLockBoundedFailure
{
    KSSpinLock lock = KSSPINLOCK_INIT;
    ks_spinlock_lock(&lock);
    XCTAssertFalse(ks_spinlock_lock_bounded(&lock));
    ks_spinlock_unlock(&lock);
}

- (void)testConcurrentAccess
{
    __block KSSpinLock lock = KSSPINLOCK_INIT;
    __block NSInteger counter = 0;
    const NSInteger iterations = 1000;
    const NSInteger threadCount = 10;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    for (NSInteger t = 0; t < threadCount; t++) {
        dispatch_group_async(group, queue, ^{
            for (NSInteger i = 0; i < iterations; i++) {
                ks_spinlock_lock(&lock);
                counter++;
                ks_spinlock_unlock(&lock);
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    XCTAssertEqual(counter, iterations * threadCount);
}

- (void)testConcurrentTryLock
{
    __block KSSpinLock lock = KSSPINLOCK_INIT;
    __block NSInteger counter = 0;                   // Protected by lock
    __block _Atomic(NSInteger) tryLockFailures = 0;  // Not protected, needs atomic
    const NSInteger iterations = 1000;
    const NSInteger threadCount = 10;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    for (NSInteger t = 0; t < threadCount; t++) {
        dispatch_group_async(group, queue, ^{
            for (NSInteger i = 0; i < iterations; i++) {
                if (ks_spinlock_try_lock(&lock)) {
                    counter++;
                    ks_spinlock_unlock(&lock);
                } else {
                    atomic_fetch_add(&tryLockFailures, 1);
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    NSInteger finalFailures = atomic_load(&tryLockFailures);

    // With try_lock, we expect some operations to succeed and some to fail
    XCTAssertGreaterThan(counter, 0);
    XCTAssertGreaterThan(finalFailures, 0);
    XCTAssertEqual(counter + finalFailures, iterations * threadCount);
}

- (void)testConcurrentBoundedLock
{
    __block KSSpinLock lock = KSSPINLOCK_INIT;
    __block NSInteger counter = 0;
    const NSInteger iterations = 1000;
    const NSInteger threadCount = 10;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    for (NSInteger t = 0; t < threadCount; t++) {
        dispatch_group_async(group, queue, ^{
            for (NSInteger i = 0; i < iterations; i++) {
                if (ks_spinlock_lock_bounded(&lock)) {
                    counter++;
                    ks_spinlock_unlock(&lock);
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // With bounded lock and 50K iterations, all should succeed
    XCTAssertEqual(counter, iterations * threadCount);
}

@end
