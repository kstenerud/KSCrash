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

import KSCrashRecordingCore
import XCTest

// Dummy handler for benchmarking - does nothing
private let dummyHandler: cxa_throw_type = { _, _, _ in }

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
    func testBenchmarkSwapInstallationCold() {
        #if KSCRASH_HAS_SANITIZER
            print("Skipping benchmark - sanitizers are enabled")
            return
        #endif

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
