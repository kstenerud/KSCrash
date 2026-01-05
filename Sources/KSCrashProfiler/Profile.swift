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
/// A `Profile` represents the results of a profiling session between `beginProfile(named:)` and
/// `endProfile(id:)` calls. It contains all samples captured during that time window, along
/// with timing metadata.
///
/// To write the profile to a crash report, call `writeReport()`. Since this performs synchronous
/// disk I/O, it should be called from a background queue.
///
/// ## Example
///
/// ```swift
/// let id = profiler.beginProfile(named: "MyOperation")
/// // ... do work ...
/// let profile = profiler.endProfile(id: id)!
/// print("Profile: \(profile.name)")
/// print("Duration: \(Double(profile.durationNs) / 1_000_000)ms")
///
/// DispatchQueue.global().async {
///     if let url = profile.writeReport() {
///         print("Report written to: \(url.path)")
///     }
/// }
/// ```
public struct Profile: Sendable {
    /// Unique identifier for this profile session.
    public let id: ProfileID

    /// Human-readable name for this profile session.
    ///
    /// This is the name provided to `beginProfile(named:)`. Use it to identify
    /// the operation or code path being profiled.
    public let name: String

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

    /// Writes this profile to a crash report file.
    ///
    /// This method triggers the KSCrash report writing machinery to generate a JSON report
    /// containing the profile data. The report is written synchronously to the KSCrash
    /// reports directory.
    ///
    /// - Returns: The URL of the written report file, or `nil` if the report could not be written.
    ///
    /// - Note: This method performs synchronous disk I/O and should be called from a background
    ///   queue or task to avoid blocking the main thread.
    public func writeReport() -> URL? {
        _writeReport()
    }

    /// The Mach thread port of the thread that was profiled.
    ///
    /// This is the thread from which backtraces were captured during the profiling session.
    /// Note that this is a Mach thread port (`thread_t`), not a pthread.
    public let thread: thread_t

    internal init(
        id: ProfileID,
        name: String,
        thread: thread_t,
        startTime: Date,
        startTimestampNs: UInt64,
        endTimestampNs: UInt64,
        expectedSampleIntervalNs: UInt64,
        samples: [any Sample]
    ) {
        self.id = id
        self.name = name
        self.thread = thread
        self.startTime = startTime
        self.startTimestampNs = startTimestampNs
        self.endTimestampNs = endTimestampNs
        self.expectedSampleIntervalNs = expectedSampleIntervalNs
        self.samples = samples
    }
}
