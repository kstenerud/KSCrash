//
//  KSDate_Tests.m
//
//  Created by Alexander Cohen on 2026-07-26.
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

#import <stdint.h>

#import "KSDate.h"

@interface KSDate_Tests : XCTestCase
@end

@implementation KSDate_Tests

- (void)testConvertsUsingTheReferenceDelta
{
    // wall anchor 1000 at monotonic 500; a monotonic of 800 is 300 past the
    // reference, so the wall time is 1000 + 300.
    XCTAssertEqual(ksdate_monotonicToWallClockNanoseconds(800, 1000, 500), (uint64_t)1300);
}

- (void)testAtTheReferenceReturnsTheWallAnchor
{
    XCTAssertEqual(ksdate_monotonicToWallClockNanoseconds(500, 1000, 500), (uint64_t)1000);
}

- (void)testBeforeTheReferenceReturnsZero
{
    XCTAssertEqual(ksdate_monotonicToWallClockNanoseconds(499, 1000, 500), (uint64_t)0);
}

- (void)testZeroWallReferenceReturnsZero
{
    XCTAssertEqual(ksdate_monotonicToWallClockNanoseconds(800, 0, 500), (uint64_t)0);
}

- (void)testZeroMonotonicReferenceReturnsZero
{
    XCTAssertEqual(ksdate_monotonicToWallClockNanoseconds(800, 1000, 0), (uint64_t)0);
}

- (void)testOverflowReturnsZero
{
    // delta (UINT64_MAX - 1) added to any nonzero wall anchor overflows the
    // epoch, so the conversion is rejected.
    XCTAssertEqual(ksdate_monotonicToWallClockNanoseconds(UINT64_MAX, 1000, 1), (uint64_t)0);
}

- (void)testMaxValidConversionDoesNotOverflow
{
    // delta exactly fills the remaining headroom: wallRef + delta == UINT64_MAX,
    // the largest value that must still convert rather than be rejected.
    uint64_t wallRef = 1000;
    uint64_t monoRef = 1;
    uint64_t mono = UINT64_MAX - wallRef + monoRef;  // delta == UINT64_MAX - wallRef
    XCTAssertEqual(ksdate_monotonicToWallClockNanoseconds(mono, wallRef, monoRef), UINT64_MAX);
}

@end
