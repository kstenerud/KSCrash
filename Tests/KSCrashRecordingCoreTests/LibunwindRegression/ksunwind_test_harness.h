//
// ksunwind_test_harness.h
//
// Test harness for libunwind regression tests.
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

#ifndef KSUNWIND_TEST_HARNESS_H
#define KSUNWIND_TEST_HARNESS_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// MARK: - Test Result Tracking
// =============================================================================

/**
 * Structure to hold test results.
 */
typedef struct {
    int totalTests;
    int passedTests;
    int failedTests;
    char lastError[256];
} KSUnwindTestResult;

/**
 * Get a pointer to the global test result structure.
 * Use this to check detailed results after running tests.
 */
KSUnwindTestResult *ksunwind_test_get_results(void);

/**
 * Reset all test results to initial state.
 */
void ksunwind_test_reset_results(void);

// =============================================================================
// MARK: - ARM64 Tests
// =============================================================================

#if defined(__arm64__)

/**
 * Run all ARM64 frame-based unwind tests.
 *
 * Tests unwinding through functions that use a frame pointer (FP/X29).
 * These are the most common type of functions on ARM64.
 *
 * @return true if all tests passed, false otherwise.
 */
bool ksunwind_test_arm64_frame(void);

/**
 * Run all ARM64 frameless unwind tests.
 *
 * Tests unwinding through functions that don't use a frame pointer.
 * These rely on DWARF unwind info to restore the link register.
 *
 * @return true if all tests passed, false otherwise.
 */
bool ksunwind_test_arm64_frameless(void);

#endif  // __arm64__

// =============================================================================
// MARK: - x86_64 Tests
// =============================================================================

#if defined(__x86_64__)

/**
 * Run all x86_64 frame-based unwind tests.
 *
 * Tests unwinding through functions that use RBP as a frame pointer.
 *
 * @return true if all tests passed, false otherwise.
 */
bool ksunwind_test_x86_64_frame(void);

/**
 * Run all x86_64 frameless unwind tests.
 *
 * Tests unwinding through functions that don't use a frame pointer.
 * These rely on compact unwind or DWARF to track stack adjustments.
 *
 * @return true if all tests passed, false otherwise.
 */
bool ksunwind_test_x86_64_frameless(void);

#endif  // __x86_64__

// =============================================================================
// MARK: - Combined Test Runners
// =============================================================================

/**
 * Run all frame-based tests for the current architecture.
 *
 * @return true if all tests passed, false otherwise.
 */
bool ksunwind_test_run_frame_tests(void);

/**
 * Run all frameless tests for the current architecture.
 *
 * @return true if all tests passed, false otherwise.
 */
bool ksunwind_test_run_frameless_tests(void);

/**
 * Run all regression tests for the current architecture.
 *
 * @return true if all tests passed, false otherwise.
 */
bool ksunwind_test_run_all(void);

#ifdef __cplusplus
}
#endif

#endif  // KSUNWIND_TEST_HARNESS_H
