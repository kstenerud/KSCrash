//
// ksunwind_test_harness.m
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

#import "ksunwind_test_harness.h"

#import <stdio.h>
#import <string.h>

#import "KSBinaryImageCache.h"
#import "Unwind/KSCompactUnwind.h"
#import "Unwind/KSDwarfUnwind.h"

// =============================================================================
// MARK: - Design Notes
// =============================================================================
//
// BACKGROUND:
// The original libunwind regression tests (from Apple via PLCrashReporter) were
// designed to test Apple's libunwind library. They work as follows:
//
// 1. `unwind_tester` loads magic values into callee-saved registers (x19-x28
//    on ARM64, rbx/r12-r15 on x86_64)
// 2. `unwind_tester` calls a test function (e.g., `_unwind_test_arm64_frame_x19_x20`)
// 3. The test function saves some registers to the stack, zeros them, then calls
//    `_uwind_to_main`
// 4. `_uwind_to_main` uses libunwind to:
//    a. Walk the stack back through the test function to `unwind_tester`
//    b. Call `unw_resume()` to JUMP directly to `unwind_tester`, restoring all
//       registers from the unwound state
// 5. `unwind_tester` verifies the registers still contain magic values
//
// The key is `unw_resume()` - it performs a longjmp-style transfer of control,
// completely bypassing the test function's epilogue. The test functions have
// epilogues that would crash if executed normally (they do `mov sp, fp` before
// restoring saved registers, which corrupts the stack for a normal return).
//
// WHY WE CAN'T USE THE ORIGINAL APPROACH:
// KSCrash doesn't have an equivalent to `unw_resume()`. Our unwind code computes
// what register values SHOULD be after unwinding, but doesn't actually restore
// them and transfer control. Implementing `unw_resume()` would require complex
// architecture-specific assembly.
//
// OUR APPROACH:
// Instead of testing the full unwind-and-resume flow, we test what matters for
// crash reporting: that we can correctly PARSE the DWARF unwind info in the
// assembly test functions. We do this by:
//
// 1. Getting the address of each test function
// 2. Looking up its unwind info (compact unwind or DWARF)
// 3. Verifying we can find and parse the FDE/CIE
// 4. Verifying the parsed CFI rules make sense
//
// This validates that our DWARF parser works correctly with real-world unwind
// info, which is what we need for accurate crash stack traces.
//
// =============================================================================

// =============================================================================
// MARK: - Test Result Tracking
// =============================================================================

static KSUnwindTestResult g_testResults;

KSUnwindTestResult *ksunwind_test_get_results(void) { return &g_testResults; }

void ksunwind_test_reset_results(void)
{
    memset(&g_testResults, 0, sizeof(g_testResults));
    g_testResults.lastError[0] = '\0';
}

static void record_test_pass(void)
{
    g_testResults.totalTests++;
    g_testResults.passedTests++;
}

static void record_test_fail(const char *error)
{
    g_testResults.totalTests++;
    g_testResults.failedTests++;
    if (error != NULL) {
        snprintf(g_testResults.lastError, sizeof(g_testResults.lastError), "%s", error);
    }
}

// =============================================================================
// MARK: - Assembly Callback Stub
// =============================================================================

// The assembly test functions call _ksunwind_to_main. In the original libunwind
// tests, this function would use unw_resume() to longjmp back to the caller.
// Since we don't call the test functions (we just use their addresses to look
// up DWARF info), this is just a stub to satisfy the linker.
//
// If this function is ever actually called, something is wrong - we should
// never be executing the test functions, only inspecting their unwind info.
__attribute__((noreturn)) void ksunwind_to_main(void)
{
    // This should never be called in our test approach.
    // If we get here, abort to make it obvious something is wrong.
    fprintf(stderr, "ERROR: ksunwind_to_main was called - this should never happen!\n");
    abort();
}

// =============================================================================
// MARK: - Assembly Test Function Declarations
// =============================================================================

// These are defined in the assembly files.
// We use their addresses to look up and verify unwind info.
typedef void (*test_function_t)(void);

#if defined(__arm64__)

// ARM64 frame-based test function list (null-terminated)
extern test_function_t unwind_tester_list_arm64_frame[];

// ARM64 frameless test function list (null-terminated)
extern test_function_t unwind_tester_list_arm64_frameless[];

#elif defined(__x86_64__)

// x86_64 frame-based test function list (null-terminated)
extern test_function_t unwind_tester_list_x86_64_frame[];

// x86_64 frameless test function list (null-terminated)
extern test_function_t unwind_tester_list_x86_64_frameless[];

#endif

// =============================================================================
// MARK: - Unwind Info Verification
// =============================================================================

/**
 * Verify that we can find and parse DWARF unwind info for a function.
 *
 * This tests that:
 * 1. We can find the image containing the function
 * 2. The image has __eh_frame data
 * 3. We can find the FDE for this function
 * 4. We can parse the CIE and FDE
 * 5. We can build a CFI row for an address within the function
 *
 * @param func_addr The address of the function to test.
 * @param name The name of the test for error reporting.
 * @return true if all verifications passed, false otherwise.
 */
