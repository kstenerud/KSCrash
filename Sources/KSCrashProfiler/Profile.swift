//
//  Profile.swift
//
//  Created by Alexander Cohen on 2025-12-12.
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

/// Unique identifier for a profiling session.
public typealias ProfileID = UUID

/// A completed profile containing timing information and captured samples.
///
/// A `Profile` represents the results of a profiling session between `beginProfile()` and
/// `endProfile()` calls. It contains all samples captured during that time window, along
/// with timing metadata.
///
/// ## Example
///
/// ```swift
/// let profile = profiler.endProfile(id: profileId)!
/// print("Duration: \(Double(profile.durationNs) / 1_000_000)ms")
/// print("Samples: \(profile.samples.count)")
/// print("Avg capture time: \(profile.metrics.avgNs / 1000)µs")
/// ```
public struct Profile: Sendable {
    /// Unique identifier for this profile session.
    public let id: ProfileID

    /// Wall-clock time when profiling started.
    ///
    /// Use this for correlating with external events or logs. For duration calculations,
    /// use the monotonic timestamps instead.
    public let startTime: Date

    /// Monotonic timestamp when profiling started (nanoseconds from `CLOCK_UPTIME_RAW`).
    public let startTimestampNs: UInt64

    /// Monotonic timestamp when profiling ended (nanoseconds from `CLOCK_UPTIME_RAW`).
    public let endTimestampNs: UInt64

    /// Expected interval between samples in nanoseconds.
    ///
    /// This is the configured sampling interval. Actual intervals may vary slightly
    /// due to timer precision and system load.
    public let expectedSampleIntervalNs: UInt64

    /// Captured backtrace samples within this profile's time window.
    ///
    /// Samples are returned in chronological order. Only samples whose capture time
    /// overlaps with `[startTimestampNs, endTimestampNs]` are included.
    public let samples: [any Sample]

    /// Total duration of this profile in nanoseconds.
    public var durationNs: UInt64 {
        endTimestampNs - startTimestampNs
    }

    /// Performance metrics computed from sample capture timings.
    ///
    /// This property is computed on demand. For repeated access, store the result
    /// in a local variable.
    public var metrics: ProfileMetrics {
        ProfileMetrics(samples: samples)
    }

    internal init(
        id: ProfileID,
        startTime: Date,
        startTimestampNs: UInt64,
        endTimestampNs: UInt64,
        expectedSampleIntervalNs: UInt64,
        samples: [any Sample]
    ) {
        self.id = id
        self.startTime = startTime
        self.startTimestampNs = startTimestampNs
        self.endTimestampNs = endTimestampNs
        self.expectedSampleIntervalNs = expectedSampleIntervalNs
        self.samples = samples
    }
}
