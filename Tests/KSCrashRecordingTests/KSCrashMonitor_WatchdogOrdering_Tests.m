//
//  KSCrashMonitor_WatchdogOrdering_Tests.m
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

#import "FileBasedTestCase.h"
#import "KSCrashMonitorContext.h"
#import "KSCrashMonitor_Lifecycle.h"
#import "KSCrashMonitor_Watchdog.h"

extern void kscm_watchdog_testcode_create(void);
extern void kscm_watchdog_testcode_begin(uint64_t timestamp);
extern void kscm_watchdog_testcode_reportReady(uint64_t timestamp, const char *path, bool deliver);
extern void kscm_watchdog_testcode_update(uint64_t endTimestamp);
extern void kscm_watchdog_testcode_recover(void);

static char g_orderingSidecarDirectory[PATH_MAX];

static bool orderingSidecarPath(const char *monitorId, char *buffer, size_t length)
{
    return snprintf(buffer, length, "%s/%s.ksscr", g_orderingSidecarDirectory, monitorId) < (int)length;
}

@interface KSCrashMonitor_WatchdogOrdering_Tests : FileBasedTestCase
@property(nonatomic, strong) NSMutableArray<NSNumber *> *events;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *timestamps;
@property(nonatomic, copy) void (^onChange)(KSHangChangeType change);
@property(nonatomic, copy) NSString *reportPath;
@property(nonatomic, assign) KSHangObserverToken observerToken;
@end

static void orderingObserver(KSHangChangeType change, uint64_t start, __unused uint64_t end, void *context)
{
    KSCrashMonitor_WatchdogOrdering_Tests *test = (__bridge id)context;
    @synchronized(test.events) {
        [test.events addObject:@(change)];
        [test.timestamps addObject:@(start)];
    }
    if (test.onChange) {
        test.onChange(change);
    }
}

@implementation KSCrashMonitor_WatchdogOrdering_Tests

- (void)setUp
{
    [super setUp];
    setenv("KSCRASH_FORCE_ENABLE_WATCHDOG", "1", 1);
    kscm_watchdog_getAPI()->setEnabled(false, NULL);
    kscm_lifecycle_getAPI()->setEnabled(false, NULL);
    strlcpy(g_orderingSidecarDirectory, self.tempPath.UTF8String, sizeof(g_orderingSidecarDirectory));
    KSCrash_ExceptionHandlerCallbacks callbacks = { .getRunSidecarPath = orderingSidecarPath };
    kscm_watchdog_getAPI()->init(&callbacks, NULL);
    kscm_watchdog_testcode_create();
    self.events = [NSMutableArray array];
    self.timestamps = [NSMutableArray array];
    self.reportPath = [self.tempPath stringByAppendingPathComponent:@"hang.json"];
    self.observerToken = kshang_addHangObserver(orderingObserver, (__bridge void *)self);

    // Register the real lifecycle observer after ours. Recovery during our
    // callback must not deliver Ended to lifecycle before its Started arrives.
    kscm_lifecycle_getAPI()->init(&callbacks, NULL);
    kscm_lifecycle_getAPI()->setEnabled(true, NULL);
    kscm_lifecycle_getAPI()->notifyPostSystemEnable(NULL);
}

- (void)tearDown
{
    self.onChange = nil;
    kscm_lifecycle_getAPI()->setEnabled(false, NULL);
    kscm_watchdog_getAPI()->setEnabled(false, NULL);
    KSCrash_ExceptionHandlerCallbacks callbacks = { 0 };
    kscm_watchdog_getAPI()->init(&callbacks, NULL);
    kscm_lifecycle_getAPI()->init(&callbacks, NULL);
    unsetenv("KSCRASH_FORCE_ENABLE_WATCHDOG");
    [super tearDown];
}

- (BOOL)lifecycleHangActive
{
    NSString *path = [self.tempPath stringByAppendingPathComponent:@"Lifecycle.ksscr"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertGreaterThanOrEqual(data.length, sizeof(KSCrash_LifecycleData));
    if (data.length < sizeof(KSCrash_LifecycleData)) {
        return NO;
    }
    KSCrash_LifecycleData lifecycle;
    [data getBytes:&lifecycle length:sizeof(lifecycle)];
    return lifecycle.hangActive != 0;
}

- (void)writeReport
{
    XCTAssertTrue([@"{}" writeToFile:self.reportPath atomically:YES encoding:NSUTF8StringEncoding error:nil]);
}

- (void)assertReportRemoved
{
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:self.reportPath]);
    XCTAssertFalse([[NSFileManager defaultManager]
        fileExistsAtPath:[self.tempPath stringByAppendingPathComponent:@"Watchdog.ksscr"]]);
}

- (void)testRecoveryBeforeReportAttachmentSuppressesBothNotifications
{
    kscm_watchdog_testcode_begin(100);
    [self writeReport];
    kscm_watchdog_testcode_recover();
    kscm_watchdog_testcode_reportReady(100, self.reportPath.UTF8String, true);
    XCTAssertEqual(self.events.count, 0U);
    XCTAssertFalse(self.lifecycleHangActive);
    [self assertReportRemoved];
}

- (void)testRecoveryAfterReservationDeliversStartedBeforeEnded
{
    kscm_watchdog_testcode_begin(100);
    [self writeReport];
    kscm_watchdog_testcode_reportReady(100, self.reportPath.UTF8String, false);
    // This is the unlock-to-callback gap from the review reproducer.
    kscm_watchdog_testcode_recover();
    XCTAssertEqualObjects(self.events, (@[ @(KSHangChangeTypeStarted), @(KSHangChangeTypeEnded) ]));
    XCTAssertFalse(self.lifecycleHangActive);
    [self assertReportRemoved];
}

