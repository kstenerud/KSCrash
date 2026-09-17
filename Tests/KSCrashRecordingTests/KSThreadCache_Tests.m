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

- (void)tearDown
{
    // The cache and the queue-name flag are process globals, and the polling
    // thread outlives this class. Leaving the flag on means every later
    // rebuild in the bundle reads queue names off threads other tests are
    // tearing down, which faults in ksthread_getQueueName.
    kstc_reset();
    [super tearDown];
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

- (void)testQueueNameSearchSetBeforeInitIsHonored
{
    // The install sets the flag before init, and init used to discard it, so no
    // cache ever searched queue names. This cannot tell the initial cache apart
    // from a later rebuild: the monitor re-reads the flag every cycle and polls
    // once a second for its first few, so there is no window in which only the
    // initial cache has answered.
    dispatch_queue_t queue = dispatch_queue_create("com.kscrash.tests.queue-name", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t parked = dispatch_semaphore_create(0);
    dispatch_semaphore_t release = dispatch_semaphore_create(0);
    __block thread_t queueThread = MACH_PORT_NULL;
    dispatch_async(queue, ^{
        queueThread = mach_thread_self();
        dispatch_semaphore_signal(parked);
        dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER);
    });
    XCTAssertEqual(dispatch_semaphore_wait(parked, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0L);

    kstc_setSearchQueueNames(true);
    kstc_init(3600);

    // Poll until the cache reports the queue name (up to 10 s). freeze() gives
    // up after one brief retry and leaves the caller with no cache at all, and
    // a monitor thread holds the cache while it rebuilds, so a single read can
    // come back NULL while queue-name search is working perfectly. Only a read
    // that got a cache answers the question. The flag is what is under test: if
    // init discarded it, every rebuild reads it as false and the name never
    // appears, so this still fails at the deadline.
    NSString *name = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    for (;;) {
        kstc_freeze();
        const char *cName = kstc_getQueueName((KSThread)queueThread);
        // Copy while frozen; the cache owns the buffer.
        name = cName != NULL ? [NSString stringWithUTF8String:cName] : nil;
        kstc_unfreeze();
        if (name != nil || [deadline timeIntervalSinceNow] <= 0) {
            break;
        }
        [NSThread sleepForTimeInterval:0.05];
    }

    XCTAssertEqualObjects(name, @"com.kscrash.tests.queue-name");

    dispatch_semaphore_signal(release);
    mach_port_deallocate(mach_task_self(), queueThread);
}

@end
