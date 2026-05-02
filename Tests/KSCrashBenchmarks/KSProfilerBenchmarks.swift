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
    class KSProfilerBenchmarks: KSBenchmarkTestCase {

        // MARK: - Profiler Lifecycle Benchmarks

        /// Benchmark profiler initialization
        func testBenchmarkProfilerInit() {
            measure {
                _ = Profiler<Sample128>(thread: pthread_self(), interval: 0.01, retentionSeconds: 30)
            }
        }

        /// Benchmark begin/end profile cycle with minimal duration
        func testBenchmarkBeginEndProfile() {
            let profiler = Profiler<Sample128>(thread: pthread_self(), interval: 0.01, retentionSeconds: 5)

            measure {
                let id = profiler.beginProfile(named: "benchmark")
                _ = profiler.endProfile(id: id)
            }
        }

        // MARK: - Sampling Benchmarks

        // The five sampling-scenario tests below need a `Thread.sleep` inside
        // the `measure` block to give the sampler real time to fire.
        // Wall-clock time is therefore dominated by the sleep, not by
        // profiler overhead, so we emit a custom `ProfilerSampleMetric`
        // carrying `profile.metrics.avgNs` (per-sample capture latency in
        // seconds). The default wall-clock metric is intentionally omitted.
        // See `ProfilerSampleMetric.swift` for the threading model.

        private static let perSampleAvgMetricID = "kscrash.profiler.persample_avg"
        private static let perSampleAvgDisplayName = "Per-sample avg latency"

        /// Runs `body` inside `measure(metrics:)`, emitting per-sample average
        /// latency from the returned `ProfileMetrics` as a custom metric.
        ///
        /// Asserts at least one sample was captured per iteration. A regression
        /// that yields zero samples (e.g. `Sample` capacity smaller than the
        /// profiled thread's stack, since the profiler discards truncated
        /// samples) would otherwise render as Excellent because `avgNs`
        /// returns 0 for empty sample lists. The assertion runs everywhere;
        /// if a platform has unreliable dispatch timing we'd rather fix the
        /// test than mask it.
        private func measurePerSampleLatency(
            file: StaticString = #file,
            line: UInt = #line,
            body: @escaping () -> ProfileMetrics?
        ) {
            var avgSeconds: Double = 0
            let metric = ProfilerSampleMetric(
                identifier: Self.perSampleAvgMetricID,
                displayName: Self.perSampleAvgDisplayName,
                valueProvider: { avgSeconds }
            )

            measure(metrics: [metric]) {
                let metrics = body()
                avgSeconds = (metrics?.avgNs ?? 0) / 1_000_000_000.0
                XCTAssertGreaterThan(
                    metrics?.count ?? 0,
                    0,
                    "Expected at least one sample to be captured",
                    file: file,
                    line: line
                )
            }
        }

        /// Benchmark profiling with 5ms interval (high frequency).
        ///
        /// Profiles `pthread_self()`, which under XCTest carries a 60+ frame
        /// stack, so uses `Sample128` to keep captures from being discarded
        /// as truncated.
        func testBenchmarkHighFrequencySampling() {
            let profiler = Profiler<Sample128>(
                thread: pthread_self(),
                interval: 0.005,
                retentionSeconds: 5
            )

            measurePerSampleLatency {
                let id = profiler.beginProfile(named: "benchmark")
                Thread.sleep(forTimeInterval: 0.05)
                return profiler.endProfile(id: id)?.metrics
            }
        }

        /// Benchmark profiling with 10ms interval (default frequency)
        func testBenchmarkDefaultFrequencySampling() {
            let profiler = Profiler<Sample128>(
                thread: pthread_self(),
                interval: 0.01,
                retentionSeconds: 5
            )

            measurePerSampleLatency {
                let id = profiler.beginProfile(named: "benchmark")
                Thread.sleep(forTimeInterval: 0.1)
                return profiler.endProfile(id: id)?.metrics
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

            let profiler = Profiler<Sample64>(
                thread: thread,
                interval: 0.01,
                retentionSeconds: 5
            )

            measurePerSampleLatency {
                let id = profiler.beginProfile(named: "benchmark")
                Thread.sleep(forTimeInterval: 0.05)
                return profiler.endProfile(id: id)?.metrics
            }

            endSemaphore.signal()
        }

        // MARK: - Sample Retrieval Benchmarks

        /// Benchmark retrieving samples from a profile.
        ///
        /// Same `Sample128` rationale as `testBenchmarkHighFrequencySampling`:
        /// the XCTest stack is too deep for `Sample64`.
        func testBenchmarkSampleRetrieval() {
            let profiler = Profiler<Sample128>(
                thread: pthread_self(),
                interval: 0.005,
                retentionSeconds: 5
            )

            measurePerSampleLatency {
                let id = profiler.beginProfile(named: "benchmark")
                Thread.sleep(forTimeInterval: 0.2)
                return profiler.endProfile(id: id)?.metrics
            }
        }

        // MARK: - Concurrent Profiles Benchmarks

        /// Benchmark multiple concurrent profile sessions
        func testBenchmarkConcurrentProfiles() {
            let profiler = Profiler<Sample128>(
                thread: pthread_self(),
                interval: 0.01,
                retentionSeconds: 10
            )

            measurePerSampleLatency {
                let id1 = profiler.beginProfile(named: "benchmark")
                let id2 = profiler.beginProfile(named: "benchmark")
                let id3 = profiler.beginProfile(named: "benchmark")

                Thread.sleep(forTimeInterval: 0.03)

                _ = profiler.endProfile(id: id1)
                _ = profiler.endProfile(id: id2)
                return profiler.endProfile(id: id3)?.metrics
            }
        }

        // MARK: - Storage Size Benchmarks

        /// Benchmark storage size calculation
        func testBenchmarkStorageSizeCalculation() {
            measure {
                for _ in 0..<1000 {
                    _ = Profiler<Sample128>.storageSize(interval: 0.01, retentionSeconds: 30)
                }
            }
        }

        // MARK: - Stack Depth Benchmarks

        /// Helper to create a thread with a specific stack depth and measure sample capture
        private func profileThreadWithStackDepth<S: Sample>(
            depth: Int,
            sampleType: S.Type,
            file: StaticString = #file,
            line: UInt = #line
        ) {
            var targetThread: pthread_t?
            let readySemaphore = DispatchSemaphore(value: 0)
            let doneSemaphore = DispatchSemaphore(value: 0)

            // Create thread that recurses to desired depth then waits
            DispatchQueue.global().async {
                targetThread = pthread_self()
                self.recurseAndWait(depth: depth, ready: readySemaphore, done: doneSemaphore)
            }

            // Wait for thread to reach desired depth
            readySemaphore.wait()

            guard let thread = targetThread else {
                XCTFail("Failed to get target thread", file: file, line: line)
                doneSemaphore.signal()
                return
            }

            // Measure 100 begin/end cycles to capture sample overhead
            // Each cycle schedules immediate sample capture (first sample is taken asynchronously shortly after begin)
            measure {
                for _ in 0..<100 {
                    let profiler = Profiler<S>(
                        thread: thread,
                        interval: 0.001,
                        retentionSeconds: 1
                    )
                    let id = profiler.beginProfile(named: "benchmark")
                    _ = profiler.endProfile(id: id)
                }
            }

            doneSemaphore.signal()
        }

        /// Recursive function to build stack depth
        @inline(never)
        private func recurseAndWait(depth: Int, ready: DispatchSemaphore, done: DispatchSemaphore) {
            if depth > 0 {
                recurseAndWait(depth: depth - 1, ready: ready, done: done)
            } else {
                ready.signal()
                done.wait()
            }
        }

        /// Benchmark sample capture with shallow stack (16 frames, Sample32)
        func testBenchmarkSampleCaptureShallowStack() {
            profileThreadWithStackDepth(depth: 16, sampleType: Sample32.self)
        }

        /// Benchmark sample capture with medium stack (64 frames, Sample128)
        func testBenchmarkSampleCaptureMediumStack() {
            profileThreadWithStackDepth(depth: 64, sampleType: Sample128.self)
        }

        /// Benchmark sample capture with deep stack (128 frames, Sample256)
        func testBenchmarkSampleCaptureDeepStack() {
            profileThreadWithStackDepth(depth: 128, sampleType: Sample256.self)
        }

        /// Benchmark sample capture with very deep stack (256 frames, Sample512)
        func testBenchmarkSampleCaptureVeryDeepStack() {
            profileThreadWithStackDepth(depth: 256, sampleType: Sample512.self)
        }

        // MARK: - Per-Sample Capture Latency Benchmarks

        /// Benchmark individual sample capture operations using ProfileMetrics.
        /// This measures the actual hot-path performance including allocation overhead.
        ///
        /// Profiles a thread holding a moderate (64-frame) stack at 1 ms over
        /// 1 s, so each iteration collects ~1000 samples — much more than the
        /// 5 sampling-scenario tests above. Per-sample average latency is
        /// emitted via `ProfilerSampleMetric` so the run shows up as a real
        /// row in the PR benchmark report.
        func testBenchmarkPerSampleCaptureLatency() {
            var targetThread: pthread_t?
            let readySemaphore = DispatchSemaphore(value: 0)
            let doneSemaphore = DispatchSemaphore(value: 0)

            // Create thread with moderate stack depth (64 frames)
            DispatchQueue.global().async {
                targetThread = pthread_self()
                self.recurseAndWait(depth: 64, ready: readySemaphore, done: doneSemaphore)
            }

            readySemaphore.wait()

            guard let thread = targetThread else {
                XCTFail("Failed to get target thread")
                doneSemaphore.signal()
                return
            }

            let profiler = Profiler<Sample128>(
                thread: thread,
                interval: 0.001,  // 1ms
                retentionSeconds: 5
            )

            measurePerSampleLatency {
                let id = profiler.beginProfile(named: "benchmark")
                Thread.sleep(forTimeInterval: 1.0)  // Collect ~1000 samples
                return profiler.endProfile(id: id)?.metrics
            }

            doneSemaphore.signal()
        }

        /// Benchmark per-sample capture with deep stacks (256 frames).
        ///
        /// Deep stacks with the comprehensive unwind (compact unwind +
        /// DWARF + frame pointer) take longer per sample, so the per-test
        /// thresholds in `benchmark-tests.json` are looser than the
        /// 64-frame variant.
        func testBenchmarkPerSampleCaptureLatencyDeepStack() {
            var targetThread: pthread_t?
            let readySemaphore = DispatchSemaphore(value: 0)
            let doneSemaphore = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                targetThread = pthread_self()
                self.recurseAndWait(depth: 256, ready: readySemaphore, done: doneSemaphore)
            }

            readySemaphore.wait()

            guard let thread = targetThread else {
                XCTFail("Failed to get target thread")
                doneSemaphore.signal()
                return
            }

            let profiler = Profiler<Sample512>(
                thread: thread,
                interval: 0.001,  // 1ms
                retentionSeconds: 5
            )

            measurePerSampleLatency {
                let id = profiler.beginProfile(named: "benchmark")
                Thread.sleep(forTimeInterval: 1.0)  // Collect ~1000 samples
                return profiler.endProfile(id: id)?.metrics
            }

            doneSemaphore.signal()
        }
    }
#endif
