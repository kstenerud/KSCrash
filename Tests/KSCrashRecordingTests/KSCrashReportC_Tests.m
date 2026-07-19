//
//  KSCrashReportC_Tests.m
//
//  Created by Alexander Cohen on 2025-12-27.
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

#import "KSCrashMonitor_MachException.h"
#import "KSCrashReportC.h"
#import "KSMachineContext.h"
#import "KSStackCursor_SelfThread.h"

#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>

@interface KSCrashReportC_Tests : XCTestCase
@end

@implementation KSCrashReportC_Tests

- (void)setUp
{
    [super setUp];
    // Clear any existing userInfo before each test
    kscrashreport_setUserInfoJSON(NULL);
}

- (void)tearDown
{
    // Clean up after each test
    kscrashreport_setUserInfoJSON(NULL);
    [super tearDown];
}

- (NSString *)temporaryReportPath
{
    return [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"kscrash-report-%@.json", [NSUUID UUID].UUIDString]];
}

- (NSDictionary *)readJSONObjectAtPath:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data);
    if (data == nil) {
        return nil;
    }

    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    return json;
}

#pragma mark - Basic Functionality Tests

- (void)testSetAndGetUserInfo
{
    const char *testJSON = "{\"key\":\"value\"}";
    kscrashreport_setUserInfoJSON(testJSON);

    const char *result = kscrashreport_getUserInfoJSON();
    XCTAssertNotEqual(result, NULL, @"getUserInfoJSON should return non-NULL after setting");
    XCTAssertTrue(strcmp(result, testJSON) == 0, @"Retrieved JSON should match set JSON");
    free((void *)result);
}

- (void)testSetNullClearsUserInfo
{
    const char *testJSON = "{\"key\":\"value\"}";
    kscrashreport_setUserInfoJSON(testJSON);

    kscrashreport_setUserInfoJSON(NULL);

    const char *result = kscrashreport_getUserInfoJSON();
    XCTAssertEqual(result, NULL, @"getUserInfoJSON should return NULL after setting NULL");
}

- (void)testGetUserInfoReturnsNewCopy
{
    const char *testJSON = "{\"key\":\"value\"}";
    kscrashreport_setUserInfoJSON(testJSON);

    const char *result1 = kscrashreport_getUserInfoJSON();
    const char *result2 = kscrashreport_getUserInfoJSON();

    XCTAssertNotEqual(result1, result2, @"Each call should return a new copy");
    XCTAssertTrue(strcmp(result1, result2) == 0, @"Both copies should have same content");

    free((void *)result1);
    free((void *)result2);
}

#pragma mark - Contention Tests

/**
 * Test concurrent set/get operations under moderate contention.
 * Validates that operations complete without deadlock and data remains consistent.
 */