static bool verify_dwarf_unwind_info(uintptr_t func_addr, const char *name)
{
    // Step 1: Find the image containing this function
    KSBinaryImageUnwindInfo imageInfo;
    if (!ksbic_getUnwindInfoForAddress(func_addr, &imageInfo)) {
        char error[256];
        snprintf(error, sizeof(error), "%s: Could not find image for address %p", name, (void *)func_addr);
        record_test_fail(error);
        return false;
    }

    // Step 2: Verify the image has __eh_frame data
    if (!imageInfo.hasEhFrame || imageInfo.ehFrame == NULL) {
        char error[256];
        snprintf(error, sizeof(error), "%s: Image has no __eh_frame data", name);
        record_test_fail(error);
        return false;
    }

    // Step 3: Find the FDE for this function
    const uint8_t *fde = NULL;
    size_t fdeSize = 0;
    const uint8_t *cie = NULL;
    size_t cieSize = 0;
    bool is64bit = false;

    bool found = ksdwarf_findFDE(imageInfo.ehFrame, imageInfo.ehFrameSize, func_addr, (uintptr_t)imageInfo.header, &fde,
                                 &fdeSize, &cie, &cieSize, &is64bit);

    if (!found) {
        char error[256];
        snprintf(error, sizeof(error), "%s: Could not find FDE for address %p", name, (void *)func_addr);
        record_test_fail(error);
        return false;
    }

    // Step 4 & 5: Parse the CIE/FDE and build a CFI row
    KSDwarfCFIRow row;
    bool parsed = ksdwarf_buildCFIRow(cie, cieSize, fde, fdeSize, func_addr, is64bit, &row);

    if (!parsed) {
        char error[256];
        snprintf(error, sizeof(error), "%s: Could not parse CFI for address %p", name, (void *)func_addr);
        record_test_fail(error);
        return false;
    }

    // Verify the CFI row has sensible values
    // CFA should be defined (either register+offset or expression)
    // cfaRule tells us how CFA is computed:
    // - KSDwarfRuleOffset: CFA = register + offset
    // - KSDwarfRuleExpression: CFA = result of expression
    bool hasCFA = (row.cfaRule != KSDwarfRuleUndefined) || (row.cfaRegister != 0) || (row.cfaOffset != 0) ||
                  (row.cfaExpression != NULL);
    if (!hasCFA) {
        char error[256];
        snprintf(error, sizeof(error), "%s: CFI row has no CFA definition", name);
        record_test_fail(error);
        return false;
    }

    record_test_pass();
    return true;
}

/**
 * Run DWARF unwind info verification for all functions in a test list.
 *
 * @param test_list Null-terminated array of test function pointers.
 * @param list_name Name of the test list for error reporting.
 * @return true if all tests passed, false otherwise.
 */
static bool run_dwarf_verification(test_function_t *test_list, const char *list_name)
{
    if (test_list == NULL) {
        return true;
    }

    bool all_passed = true;
    int index = 0;

    while (test_list[index] != NULL) {
        char test_name[64];
        snprintf(test_name, sizeof(test_name), "%s[%d]", list_name, index);

        uintptr_t func_addr = (uintptr_t)test_list[index];
        if (!verify_dwarf_unwind_info(func_addr, test_name)) {
            all_passed = false;
        }
        index++;
    }

    return all_passed;
}

// =============================================================================
// MARK: - ARM64 Tests
// =============================================================================

#if defined(__arm64__)

bool ksunwind_test_arm64_frame(void)
{
    ksunwind_test_reset_results();
    return run_dwarf_verification(unwind_tester_list_arm64_frame, "arm64_frame");
}

bool ksunwind_test_arm64_frameless(void)
{
    ksunwind_test_reset_results();
    return run_dwarf_verification(unwind_tester_list_arm64_frameless, "arm64_frameless");
}

#endif  // __arm64__

// =============================================================================
// MARK: - x86_64 Tests
// =============================================================================

#if defined(__x86_64__)

bool ksunwind_test_x86_64_frame(void)
{
    ksunwind_test_reset_results();
    return run_dwarf_verification(unwind_tester_list_x86_64_frame, "x86_64_frame");
}

bool ksunwind_test_x86_64_frameless(void)
{
    ksunwind_test_reset_results();
    return run_dwarf_verification(unwind_tester_list_x86_64_frameless, "x86_64_frameless");
}

#endif  // __x86_64__

// =============================================================================
// MARK: - Combined Test Runners
// =============================================================================

bool ksunwind_test_run_frame_tests(void)
{
#if defined(__arm64__)
    return ksunwind_test_arm64_frame();
#elif defined(__x86_64__)
    return ksunwind_test_x86_64_frame();
#else
    // Unsupported architecture
    return true;
#endif
}

bool ksunwind_test_run_frameless_tests(void)
{
#if defined(__arm64__)
    return ksunwind_test_arm64_frameless();
#elif defined(__x86_64__)
    return ksunwind_test_x86_64_frameless();
#else
    // Unsupported architecture
    return true;
#endif
}

bool ksunwind_test_run_all(void)
{
    ksunwind_test_reset_results();

    bool frame_passed = ksunwind_test_run_frame_tests();
    bool frameless_passed = ksunwind_test_run_frameless_tests();

    return frame_passed && frameless_passed;
}
