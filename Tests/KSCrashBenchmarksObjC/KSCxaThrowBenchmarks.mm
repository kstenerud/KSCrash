//
//  KSCxaThrowBenchmarks.mm
//
//  Created by Alexander Cohen on 2025-01-11.
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

#include <exception>
#include <stdexcept>
#include <string>
#include <typeinfo>

#include "KSCxaThrowSwapper.h"
#include "KSSystemCapabilities.h"

#pragma mark - Test Exception Classes

class BenchmarkException : public std::exception
{
   public:
    const char *what() const noexcept override { return "Benchmark exception"; }
};

#pragma mark - Helper Functions

// Dummy handler for benchmarking - does nothing
static void dummyHandler(void *thrown_exception __unused, std::type_info *tinfo __unused, void (*dest)(void *) __unused)
{
}

#pragma mark - Benchmark Test Class

@interface KSCxaThrowBenchmarks : XCTestCase
@end

@implementation KSCxaThrowBenchmarks

- (void)tearDown
{
#if !KSCRASH_HAS_SANITIZER
    // Reset after each test to ensure clean state for subsequent tests
    ksct_swapReset();
#endif
    [super tearDown];
}

#pragma mark - Installation Benchmarks

/// Benchmark the time to install/re-scan the __cxa_throw swapper (warm path).
/// Pre-registers the dyld callback and warms caches before measurement.
/// All measured iterations use the same code path with warm caches.
- (void)testBenchmarkSwapInstallationWarm
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping benchmark - sanitizers are enabled");
    return;
#endif

    // Pre-register callback and warm the binary image cache
    ksct_swap(dummyHandler);
    ksct_swapReset();
    ksct_swap(dummyHandler);
    ksct_swapReset();

    [self measureBlock:^{
        int result = ksct_swap(dummyHandler);
        XCTAssertEqual(result, 0, @"ksct_swap should succeed");
    }];
}

#pragma mark - Overhead Comparison Benchmarks

/// Baseline: Throw without swap installed (native C++ exception performance).
- (void)testBenchmarkThrowWithoutSwap
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping benchmark - sanitizers are enabled");
    return;
#endif

    // Ensure swap is not installed
    ksct_swapReset();

    [self measureBlock:^{
        try {
            throw BenchmarkException();
        } catch (const BenchmarkException &e) {
            (void)e;
        }
    }];
}

/// With swap: Throw with decorator installed (measures our overhead).
- (void)testBenchmarkThrowWithSwap
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping benchmark - sanitizers are enabled");
    return;
#endif

    // Ensure swap is installed
    ksct_swap(dummyHandler);

    [self measureBlock:^{
        try {
            throw BenchmarkException();
        } catch (const BenchmarkException &e) {
            (void)e;
        }
    }];
}

#pragma mark - Reset Benchmark

/// Benchmark the time to reset/restore original bindings.
- (void)testBenchmarkSwapReset
{
#if KSCRASH_HAS_SANITIZER
    NSLog(@"Skipping benchmark - sanitizers are enabled");
    return;
#endif

    // Install first so there's something to reset
    ksct_swap(dummyHandler);

    [self measureBlock:^{
        ksct_swapReset();
        // Re-install for next iteration
        ksct_swap(dummyHandler);
    }];
}

#pragma mark - Exception Type Benchmarks

/// Benchmark throwing and catching a C++ exception.
- (void)testBenchmarkThrowCatch
{
    [self measureBlock:^{
        try {
            throw BenchmarkException();
        } catch (const BenchmarkException &e) {
            (void)e;
        }
    }];
}

/// Benchmark throwing std::runtime_error.
- (void)testBenchmarkThrowRuntimeError
{
    [self measureBlock:^{
        try {
            throw std::runtime_error("benchmark error");
        } catch (const std::runtime_error &e) {
            (void)e;
        }
    }];
}

/// Benchmark throwing std::string (tests different exception type path).
- (void)testBenchmarkThrowString
{
    [self measureBlock:^{
        try {
            throw std::string("benchmark string exception");
        } catch (const std::string &e) {
            (void)e;
        }
    }];
}

/// Benchmark throwing int (primitive type).
- (void)testBenchmarkThrowInt
{
    [self measureBlock:^{
        try {
            throw 42;
        } catch (int e) {
            (void)e;
        }
    }];
}

#pragma mark - Stack Depth Benchmarks

/// Helper to throw from a specific stack depth.
__attribute__((noinline)) static void throwAtDepth(int depth)
{
    if (depth > 0) {
        throwAtDepth(depth - 1);
    } else {
        throw BenchmarkException();
    }
}

/// Benchmark throwing from shallow stack (10 frames).
/// Note: Stack depth affects C++ unwinding time, not our decorator overhead.
- (void)testBenchmarkThrowShallowStack
{
    [self measureBlock:^{
        try {
            throwAtDepth(10);
        } catch (const BenchmarkException &e) {
            (void)e;
        }
    }];
}

/// Benchmark throwing from deep stack (50 frames).
/// Note: Stack depth affects C++ unwinding time, not our decorator overhead.
- (void)testBenchmarkThrowDeepStack
{
    [self measureBlock:^{
        try {
            throwAtDepth(50);
        } catch (const BenchmarkException &e) {
            (void)e;
        }
    }];
}

/// Benchmark throwing from very deep stack (100 frames).
/// Note: Stack depth affects C++ unwinding time, not our decorator overhead.
- (void)testBenchmarkThrowVeryDeepStack
{
    [self measureBlock:^{
        try {
            throwAtDepth(100);
        } catch (const BenchmarkException &e) {
            (void)e;
        }
    }];
}

@end
