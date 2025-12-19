//
//  ProfileMetrics.swift
//
//  Created by Alexander Cohen on 2025-12-14.
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

import Foundation

/// Performance metrics computed from sample capture timings.
///
/// Provides statistical analysis of sample capture overhead, useful for understanding
/// profiler performance characteristics and tuning sampling intervals.
///
/// ## Example
///
/// ```swift
/// let metrics = profile.metrics
/// print("Captured \(metrics.count) samples")
/// print("Avg: \(metrics.avgNs / 1000)µs, P99: \(metrics.p99Ns / 1000)µs")
/// ```
///
/// All timing values represent `durationNs` from each sample's metadata.
public struct ProfileMetrics: Sendable {
    /// Per-sample capture timing in nanoseconds.
    public let sampleTimingsNs: [UInt64]

    /// Number of samples with timing data.
    public var count: Int { sampleTimingsNs.count }

    /// Minimum capture time in nanoseconds.
    public var minNs: UInt64 { sampleTimingsNs.min() ?? 0 }

    /// Maximum capture time in nanoseconds.
    public var maxNs: UInt64 { sampleTimingsNs.max() ?? 0 }

    /// Average (mean) capture time in nanoseconds.
    public var avgNs: Double {
        guard !sampleTimingsNs.isEmpty else { return 0 }
        return Double(sampleTimingsNs.reduce(0, +)) / Double(sampleTimingsNs.count)
    }

    /// Standard deviation of capture times in nanoseconds.
    ///
    /// Uses population standard deviation (divides by N, not N-1).
    public var stdDevNs: Double {
        guard sampleTimingsNs.count > 1 else { return 0 }
        let avg = avgNs
        let variance =
            sampleTimingsNs.map { pow(Double($0) - avg, 2) }.reduce(0, +)
            / Double(sampleTimingsNs.count)
        return sqrt(variance)
    }

    /// Returns the capture time at the given percentile.
    ///
    /// - Parameter p: Percentile value from 0 to 100.
    /// - Returns: The capture time at that percentile in nanoseconds.
    public func percentileNs(_ p: Double) -> UInt64 {
        guard !sampleTimingsNs.isEmpty else { return 0 }
        let sorted = sampleTimingsNs.sorted()
        let index = min(Int(Double(sorted.count) * p / 100.0), sorted.count - 1)
        return sorted[index]
    }

    /// P50 (median) capture time in nanoseconds.
    public var p50Ns: UInt64 { percentileNs(50) }

    /// P95 capture time in nanoseconds.
    public var p95Ns: UInt64 { percentileNs(95) }

    /// P99 capture time in nanoseconds.
    public var p99Ns: UInt64 { percentileNs(99) }

    /// Creates metrics from an array of samples.
    ///
    /// Extracts `durationNs` from each sample's metadata.
    internal init(samples: [any Sample]) {
        self.sampleTimingsNs = samples.map { $0.metadata.durationNs }
    }
}

extension Profile {

    /// Performance metrics computed from sample capture timings.
    ///
    /// This property is computed on demand. For repeated access, store the result
    /// in a local variable.
    public var metrics: ProfileMetrics {
        ProfileMetrics(samples: samples)
    }
}
