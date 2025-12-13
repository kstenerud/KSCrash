//
//  KSProfilerBenchmarks.swift
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
import KSCrashProfiler
import XCTest

#if !os(watchOS)
    final class KSProfilerBenchmarks: XCTestCase {

        // MARK: - Profiler Lifecycle Benchmarks

        /// Benchmark profiler initialization
        func testBenchmarkProfilerInit() {
            measure {
                _ = Profiler(thread: pthread_self(), interval: 0.01, maxFrames: 128, retentionSeconds: 30)
            }
        }

        /// Benchmark begin/end profile cycle with minimal duration
        func testBenchmarkBeginEndProfile() {
            let profiler = Profiler(thread: pthread_self(), interval: 0.01, retentionSeconds: 5)

            measure {
                let id = profiler.beginProfile()
                _ = profiler.endProfile(id: id)
            }
        }

        // MARK: - Sampling Benchmarks

        /// Benchmark profiling with 5ms interval (high frequency)
        func testBenchmarkHighFrequencySampling() {
            let profiler = Profiler(
                thread: pthread_self(),
                interval: 0.005,
                maxFrames: 64,
                retentionSeconds: 5
            )

            measure {
                let id = profiler.beginProfile()
                Thread.sleep(forTimeInterval: 0.05)
                _ = profiler.endProfile(id: id)
            }
        }

        /// Benchmark profiling with 10ms interval (default frequency)
        func testBenchmarkDefaultFrequencySampling() {
            let profiler = Profiler(
                thread: pthread_self(),
                interval: 0.01,
                maxFrames: 128,
                retentionSeconds: 5
            )

            measure {
                let id = profiler.beginProfile()
                Thread.sleep(forTimeInterval: 0.1)
                _ = profiler.endProfile(id: id)
            }
        }

        /// Benchmark profiling another thread
        func testBenchmarkCrossThreadProfiling() {
            var targetThread: pthread_t?
            let semaphore = DispatchSemaphore(value: 0)
            let endSemaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                targetThread = pthread_self()
                semaphore.signal()
                endSemaphore.wait()
            }

            semaphore.wait()

            guard let thread = targetThread else {
                XCTFail("Failed to get target thread")
                return
            }

            let profiler = Profiler(
                thread: thread,
                interval: 0.01,
                maxFrames: 64,
                retentionSeconds: 5
            )

            measure {
                let id = profiler.beginProfile()
                Thread.sleep(forTimeInterval: 0.05)
                _ = profiler.endProfile(id: id)
            }

            endSemaphore.signal()
        }

        // MARK: - Sample Retrieval Benchmarks

        /// Benchmark retrieving samples from a profile
        func testBenchmarkSampleRetrieval() {
            let profiler = Profiler(
                thread: pthread_self(),
                interval: 0.005,
                maxFrames: 64,
                retentionSeconds: 5
            )

            // Pre-fill with samples
            let id = profiler.beginProfile()
            Thread.sleep(forTimeInterval: 0.2)

            measure {
                _ = profiler.endProfile(id: id)
            }
        }

        // MARK: - Concurrent Profiles Benchmarks

        /// Benchmark multiple concurrent profile sessions
        func testBenchmarkConcurrentProfiles() {
            let profiler = Profiler(
                thread: pthread_self(),
                interval: 0.01,
                retentionSeconds: 10
            )

            measure {
                let id1 = profiler.beginProfile()
                let id2 = profiler.beginProfile()
                let id3 = profiler.beginProfile()

                Thread.sleep(forTimeInterval: 0.03)

                _ = profiler.endProfile(id: id1)
                _ = profiler.endProfile(id: id2)
                _ = profiler.endProfile(id: id3)
            }
        }

        // MARK: - Storage Size Benchmarks

        /// Benchmark storage size calculation
        func testBenchmarkStorageSizeCalculation() {
            measure {
                for _ in 0..<1000 {
                    _ = Profiler.storageSize(interval: 0.01, maxFrames: 128, retentionSeconds: 30)
                }
            }
        }
    }
#endif
