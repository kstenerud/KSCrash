//
//  KSBacktraceBenchmarks.swift
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

#if !os(watchOS)
    class KSBacktraceBenchmarks: XCTestCase {

        // MARK: - Backtrace Capture Benchmarks

        /// Benchmark capturing backtrace from the same thread (fast path)
        func testBenchmarkSameThreadBacktrace() {
            let thread = pthread_self()
            let entries = 512
            var addresses: [UInt] = Array(repeating: 0, count: entries)

            measure {
                _ = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))
            }
        }

        /// Benchmark capturing backtrace from a different thread (slow path with thread suspension)
        func testBenchmarkOtherThreadBacktrace() {
            let entries = 512
            var addresses: [UInt] = Array(repeating: 0, count: entries)

            var targetThread: pthread_t?

            let semaphore = DispatchSemaphore(value: 0)
            let endTestSemaphore = DispatchSemaphore(value: 0)

            // Start a background thread that stays alive during measurement
            DispatchQueue.global(qos: .default).async {
                targetThread = pthread_self()
                semaphore.signal()
                endTestSemaphore.wait()
            }

            semaphore.wait()

            guard let thread = targetThread else {
                XCTFail("Failed to get target thread")
                return
            }

            // Measure from main thread, capturing backtrace of the background thread
            measure {
                _ = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))
            }

            endTestSemaphore.signal()
        }

        /// Benchmark capturing backtrace with limited depth (typical crash scenario)
        func testBenchmarkBacktraceTypicalDepth() {
            let thread = pthread_self()
            let entries = 50  // Typical depth for crash reports
            var addresses: [UInt] = Array(repeating: 0, count: entries)

            measure {
                _ = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))
            }
        }

        // MARK: - Symbolication Benchmarks

        /// Benchmark symbolicating a single address
        func testBenchmarkSymbolicateSingleAddress() {
            let thread = pthread_self()
            let entries = 10
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            _ = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

            guard addresses[0] != 0 else {
                XCTFail("Failed to capture backtrace for symbolication benchmark")
                return
            }

            var result = SymbolInformation()
            measure {
                _ = symbolicate(address: addresses[0], result: &result)
            }
        }

        /// Benchmark symbolicating multiple addresses (full stack trace)
        func testBenchmarkSymbolicateFullStack() {
            let thread = pthread_self()
            let entries = 20
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

            guard count > 0 else {
                XCTFail("Failed to capture backtrace for symbolication benchmark")
                return
            }

            var result = SymbolInformation()
            measure {
                for i in 0..<Int(count) {
                    _ = symbolicate(address: addresses[i], result: &result)
                }
            }
        }

        // MARK: - Combined Benchmarks

        /// Benchmark complete backtrace capture and symbolication (typical crash handling flow)
        func testBenchmarkCaptureAndSymbolicate() {
            let thread = pthread_self()
            let entries = 50
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            var result = SymbolInformation()

            measure {
                let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))
                for i in 0..<Int(count) {
                    _ = symbolicate(address: addresses[i], result: &result)
                }
            }
        }
    }
#endif
