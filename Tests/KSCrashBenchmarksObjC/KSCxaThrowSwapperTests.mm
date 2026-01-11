//
//  KSCxaThrowSwapperTests.mm
//
//  Created for KSCrash.
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

#include <atomic>
#include <exception>
#include <stdexcept>
#include <string>
#include <typeinfo>

#include "KSCxaThrowSwapper.h"
#include "KSSystemCapabilities.h"

#pragma mark - Test Exception Classes

class TestException : public std::exception
{
   public:
    const char *what() const noexcept override { return "Test exception"; }
};

#pragma mark - Handler State

static std::atomic<int> g_handlerCallCount { 0 };
static std::atomic<void *> g_lastThrownException { nullptr };
static std::atomic<std::type_info *> g_lastTypeInfo { nullptr };

static void testHandler(void *thrown_exception, std::type_info *tinfo, void (*dest)(void *) __unused)
{
    g_handlerCallCount.fetch_add(1, std::memory_order_relaxed);
    g_lastThrownException.store(thrown_exception, std::memory_order_relaxed);
    g_lastTypeInfo.store(tinfo, std::memory_order_relaxed);
}

static void resetHandlerState()
{
    g_handlerCallCount.store(0, std::memory_order_relaxed);
    g_lastThrownException.store(nullptr, std::memory_order_relaxed);
    g_lastTypeInfo.store(nullptr, std::memory_order_relaxed);
}

#pragma mark - Test Class

@interface KSCxaThrowSwapperTests : XCTestCase
@end

@implementation KSCxaThrowSwapperTests

- (void)setUp
{
    [super setUp];
    resetHandlerState();
}

- (void)tearDown
{
#if !KSCRASH_HAS_SANITIZER
    ksct_swapReset();
#endif
    [super tearDown];
}

#pragma mark - Basic Functionality Tests

/// Test that swap returns success
- (void)testSwapReturnsSuccess
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    int result = ksct_swap(testHandler);
    XCTAssertEqual(result, 0, @"ksct_swap should return 0 on success");
}

/// Test that handler is called when exception is thrown
- (void)testHandlerIsCalledOnThrow
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    ksct_swap(testHandler);

    XCTAssertEqual(g_handlerCallCount.load(), 0, @"Handler should not be called yet");

    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }

    XCTAssertEqual(g_handlerCallCount.load(), 1, @"Handler should be called once after throw");
}

/// Test that handler receives correct type info
- (void)testHandlerReceivesTypeInfo
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    ksct_swap(testHandler);

    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }

    std::type_info *capturedType = g_lastTypeInfo.load();
    XCTAssertNotEqual(capturedType, nullptr, @"Type info should be captured");
    XCTAssertTrue(*capturedType == typeid(TestException), @"Type info should match TestException");
}

/// Test that exceptions still work correctly after swap
- (void)testExceptionStillWorksAfterSwap
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    ksct_swap(testHandler);

    bool exceptionCaught = false;
    try {
        throw std::runtime_error("test error");
    } catch (const std::runtime_error &e) {
        exceptionCaught = true;
        XCTAssertTrue(strcmp(e.what(), "test error") == 0, @"Exception message should be preserved");
    }

    XCTAssertTrue(exceptionCaught, @"Exception should be caught normally");
}

#pragma mark - Reset Tests

/// Test that reset can be called without prior swap
- (void)testResetWithoutSwap
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    // Should not crash
    ksct_swapReset();
}

/// Test that handler is not called after reset
- (void)testHandlerNotCalledAfterReset
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    ksct_swap(testHandler);

    // Verify handler works
    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 1, @"Handler should be called once");

    // Reset
    ksct_swapReset();
    resetHandlerState();

    // Throw again - handler should not be called
    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }

    XCTAssertEqual(g_handlerCallCount.load(), 0, @"Handler should not be called after reset");
}

/// Test that exceptions still work after reset
- (void)testExceptionsWorkAfterReset
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    ksct_swap(testHandler);
    ksct_swapReset();

    bool exceptionCaught = false;
    try {
        throw std::runtime_error("after reset");
    } catch (const std::runtime_error &e) {
        exceptionCaught = true;
        XCTAssertTrue(strcmp(e.what(), "after reset") == 0, @"Exception message should be preserved");
    }

    XCTAssertTrue(exceptionCaught, @"Exception should be caught after reset");
}

#pragma mark - Multiple Swap Tests

/// Test that calling swap multiple times works correctly
- (void)testMultipleSwapCalls
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    // First swap
    int result1 = ksct_swap(testHandler);
    XCTAssertEqual(result1, 0);

    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 1);

    // Second swap (should reset first, then rebind)
    resetHandlerState();
    int result2 = ksct_swap(testHandler);
    XCTAssertEqual(result2, 0);

    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 1, @"Handler should be called once after re-swap");
}

/// Test swap-reset-swap cycle
- (void)testSwapResetSwapCycle
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    for (int cycle = 0; cycle < 3; cycle++) {
        resetHandlerState();

        ksct_swap(testHandler);

        try {
            throw TestException();
        } catch (const TestException &e) {
            (void)e;
        }
        XCTAssertEqual(g_handlerCallCount.load(), 1, @"Handler should be called in cycle %d", cycle);

        ksct_swapReset();
        resetHandlerState();

        try {
            throw TestException();
        } catch (const TestException &e) {
            (void)e;
        }
        XCTAssertEqual(g_handlerCallCount.load(), 0, @"Handler should not be called after reset in cycle %d", cycle);
    }
}

#pragma mark - Multiple Exception Types

/// Test handler is called for different exception types
- (void)testDifferentExceptionTypes
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping test - sanitizers are enabled");
    return;
#endif

    ksct_swap(testHandler);

    // Test with custom exception
    try {
        throw TestException();
    } catch (const TestException &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 1);

    // Test with runtime_error
    try {
        throw std::runtime_error("test");
    } catch (const std::runtime_error &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 2);

    // Test with int
    try {
        throw 42;
    } catch (int e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 3);

    // Test with string
    try {
        throw std::string("test string");
    } catch (const std::string &e) {
        (void)e;
    }
    XCTAssertEqual(g_handlerCallCount.load(), 4);
}

@end
