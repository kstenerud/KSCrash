//
//  KSCPURingBuffer_Tests.m
//
//  Created by Alexander Cohen on 2026-04-09.
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

#include "KSCPURingBuffer.h"

#define NS_PER_SEC 1000000000ULL

@interface KSCPURingBuffer_Tests : XCTestCase
@end

@implementation KSCPURingBuffer_Tests

- (void)testEmptyRingHasZeroCount
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);
    XCTAssertEqual(kscpuring_count(&ring), 0u);
}

- (void)testEmptyNewestReturnsZero
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);
    KSCPURingSample s = kscpuring_newest(&ring);
    XCTAssertEqual(s.wallNs, 0u);
    XCTAssertEqual(s.cpuTimeNs, 0u);
}

- (void)testPushIncrementsCount
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 100, .cpuTimeNs = 50 });
    XCTAssertEqual(kscpuring_count(&ring), 1u);
}

- (void)testNewestReturnsMostRecentPush
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 100, .cpuTimeNs = 50 });
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 200, .cpuTimeNs = 120 });
    KSCPURingSample s = kscpuring_newest(&ring);
    XCTAssertEqual(s.wallNs, 200u);
    XCTAssertEqual(s.cpuTimeNs, 120u);
}

- (void)testCountCapsAtCapacity
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);
    for (uint32_t i = 0; i < KSCPU_RING_BUFFER_CAPACITY + 10; i++) {
        kscpuring_push(&ring, (KSCPURingSample) { .wallNs = (i + 1) * 100, .cpuTimeNs = (i + 1) * 50 });
    }
    XCTAssertEqual(kscpuring_count(&ring), (uint32_t)KSCPU_RING_BUFFER_CAPACITY);
}

- (void)testNewestAfterWrapAround
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);
    for (uint32_t i = 0; i < KSCPU_RING_BUFFER_CAPACITY + 5; i++) {
        kscpuring_push(&ring, (KSCPURingSample) { .wallNs = (i + 1) * 100, .cpuTimeNs = (i + 1) * 50 });
    }
    uint32_t expected = KSCPU_RING_BUFFER_CAPACITY + 5;
    KSCPURingSample s = kscpuring_newest(&ring);
    XCTAssertEqual(s.wallNs, expected * 100);
}

- (void)testOldestForWindowFindsCorrectSample
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);

    // Push 10 samples at 5s intervals: t=5s,10s,...,50s
    for (uint32_t i = 1; i <= 10; i++) {
        kscpuring_push(&ring, (KSCPURingSample) { .wallNs = i * 5 * NS_PER_SEC, .cpuTimeNs = i * 1000 });
    }

    // Window of 20s from newest (50s): cutoff = 30s.
    // Oldest sample at or before 30s is t=30s (i=6).
    KSCPURingSample oldest = kscpuring_oldestForWindow(&ring, 20 * NS_PER_SEC);
    XCTAssertEqual(oldest.wallNs, 30 * NS_PER_SEC);
}

- (void)testOldestForWindowFallsBackToOldest
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);

    // Push 3 samples spanning only 10s
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 1 * NS_PER_SEC, .cpuTimeNs = 100 });
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 6 * NS_PER_SEC, .cpuTimeNs = 500 });
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 11 * NS_PER_SEC, .cpuTimeNs = 1000 });

    // Window of 60s: no sample is 60s old, so return the absolute oldest.
    KSCPURingSample oldest = kscpuring_oldestForWindow(&ring, 60 * NS_PER_SEC);
    XCTAssertEqual(oldest.wallNs, 1 * NS_PER_SEC);
}

- (void)testAverageForWindowReturnsZeroWithFewerThanTwoSamples
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 100, .cpuTimeNs = 50 });
    XCTAssertEqualWithAccuracy(kscpuring_averageForWindow(&ring, 60 * NS_PER_SEC, 4), 0.0, 0.001);
}

- (void)testAverageForWindowReturnsZeroIfWindowNotSpanned
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);

    // Two samples 10s apart, but asking for a 60s window.
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 1 * NS_PER_SEC, .cpuTimeNs = 0 });
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 11 * NS_PER_SEC, .cpuTimeNs = 5 * NS_PER_SEC });
    XCTAssertEqualWithAccuracy(kscpuring_averageForWindow(&ring, 60 * NS_PER_SEC, 4), 0.0, 0.001);
}

- (void)testAverageForWindowComputesCorrectly
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);

    // Simulate 4-core device, 100% of one core sustained for 70s.
    // Push samples at 5s intervals for 70s.
    for (uint32_t i = 0; i <= 14; i++) {
        uint64_t wallNs = i * 5 * NS_PER_SEC;
        // CPU time accumulates at 1 core's worth: cpuTimeNs == wallNs
        kscpuring_push(&ring, (KSCPURingSample) { .wallNs = wallNs, .cpuTimeNs = wallNs });
    }

    // Average over 60s window on 4 cores: cpuDelta/wallDelta = 1.0 (one core),
    // divided by 4 cores = 0.25.
    double avg = kscpuring_averageForWindow(&ring, 60 * NS_PER_SEC, 4);
    XCTAssertEqualWithAccuracy(avg, 0.25, 0.01);
}

- (void)testAverageForWindowReturnsZeroWithZeroCoreCount
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 0, .cpuTimeNs = 0 });
    kscpuring_push(&ring, (KSCPURingSample) { .wallNs = 100 * NS_PER_SEC, .cpuTimeNs = 50 * NS_PER_SEC });
    XCTAssertEqualWithAccuracy(kscpuring_averageForWindow(&ring, 60 * NS_PER_SEC, 0), 0.0, 0.001);
}

- (void)testWrapAroundPreservesCorrectness
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);

    // Fill beyond capacity, then verify average still works.
    // CAPACITY + 20 samples at 5s intervals with constant 50% of 2 cores.
    uint32_t totalSamples = KSCPU_RING_BUFFER_CAPACITY + 20;
    for (uint32_t i = 0; i < totalSamples; i++) {
        uint64_t wallNs = (uint64_t)(i + 1) * 5 * NS_PER_SEC;
        // 50% of one core: cpuTimeNs = wallNs / 2
        kscpuring_push(&ring, (KSCPURingSample) { .wallNs = wallNs, .cpuTimeNs = wallNs / 2 });
    }

    // Average over 60s on 2 cores: (cpuDelta/wallDelta) / 2 = 0.5 / 2 = 0.25
    double avg = kscpuring_averageForWindow(&ring, 60 * NS_PER_SEC, 2);
    XCTAssertEqualWithAccuracy(avg, 0.25, 0.01);
}

- (void)testOldestForWindowOnEmptyRingReturnsZero
{
    KSCPURingBuffer ring;
    kscpuring_init(&ring);
    KSCPURingSample s = kscpuring_oldestForWindow(&ring, 60 * NS_PER_SEC);
    XCTAssertEqual(s.wallNs, 0u);
    XCTAssertEqual(s.cpuTimeNs, 0u);
}

@end
