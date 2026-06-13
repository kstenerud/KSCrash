//
//  ProfileInfo.swift
//
//  Created by Alexander Cohen on 2024-12-09.
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

/// Information about a profiling session captured in the crash report.
///
/// Profile reports contain sampled backtraces with frame deduplication to minimize file
/// size. The `frames` table is shared across every thread, and samples reference frames by
/// index. Samples are always grouped under `threads`, one entry per thread, with one flagged
/// primary, even a single-thread time profile uses a one-element `threads` array. There is
/// no separate top-level samples list, so a reader never has to choose between two shapes.
///
/// Two sources populate this model:
/// - A live time profile (`TimeProfiler`) records one sample per captured backtrace on a
///   single thread (`count == 1`), with per-sample timing.
/// - A hang (e.g. a MetricKit hang diagnostic) aggregates many samples across all threads
///   with no per-sample timing. Each sample carries a `count` (multiplicity) and only
///   `duration` is set at the profile level.
public struct ProfileInfo: Codable, Sendable, Equatable {
    /// Human-readable name for this profile session.
    public let name: String

    /// Unique identifier for this profile session (UUID string).
    public let id: String

    /// Wall-clock start time in nanoseconds since epoch. Nil when unknown (e.g. a hang
    /// reported from a previous process run).
    public let timeStartEpoch: UInt64?

    /// Monotonic start timestamp in nanoseconds. Nil for a hang: its monotonic clock comes
    /// from a previous process run and is not comparable here.
    public let timeStartUptime: UInt64?

    /// Monotonic end timestamp in nanoseconds. Nil for a hang (see ``timeStartUptime``).
    public let timeEndUptime: UInt64?

    /// Expected interval between samples in nanoseconds. Nil when the source does not
    /// report a configured interval (e.g. a hang).
    public let expectedSampleInterval: UInt64?

    /// Profile duration in nanoseconds. Always set. Its meaning depends on the report's
    /// `error.subtype`: for a time profile it is how long we observed; for a hang
    /// (`subtype == .hang`) it is how long the hang lasted.
    public let duration: UInt64

    /// Units for the time fields ("nanoseconds"). Applies to durations and timestamps only;
    /// per-sample ``ProfileSample/count`` values are unitless.
    public let timeUnits: String

    /// Array of unique symbolicated frames referenced by samples.
    public let frames: [StackFrame]

    /// Per-thread samples; one entry per thread, one flagged primary. A single-thread time
    /// profile has exactly one element.
    public let threads: [ProfileThread]

    public init(
        name: String,
        id: String,
        timeStartEpoch: UInt64? = nil,
        timeStartUptime: UInt64? = nil,
        timeEndUptime: UInt64? = nil,
        expectedSampleInterval: UInt64? = nil,
        duration: UInt64,
        timeUnits: String = "nanoseconds",
        frames: [StackFrame],
        threads: [ProfileThread]
    ) {
        self.name = name
        self.id = id
        self.timeStartEpoch = timeStartEpoch
        self.timeStartUptime = timeStartUptime
        self.timeEndUptime = timeEndUptime
        self.expectedSampleInterval = expectedSampleInterval
        self.duration = duration
        self.timeUnits = timeUnits
        self.frames = frames
        self.threads = threads
    }

    enum CodingKeys: String, CodingKey {
        case name
        case id
        case timeStartEpoch = "time_start_epoch"
        case timeStartUptime = "time_start_uptime"
        case timeEndUptime = "time_end_uptime"
        case expectedSampleInterval = "expected_sample_interval"
        case duration
        case timeUnits = "time_units"
        case frames
        case threads
    }
}

/// One thread's samples within a multi-thread profile.
public struct ProfileThread: Codable, Sendable, Equatable {
    /// Thread index within the profile.
    public let index: Int

    /// Whether this is the primary thread of interest (e.g. the main thread for a hang).
    public let primary: Bool

    /// Thread name, if known.
    public let name: String?

    /// Samples captured for this thread, each referencing frames by index into the
    /// enclosing ``ProfileInfo/frames`` table.
    public let samples: [ProfileSample]

    public init(index: Int, primary: Bool, name: String? = nil, samples: [ProfileSample]) {
        self.index = index
        self.primary = primary
        self.name = name
        self.samples = samples
    }

    enum CodingKeys: String, CodingKey {
        case index
        case primary
        case name
        case samples
    }
}

/// A captured sample in a profile.
///
/// Each sample references frames by index into the profile's frames array. `count` is the
/// number of times this stack was observed (always 1 for a live time profile, where each
/// captured backtrace is its own sample). Timing is independent and optional: a live time
/// profile fills it with the backtrace capture window, a hang has none.
public struct ProfileSample: Codable, Sendable, Equatable {
    /// Number of times this stack was observed.
    public let count: Int

    /// Monotonic timestamp when backtrace capture began. Nil for an aggregated hang sample.
    public let timeStartUptime: UInt64?

    /// Monotonic timestamp when backtrace capture completed. Nil for an aggregated hang sample.
    public let timeEndUptime: UInt64?

    /// Duration of the backtrace capture in nanoseconds. Nil for an aggregated hang sample.
    public let duration: UInt64?

    /// Indexes into the profile's frames array, deepest call first.
    public let frames: [Int]

    public init(
        count: Int = 1,
        timeStartUptime: UInt64? = nil,
        timeEndUptime: UInt64? = nil,
        duration: UInt64? = nil,
        frames: [Int]
    ) {
        self.count = count
        self.timeStartUptime = timeStartUptime
        self.timeEndUptime = timeEndUptime
        self.duration = duration
        self.frames = frames
    }

    enum CodingKeys: String, CodingKey {
        case count
        case timeStartUptime = "time_start_uptime"
        case timeEndUptime = "time_end_uptime"
        case duration
        case frames
    }
}
