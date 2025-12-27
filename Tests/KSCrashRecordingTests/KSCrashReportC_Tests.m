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

#import "KSCrashReportC.h"

#include <pthread.h>
#include <stdatomic.h>

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
