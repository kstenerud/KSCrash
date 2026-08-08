//
//  KSCxaThrowColdBenchmarks.swift
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

import Darwin
import KSCrashRecordingCore
import XCTest

// Dummy handler for benchmarking - does nothing
private let dummyHandler: cxa_throw_type = { _, _, _ in }

// True when the process is running under a sanitizer (ASan/TSan/UBSan), used to
// skip this benchmark (it conflicts with a sanitizer and SEGVs under TSan).
// Copied from KSBenchmarkTestCase because this cold benchmark is a separate SPM
// target and can't share code with it; see there for why the sanitizer is probed
// with dlsym rather than a C-macro `#if`, a shared module, or a build flag.
private func isRunningUnderSanitizer() -> Bool {
    // RTLD_DEFAULT (search every loaded image) is not exported to Swift, so spell
    // out its pseudo-handle value.
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    return ["__asan_init", "__tsan_init", "__ubsan_handle_add_overflow"].contains { symbol in
        symbol.withCString { dlsym(rtldDefault, $0) != nil }
    }
}

/// This test target runs in its own process to ensure true cold measurement.
/// No other tests run before this, guaranteeing:
/// - dyld callback not yet registered
/// - Binary image cache not populated
/// - Memory pages not yet accessed
class KSCxaThrowColdBenchmarks: XCTestCase {

    /// Benchmark the time to install the __cxa_throw swapper (cold path).
    /// This test runs in an isolated process to ensure truly cold state.
    /// Uses iterationCount=1 with a counter trick: warmup iteration does nothing,
    /// measured iteration runs the actual cold installation.
    func testBenchmarkSwapInstallationCold() throws {
        try XCTSkipIf(isRunningUnderSanitizer(), "Sanitizers conflict with __cxa_throw swapper")

        var iteration = 0

        let options = Self.defaultMeasureOptions
        options.iterationCount = 1

        measure(options: options) {
            if iteration == 1 {
                // Second call (measured): run the actual cold installation
                let result = ksct_swap(dummyHandler)
                XCTAssertEqual(result, 0, "ksct_swap should succeed")
            }
            // First call (warmup): do nothing, leaving state cold for measured iteration
            iteration += 1
        }
    }
}