- (void)testConcurrentSetGet
{
    const int kNumThreads = 4;
    const int kIterationsPerThread = 100;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("test.concurrent", DISPATCH_QUEUE_CONCURRENT);

    __block atomic_int successfulSets = 0;
    __block atomic_int successfulGets = 0;
    __block atomic_int skippedGets = 0;

    for (int t = 0; t < kNumThreads; t++) {
        dispatch_group_async(group, queue, ^{
            char jsonBuffer[64];

            for (int i = 0; i < kIterationsPerThread; i++) {
                // Alternate between set and get operations
                if (i % 2 == 0) {
                    snprintf(jsonBuffer, sizeof(jsonBuffer), "{\"thread\":%d,\"iter\":%d}", t, i);
                    kscrashreport_setUserInfoJSON(jsonBuffer);
                    atomic_fetch_add(&successfulSets, 1);
                } else {
                    const char *result = kscrashreport_getUserInfoJSON();
                    if (result != NULL) {
                        atomic_fetch_add(&successfulGets, 1);
                        free((void *)result);
                    } else {
                        atomic_fetch_add(&skippedGets, 1);
                    }
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    // Verify no deadlock occurred (we reached this point)
    int totalSets = atomic_load(&successfulSets);
    int totalGets = atomic_load(&successfulGets);
    int totalSkipped = atomic_load(&skippedGets);

    XCTAssertEqual(totalSets, kNumThreads * kIterationsPerThread / 2, @"All set operations should complete");
    XCTAssertEqual(totalGets + totalSkipped, kNumThreads * kIterationsPerThread / 2,
                   @"All get operations should complete (successfully or skipped)");

    NSLog(@"Concurrent test: %d sets, %d successful gets, %d skipped gets", totalSets, totalGets, totalSkipped);
}

/**
 * Test high contention scenario with many threads competing for access.
 * Under extreme contention, the skip behavior should kick in.
 */
- (void)testHighContentionSkipBehavior
{
    const int kNumThreads = 16;
    const int kIterationsPerThread = 500;

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("test.highContention", DISPATCH_QUEUE_CONCURRENT);

    __block atomic_int totalOperations = 0;
    __block atomic_int skippedGets = 0;

    // Set an initial value
    kscrashreport_setUserInfoJSON("{\"initial\":true}");

    for (int t = 0; t < kNumThreads; t++) {
        dispatch_group_async(group, queue, ^{
            char jsonBuffer[64];

            for (int i = 0; i < kIterationsPerThread; i++) {
                // Rapid fire set/get operations to create contention
                snprintf(jsonBuffer, sizeof(jsonBuffer), "{\"t\":%d,\"i\":%d}", t, i);
                kscrashreport_setUserInfoJSON(jsonBuffer);
                atomic_fetch_add(&totalOperations, 1);

                const char *result = kscrashreport_getUserInfoJSON();
                atomic_fetch_add(&totalOperations, 1);
                if (result != NULL) {
                    free((void *)result);
                } else {
                    atomic_fetch_add(&skippedGets, 1);
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    int total = atomic_load(&totalOperations);
    int skipped = atomic_load(&skippedGets);

    // Under high contention, we expect some skips, but the system should remain stable
    XCTAssertEqual(total, kNumThreads * kIterationsPerThread * 2, @"All operations should attempt to complete");

    NSLog(@"High contention test: %d total operations, %d skipped gets (%.2f%%)", total, skipped,
          (double)skipped / (kNumThreads * kIterationsPerThread) * 100.0);

    // Verify that after contention subsides, operations work normally
    const char *testJSON = "{\"postContention\":true}";
    kscrashreport_setUserInfoJSON(testJSON);
    const char *result = kscrashreport_getUserInfoJSON();
    XCTAssertNotEqual(result, NULL, @"Operations should work normally after contention subsides");
    if (result != NULL) {
        XCTAssertTrue(strcmp(result, testJSON) == 0, @"Value should be correctly set after contention");
        free((void *)result);
    }
}

/**
 * Test that rapid successive sets don't cause issues.
 */
- (void)testRapidSuccessiveSets
{
    const int kIterations = 1000;

    for (int i = 0; i < kIterations; i++) {
        char jsonBuffer[64];
        snprintf(jsonBuffer, sizeof(jsonBuffer), "{\"iteration\":%d}", i);
        kscrashreport_setUserInfoJSON(jsonBuffer);
    }

    // Final value should be set correctly
    char expectedJSON[64];
    snprintf(expectedJSON, sizeof(expectedJSON), "{\"iteration\":%d}", kIterations - 1);

    const char *result = kscrashreport_getUserInfoJSON();
    XCTAssertNotEqual(result, NULL, @"Should have a value set");
    if (result != NULL) {
        XCTAssertTrue(strcmp(result, expectedJSON) == 0, @"Last set value should persist");
        free((void *)result);
    }
}

static dispatch_semaphore_t g_overflowWorkerReady;
static dispatch_semaphore_t g_overflowWorkerRelease;
static thread_t g_overflowWorkerThread;

static void *overflowWorkerMain(__unused void *arg)
{
    g_overflowWorkerThread = pthread_mach_thread_np(pthread_self());
    dispatch_semaphore_signal(g_overflowWorkerReady);
    dispatch_semaphore_wait(g_overflowWorkerRelease, DISPATCH_TIME_FOREVER);
    return NULL;
}

- (void)testStackOverflowFieldReportsTheContextVerdictNotCursorTruncation
{
#if KSCRASH_HAS_MACH
    // crash.threads[].stack.overflow is consumed as "the stack overflowed": KSCrashDoctor
    // diagnoses a stack overflow from it and the report model documents it that way. It must
    // therefore come from the machine context's verdict, not from whether the backtrace cursor
    // stopped early, which is a different question asked at a threshold that varies by path
    // (the crashed thread's pre-captured cursor uses KSSC_MAX_STACK_DEPTH, everything else uses
    // KSSC_STACK_OVERFLOW_THRESHOLD).
    ksdl_init();

    // A suspended second thread, because the stack dump needs readable registers and you cannot
    // read CPU state for the thread doing the reading.
    g_overflowWorkerReady = dispatch_semaphore_create(0);
    g_overflowWorkerRelease = dispatch_semaphore_create(0);
    g_overflowWorkerThread = MACH_PORT_NULL;
    pthread_t worker;
    XCTAssertEqual(pthread_create(&worker, NULL, overflowWorkerMain, NULL), 0);
    dispatch_semaphore_wait(g_overflowWorkerReady, DISPATCH_TIME_FOREVER);
    usleep(10000);
    XCTAssertEqual(thread_suspend(g_overflowWorkerThread), KERN_SUCCESS);

    NSString *path = [self temporaryReportPath];
    @try {
        struct KSMachineContext machineContext = { 0 };
        XCTAssertTrue(ksmc_getContextForThread(g_overflowWorkerThread, &machineContext, true));
        XCTAssertFalse(machineContext.isStackOverflow, @"a parked worker has not overflowed its stack");

        // A cursor that has given up. If the report took its value from here it would claim the
        // stack overflowed, which is exactly the conflation being removed.
        KSStackCursor stackCursor;
        kssc_initWithUnwind(&stackCursor, KSSC_MAX_STACK_DEPTH, &machineContext);
        stackCursor.state.hasGivenUp = true;

        KSCrash_MonitorContext context = { 0 };
        snprintf(context.eventID, sizeof(context.eventID), "OVERFLOWFIELDTEST");
        context.offendingMachineContext = &machineContext;
        context.stackCursor = &stackCursor;
        context.registersAreValid = true;
        context.omitBinaryImages = true;
        context.monitorId = kscm_machexception_getAPI()->monitorId(NULL);
        context.mach.type = EXC_BAD_ACCESS;

        kscrashreport_writeStandardReport(&context, path.UTF8String);

        NSDictionary *json = [self readJSONObjectAtPath:path];
        NSArray *threads = json[@"crash"][@"threads"];
        NSDictionary *stack = nil;
        for (NSDictionary *t in threads) {
            if ([t[@"crashed"] boolValue]) {
                stack = t[@"stack"];
                break;
            }
        }
        XCTAssertNotNil(stack, @"the crashed thread must carry a stack dump");
        XCTAssertEqualObjects(stack[@"overflow"], @NO,
                              @"overflow must follow the machine context, not the cursor giving up");
    } @finally {
        thread_resume(g_overflowWorkerThread);
        dispatch_semaphore_signal(g_overflowWorkerRelease);
        pthread_join(worker, NULL);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
#endif
}

- (void)testWriteStandardReportPreserves64BitMachCodeAndSubcode
{
#if KSCRASH_HAS_MACH
    struct KSMachineContext machineContext = { 0 };
    XCTAssertTrue(ksmc_getContextForThread(pthread_mach_thread_np(pthread_self()), &machineContext, true));

    KSStackCursor stackCursor;
    kssc_initSelfThread(&stackCursor, 0);

    KSCrash_MonitorContext context = { 0 };
    snprintf(context.eventID, sizeof(context.eventID), "MACHCODETEST");
    context.offendingMachineContext = &machineContext;
    context.stackCursor = &stackCursor;
    context.registersAreValid = true;
    context.omitBinaryImages = true;
    context.monitorId = kscm_machexception_getAPI()->monitorId(NULL);
    context.crashReason = "Mach code serialization test";
    context.faultAddress = (uintptr_t)0xDEADBEEF;
    context.mach.type = EXC_BAD_ACCESS;
    context.mach.code = INT64_C(0x123456789ABCDEF0);
    context.mach.subcode = INT64_C(0x7EEDFACEDEADBEEF);
    context.signal.signum = SIGBUS;

    NSString *path = [self temporaryReportPath];
    @try {
        kscrashreport_writeStandardReport(&context, path.UTF8String);

        NSDictionary *json = [self readJSONObjectAtPath:path];
        NSDictionary *crash = json[@"crash"];
        NSDictionary *error = crash[@"error"];
        NSDictionary *mach = error[@"mach"];

        XCTAssertEqual([mach[@"code"] unsignedLongLongValue], UINT64_C(0x123456789ABCDEF0));
        XCTAssertEqual([mach[@"subcode"] unsignedLongLongValue], UINT64_C(0x7EEDFACEDEADBEEF));
    } @finally {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
#endif
}

/**
 * Test concurrent reads don't interfere with each other.
 */
- (void)testConcurrentReads
{
    const int kNumThreads = 8;
    const int kReadsPerThread = 200;

    // Set a known value
    const char *testJSON = "{\"shared\":\"value\",\"number\":42}";
    kscrashreport_setUserInfoJSON(testJSON);

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("test.concurrentReads", DISPATCH_QUEUE_CONCURRENT);

    __block atomic_int successfulReads = 0;
    __block atomic_int correctValues = 0;
    __block atomic_int skippedReads = 0;

    for (int t = 0; t < kNumThreads; t++) {
        dispatch_group_async(group, queue, ^{
            for (int i = 0; i < kReadsPerThread; i++) {
                const char *result = kscrashreport_getUserInfoJSON();
                if (result != NULL) {
                    atomic_fetch_add(&successfulReads, 1);
                    if (strcmp(result, testJSON) == 0) {
                        atomic_fetch_add(&correctValues, 1);
                    }
                    free((void *)result);
                } else {
                    atomic_fetch_add(&skippedReads, 1);
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    int reads = atomic_load(&successfulReads);
    int correct = atomic_load(&correctValues);
    int skipped = atomic_load(&skippedReads);

    XCTAssertEqual(reads + skipped, kNumThreads * kReadsPerThread, @"All read attempts should complete");
    XCTAssertEqual(reads, correct, @"All successful reads should return correct value");

    NSLog(@"Concurrent reads test: %d successful, %d correct, %d skipped", reads, correct, skipped);
}

@end
