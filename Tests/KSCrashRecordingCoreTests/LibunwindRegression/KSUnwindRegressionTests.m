//
// KSUnwindRegressionTests.m
//
// XCTest wrapper for libunwind regression tests.
// Ported from Apple's libunwind regression tests via PLCrashReporter.
//
// Copyright (c) 2025 Karl Stenerud. All rights reserved.
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

#import "ksunwind_test_harness.h"

// External declarations for binary image cache initialization
extern void ksbic_resetCache(void);
extern void ksbic_init(void);

@interface KSUnwindRegressionTests : XCTestCase
@end

@implementation KSUnwindRegressionTests

// =============================================================================
// MARK: - Setup and Teardown
// =============================================================================

- (void)setUp
{
    [super setUp];
    // The binary image cache must be initialized before we can look up unwind
    // info for addresses. This is normally done by the KSCrash installation
    // process, but we need to do it manually in tests.
    ksbic_resetCache();
    ksbic_init();
}

// =============================================================================
// MARK: - ARM64 Tests
// =============================================================================

#if defined(__arm64__)

- (void)testARM64FrameBased
{
    bool passed = ksunwind_test_arm64_frame();
    if (!passed) {
        KSUnwindTestResult *results = ksunwind_test_get_results();
        XCTFail(@"ARM64 frame-based tests failed: %s (passed=%d, failed=%d)", results->lastError, results->passedTests,
                results->failedTests);
    }
}

- (void)testARM64Frameless
{
    bool passed = ksunwind_test_arm64_frameless();
    if (!passed) {
        KSUnwindTestResult *results = ksunwind_test_get_results();
        XCTFail(@"ARM64 frameless tests failed: %s (passed=%d, failed=%d)", results->lastError, results->passedTests,
                results->failedTests);
    }
}

#endif  // __arm64__

// =============================================================================
// MARK: - x86_64 Tests
// =============================================================================

#if defined(__x86_64__)

- (void)testX86_64FrameBased
{
    bool passed = ksunwind_test_x86_64_frame();
    if (!passed) {
        KSUnwindTestResult *results = ksunwind_test_get_results();
        XCTFail(@"x86_64 frame-based tests failed: %s (passed=%d, failed=%d)", results->lastError, results->passedTests,
                results->failedTests);
    }
}

- (void)testX86_64Frameless
{
    bool passed = ksunwind_test_x86_64_frameless();
    if (!passed) {
        KSUnwindTestResult *results = ksunwind_test_get_results();
        XCTFail(@"x86_64 frameless tests failed: %s (passed=%d, failed=%d)", results->lastError, results->passedTests,
                results->failedTests);
    }
}

#endif  // __x86_64__

// =============================================================================
// MARK: - Combined Tests
// =============================================================================

- (void)testAllFrameBasedUnwind
{
    bool passed = ksunwind_test_run_frame_tests();
    if (!passed) {
        KSUnwindTestResult *results = ksunwind_test_get_results();
        XCTFail(@"Frame-based tests failed: %s (passed=%d, failed=%d)", results->lastError, results->passedTests,
                results->failedTests);
    }
}

- (void)testAllFramelessUnwind
{
    bool passed = ksunwind_test_run_frameless_tests();
    if (!passed) {
        KSUnwindTestResult *results = ksunwind_test_get_results();
        XCTFail(@"Frameless tests failed: %s (passed=%d, failed=%d)", results->lastError, results->passedTests,
                results->failedTests);
    }
}

@end
