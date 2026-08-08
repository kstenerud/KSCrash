//
//  KSBenchmarkTestCase.swift
//
//  Created by Alexander Cohen on 2026-01-29.
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
import XCTest

// True when the process is running under a sanitizer (ASan/TSan/UBSan). Used to
// skip these benchmarks: measuring performance under a sanitizer is meaningless,
// and under TSan XCTest's measure() intermittently SEGVs in objc_release during
// measurement teardown.
//
// The dlsym probe is deliberate. Each tidier-looking option fails here:
//   - `#if KSCRASH_HAS_SANITIZER`: that is a C preprocessor macro, and Swift's
//     `#if` only reads `-D` build conditions, not C macros, so it is silently
//     always false (this was the original, broken guard).
//   - A shared helper in a module (KSCrashTestTools, KSCrashSwiftCore): these
//     benchmark sources are also compiled by the Tuist on-device build
//     (Benchmarks/Project.swift), which can only depend on shipping products, not
//     internal test/utility targets, so any such import breaks that build.
//   - A `-D SANITIZER` build flag + `#if`: only skips when the build passes the
//     flag, so a local `swift test --sanitize` that omits it silently runs the
//     benchmarks and crashes.
// A sanitizer runtime exports a well-known init symbol once loaded, so a dlsym
// against RTLD_DEFAULT detects it however the build was invoked, with zero
// dependencies.
private func isRunningUnderSanitizer() -> Bool {
    // RTLD_DEFAULT (search every loaded image) is not exported to Swift, so spell
    // out its pseudo-handle value.
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    return ["__asan_init", "__tsan_init", "__ubsan_handle_add_overflow"].contains { symbol in
        symbol.withCString { dlsym(rtldDefault, $0) != nil }
    }
}

/// Base class for all KSCrash benchmark tests.
///
/// On physical devices (non-simulator), reduces the default XCTest
/// measurement iteration count from 10 to 5. With 9 benchmark classes
/// running across 3 BrowserStack shards, the default 10 iterations adds
/// significant wall-clock time and CI cost. 5 iterations still provides
/// statistically meaningful results while keeping total execution time
/// reasonable.
///
/// On simulators, the default 10 iterations are preserved since
/// simulator runs are local and faster to iterate on.
class KSBenchmarkTestCase: XCTestCase {
    override class var defaultMeasureOptions: XCTMeasureOptions {
        let options = super.defaultMeasureOptions
        #if !targetEnvironment(simulator)
            options.iterationCount = 5
        #endif
        return options
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Benchmarks measure performance, which is meaningless under a sanitizer,
        // and XCTest's measure() intermittently crashes in objc_release under TSan.
        try XCTSkipIf(isRunningUnderSanitizer(), "Benchmarks do not run under sanitizers")
    }
}
