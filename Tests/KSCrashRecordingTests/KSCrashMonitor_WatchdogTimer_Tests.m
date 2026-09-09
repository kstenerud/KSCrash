//
//  KSCrashMonitor_WatchdogTimer_Tests.m
//
//  Created by Alexander Cohen on 2025-01-04.
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

#import "KSCrashNamespace.h"
#import "KSLogger.h"

// The included C implementation uses C string literals for log messages.
#undef i_KSLOG_FULL
#define i_KSLOG_FULL(LEVEL, FILE, LINE, FUNCTION, FMT, ...) \
    i_kslog_logObjC(LEVEL, FILE, LINE, FUNCTION, CFSTR(FMT), ##__VA_ARGS__)

// Compile a private copy to pause the real timer callback before its state
// lock, without adding test hooks or branches to the shipping watchdog.
#undef kscm_watchdog_getAPI
#undef kscm_watchdog_setReportsHangs
#undef kshang_addHangObserver
#undef kshang_removeHangObserver
#undef kstaskrole_current
#define kscm_watchdog_getAPI watchdogTimerTests_getAPI
#define kscm_watchdog_setReportsHangs watchdogTimerTests_setReportsHangs
#define kshang_addHangObserver watchdogTimerTests_addHangObserver
#define kshang_removeHangObserver watchdogTimerTests_removeHangObserver
#define kstaskrole_current watchdogTimerTests_currentRole
#include "../../Sources/KSCrashRecording/Monitors/KSCrashMonitor_Watchdog.c"

static void (^g_beforeTimerStateChange)(void);

int watchdogTimerTests_currentRole(void)
{
    void (^beforeStateChange)(void) = g_beforeTimerStateChange;
    g_beforeTimerStateChange = nil;
    if (beforeStateChange) {
        beforeStateChange();
    }
    return TASK_FOREGROUND_APPLICATION;
}

static void startTestInterval(KSHangMonitor *monitor)
{
    monitor->lock = (os_unfair_lock)OS_UNFAIR_LOCK_INIT;
    monitor->watchdogRunLoop = CFRunLoopGetCurrent();
    // Invoke callbacks directly; the registered timer must not fire by itself.
    monitor->threshold = 3600;
    monitor->thresholdNs = 0;
    schedulePings(monitor);
}

@interface KSCrashMonitor_WatchdogTimer_Tests : XCTestCase
@end

@implementation KSCrashMonitor_WatchdogTimer_Tests

- (void)fireTimer:(KSHangMonitor *)monitor whilePaused:(void (^)(KSHangMonitor *))mainThreadWork
{
    dispatch_semaphore_t reached = dispatch_semaphore_create(0);
    dispatch_semaphore_t resume = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_queue_create("watchdog.timer.test", DISPATCH_QUEUE_SERIAL);
    g_beforeTimerStateChange = ^{
        dispatch_semaphore_signal(reached);
        dispatch_semaphore_wait(resume, DISPATCH_TIME_FOREVER);
    };

    // The run loop retains a timer while invoking its callback. Model that
    // ownership while BeforeWaiting invalidates and releases the monitor's ref.
    CFRunLoopTimerRef timer = (CFRunLoopTimerRef)CFRetain(monitor->watchdogTimer);
    dispatch_async(queue, ^{
        watchdogTimerFired(timer, monitor);
        CFRelease(timer);
    });

    long result = dispatch_semaphore_wait(reached, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    XCTAssertEqual(result, 0, @"Timer must pause after reading enterTime and before taking the state lock");
    if (result == 0) {
        mainThreadWork(monitor);
    }
    dispatch_semaphore_signal(resume);
    // Join before reading state or returning the stack-allocated monitor.
    dispatch_sync(queue, ^ {
                  });
}

- (void)testInFlightTimerCannotRestartResolvedHang
{
    KSHangMonitor monitor = { 0 };
    startTestInterval(&monitor);
    kshangstate_init(&monitor.hang, atomic_load(&monitor.enterTime), TASK_FOREGROUND_APPLICATION,
                     KSCrashAppTransitionStateActive);

    [self fireTimer:&monitor
        whilePaused:^(KSHangMonitor *pausedMonitor) {
            mainRunLoopActivity(NULL, kCFRunLoopBeforeWaiting, pausedMonitor);
            XCTAssertFalse(pausedMonitor->hang.active);
        }];

    XCTAssertFalse(monitor.hang.active, @"An in-flight callback must not restart the resolved hang");
    XCTAssertEqual(atomic_load(&monitor.enterTime), 0ULL);
}

- (void)testInFlightTimerCannotStartHangAfterAnUnhungIntervalEnds
{
    KSHangMonitor monitor = { 0 };
    startTestInterval(&monitor);

    [self fireTimer:&monitor
        whilePaused:^(KSHangMonitor *pausedMonitor) {
            mainRunLoopActivity(NULL, kCFRunLoopBeforeWaiting, pausedMonitor);
        }];

    XCTAssertFalse(monitor.hang.active, @"Going idle must close intervals even when no hang was active");
}

- (void)testInFlightTimerCannotStartHangForAnOlderIntervalAfterWaking
{
    KSHangMonitor monitor = { 0 };
    startTestInterval(&monitor);
    uint64_t oldEnter = atomic_load(&monitor.enterTime);

    [self fireTimer:&monitor
        whilePaused:^(KSHangMonitor *pausedMonitor) {
            mainRunLoopActivity(NULL, kCFRunLoopBeforeWaiting, pausedMonitor);
            mainRunLoopActivity(NULL, kCFRunLoopAfterWaiting, pausedMonitor);
        }];

    uint64_t newEnter = atomic_load(&monitor.enterTime);
    XCTAssertGreaterThan(newEnter, oldEnter);
    XCTAssertFalse(monitor.hang.active, @"The old callback must not carry its timestamp into the new interval");

    watchdogTimerFired(monitor.watchdogTimer, &monitor);
    XCTAssertTrue(monitor.hang.active, @"The new interval must still be able to detect a hang");
    XCTAssertEqual(monitor.hang.timestamp, newEnter);
    mainRunLoopActivity(NULL, kCFRunLoopBeforeWaiting, &monitor);
}

- (void)testCallbackThatStartsWhileIdleDoesNotDetectHang
{
    KSHangMonitor monitor = { 0 };
    startTestInterval(&monitor);
    mainRunLoopActivity(NULL, kCFRunLoopBeforeWaiting, &monitor);

    watchdogTimerFired(NULL, &monitor);

    XCTAssertFalse(monitor.hang.active);
}

- (void)testCurrentIntervalStillStartsAndUpdatesHang
{
    KSHangMonitor monitor = { 0 };
    startTestInterval(&monitor);
    uint64_t enter = atomic_load(&monitor.enterTime);

    watchdogTimerFired(monitor.watchdogTimer, &monitor);
    XCTAssertTrue(monitor.hang.active);
    XCTAssertEqual(monitor.hang.timestamp, enter);
    uint64_t previousEnd = monitor.hang.endTimestamp;

    watchdogTimerFired(monitor.watchdogTimer, &monitor);
    XCTAssertEqual(monitor.hang.timestamp, enter);
    XCTAssertGreaterThanOrEqual(monitor.hang.endTimestamp, previousEnd);
    mainRunLoopActivity(NULL, kCFRunLoopBeforeWaiting, &monitor);
}

@end