- (void)exerciseRecoveryDuringDelivery:(KSHangChangeType)blockedChange
{
    kscm_watchdog_testcode_begin(100);
    [self writeReport];
    if (blockedChange == KSHangChangeTypeUpdated) {
        kscm_watchdog_testcode_reportReady(100, self.reportPath.UTF8String, true);
    }

    dispatch_semaphore_t entered = dispatch_semaphore_create(0);
    dispatch_semaphore_t resume = dispatch_semaphore_create(0);
    self.onChange = ^(KSHangChangeType change) {
        if (change == blockedChange) {
            dispatch_semaphore_signal(entered);
            dispatch_semaphore_wait(resume, DISPATCH_TIME_FOREVER);
        }
    };
    XCTestExpectation *finished = [self expectationWithDescription:@"notification delivery completed"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (blockedChange == KSHangChangeTypeUpdated) {
            kscm_watchdog_testcode_update(200);
        } else {
            kscm_watchdog_testcode_reportReady(100, self.reportPath.UTF8String, true);
        }
        [finished fulfill];
    });
    long arrived = dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    XCTAssertEqual(arrived, 0L);
    if (arrived == 0) {
        kscm_watchdog_testcode_recover();
        // Recovery and cleanup return while the observer remains blocked.
        @synchronized(self.events) {
            XCTAssertFalse([self.events containsObject:@(KSHangChangeTypeEnded)]);
        }
        [self assertReportRemoved];
    }
    dispatch_semaphore_signal(resume);
    [self waitForExpectations:@[ finished ] timeout:5];
    NSArray *expected = blockedChange == KSHangChangeTypeStarted
                            ? @[ @(KSHangChangeTypeStarted), @(KSHangChangeTypeEnded) ]
                            : @[ @(KSHangChangeTypeStarted), @(KSHangChangeTypeUpdated), @(KSHangChangeTypeEnded) ];
    XCTAssertEqualObjects(self.events, expected);
    XCTAssertFalse(self.lifecycleHangActive);
}

- (void)testRecoveryDuringStartedWaitsForTheWholeObserverBatch
{
    [self exerciseRecoveryDuringDelivery:KSHangChangeTypeStarted];
}

- (void)testRecoveryDuringUpdatedWaitsForTheWholeObserverBatch
{
    [self exerciseRecoveryDuringDelivery:KSHangChangeTypeUpdated];
}

- (void)testOldReportCannotAnnounceOrAttachToANewerHang
{
    kscm_watchdog_testcode_begin(100);
    [self writeReport];
    kscm_watchdog_testcode_recover();
    kscm_watchdog_testcode_begin(200);
    kscm_watchdog_testcode_reportReady(100, self.reportPath.UTF8String, true);
    XCTAssertEqual(self.events.count, 0U);
    [self assertReportRemoved];

    [self writeReport];
    kscm_watchdog_testcode_reportReady(200, self.reportPath.UTF8String, true);
    kscm_watchdog_testcode_recover();
    XCTAssertEqualObjects(self.events, (@[ @(KSHangChangeTypeStarted), @(KSHangChangeTypeEnded) ]));
    XCTAssertEqualObjects(self.timestamps, (@[ @200, @200 ]));
    XCTAssertFalse(self.lifecycleHangActive);
    [self assertReportRemoved];
}

- (void)testNewHangCannotOvertakeAnEndedObserverBatch
{
    __weak typeof(self) weakSelf = self;
    __block bool startedNext = false;
    self.onChange = ^(KSHangChangeType change) {
        if (change == KSHangChangeTypeEnded && !startedNext) {
            startedNext = true;
            kscm_watchdog_testcode_begin(200);
            typeof(self) strongSelf = weakSelf;
            [strongSelf writeReport];
            kscm_watchdog_testcode_reportReady(200, strongSelf.reportPath.UTF8String, true);
        }
    };
    kscm_watchdog_testcode_begin(100);
    [self writeReport];
    kscm_watchdog_testcode_reportReady(100, self.reportPath.UTF8String, true);
    kscm_watchdog_testcode_recover();
    XCTAssertTrue(self.lifecycleHangActive);
    kscm_watchdog_testcode_recover();
    XCTAssertEqualObjects(self.events, (@[ @1, @3, @1, @3 ]));
    XCTAssertEqualObjects(self.timestamps, (@[ @100, @100, @200, @200 ]));
    XCTAssertFalse(self.lifecycleHangActive);
    [self assertReportRemoved];
}

- (void)testObserverCanUnregisterDuringDelivery
{
    KSHangObserverToken token = self.observerToken;
    self.onChange = ^(__unused KSHangChangeType change) {
        kshang_removeHangObserver(token);
    };
    kscm_watchdog_testcode_begin(100);
    [self writeReport];
    kscm_watchdog_testcode_reportReady(100, self.reportPath.UTF8String, true);
    kscm_watchdog_testcode_recover();
    XCTAssertEqualObjects(self.events, (@[ @(KSHangChangeTypeStarted) ]));
    XCTAssertFalse(self.lifecycleHangActive);
}

- (void)testObserverCanDisableTheMonitorDuringDelivery
{
    self.onChange = ^(__unused KSHangChangeType change) {
        kscm_watchdog_getAPI()->setEnabled(false, NULL);
    };
    kscm_watchdog_testcode_begin(100);
    [self writeReport];
    kscm_watchdog_testcode_reportReady(100, self.reportPath.UTF8String, true);
    XCTAssertFalse(kscm_watchdog_getAPI()->isEnabled(NULL));
    XCTAssertEqualObjects(self.events, (@[ @(KSHangChangeTypeStarted) ]));
}

@end
