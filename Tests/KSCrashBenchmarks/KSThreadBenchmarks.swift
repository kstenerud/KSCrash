//
//  KSThreadBenchmarks.swift
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

final class KSThreadBenchmarks: XCTestCase {

    // MARK: - Thread Self Benchmarks

    /// Benchmark getting the current thread ID
    func testBenchmarkThreadSelf() {
        measure {
            for _ in 0..<10000 {
                _ = ksthread_self()
            }
        }
    }

    // MARK: - Thread Name Benchmarks

    /// Benchmark getting the thread name
    func testBenchmarkGetThreadName() {
        let thread = ksthread_self()
        var buffer = [CChar](repeating: 0, count: 64)

        measure {
            for _ in 0..<1000 {
                _ = ksthread_getThreadName(thread, &buffer, 64)
            }
        }
    }

    // MARK: - Thread State Benchmarks

    /// Benchmark getting the thread state
    func testBenchmarkGetThreadState() {
        let thread = ksthread_self()

        measure {
            for _ in 0..<1000 {
                _ = ksthread_getThreadState(thread)
            }
        }
    }

    /// Benchmark converting thread state to name
    func testBenchmarkThreadStateName() {
        measure {
            for _ in 0..<10000 {
                _ = ksthread_state_name(1)  // TH_STATE_RUNNING
                _ = ksthread_state_name(2)  // TH_STATE_STOPPED
                _ = ksthread_state_name(3)  // TH_STATE_WAITING
            }
        }
    }

    // MARK: - Queue Name Benchmarks

    /// Benchmark getting the dispatch queue name
    func testBenchmarkGetQueueName() {
        let thread = ksthread_self()
        var buffer = [CChar](repeating: 0, count: 64)

        measure {
            for _ in 0..<1000 {
                _ = ksthread_getQueueName(thread, &buffer, 64)
            }
        }
    }

    // MARK: - Combined Operations (Crash Scenario)

    /// Benchmark typical thread info gathering during crash
    func testBenchmarkGatherThreadInfo() {
        let thread = ksthread_self()
        var nameBuffer = [CChar](repeating: 0, count: 64)
        var queueBuffer = [CChar](repeating: 0, count: 64)

        measure {
            // Simulate gathering info for multiple threads
            for _ in 0..<100 {
                _ = ksthread_getThreadName(thread, &nameBuffer, 64)
                _ = ksthread_getThreadState(thread)
                _ = ksthread_getQueueName(thread, &queueBuffer, 64)
            }
        }
    }

    // MARK: - Multi-threaded Scenarios

    /// Benchmark thread operations with multiple threads running
    func testBenchmarkThreadOpsWithConcurrency() {
        // Spawn some background threads to simulate typical app state
        let group = DispatchGroup()
        let threadCount = 10

        for _ in 0..<threadCount {
            group.enter()
            DispatchQueue.global(qos: .background).async {
                Thread.sleep(forTimeInterval: 2.0)  // Keep threads alive during benchmark
                group.leave()
            }
        }

        // Give threads time to start
        Thread.sleep(forTimeInterval: 0.1)

        let thread = ksthread_self()
        var nameBuffer = [CChar](repeating: 0, count: 64)

        measure {
            for _ in 0..<1000 {
                _ = ksthread_getThreadName(thread, &nameBuffer, 64)
                _ = ksthread_getThreadState(thread)
            }
        }

        // Don't wait for background threads - they'll be cleaned up
    }
}
