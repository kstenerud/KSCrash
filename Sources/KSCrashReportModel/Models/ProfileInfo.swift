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
/// Profile reports contain sampled backtraces captured during a profiling session,
/// with frame deduplication to minimize file size. The `frames` table is shared across
/// all samples (and all threads, when `threads` is used).
///
/// Two sources populate this model:
/// - A live time profile (`TimeProfiler`) records one sample per captured backtrace on a
///   single thread, with per-sample timing. It uses `samples` and fills every timing field.
/// - A hang (e.g. a MetricKit hang diagnostic) is an aggregate of many samples across all
///   threads with no per-sample timing. It uses `threads`, each sample carrying a `count`
///   (multiplicity) instead of timing, and fills only `duration` at the profile level.
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

    /// Profile duration in nanoseconds. Always set (for a hang this is the hang duration).
    public let duration: UInt64

    /// Time units used (typically "nanoseconds").
    public let timeUnits: String

    /// Array of unique symbolicated frames referenced by samples.
    public let frames: [StackFrame]

    /// Single-thread samples, each referencing frames by index. Used by live time profiles.
    /// Empty for multi-thread profiles, which use ``threads`` instead.
    public let samples: [ProfileSample]

    /// Per-thread samples for a multi-thread profile (e.g. a hang covering all threads).
    /// When non-nil this takes precedence over ``samples``; one thread is flagged primary.
    public let threads: [ProfileThread]?

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
        samples: [ProfileSample] = [],
        threads: [ProfileThread]? = nil
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
        self.samples = samples
        self.threads = threads
    }

    /// Per-thread samples normalized across both shapes: returns ``threads`` when present,
    /// otherwise wraps the single-thread ``samples`` as one primary thread. Lets a consumer
    /// read every profile the same way regardless of source.
    public var threadSamples: [ProfileThread] {
        if let threads { return threads }
        return [ProfileThread(index: 0, primary: true, name: nil, samples: samples)]
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
        case samples
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
/// Each sample references frames by index into the profile's frames array. A live time
/// profile sample carries capture timing (`timeStartUptime`/`timeEndUptime`/`duration`)
/// and an implicit count of 1. A hang sample carries a `count` (how many times the stack
/// was observed in the window) and no timing.
///
/// Invariant: if `count > 1`, the timing fields are nil; if timing is present, `count` is
/// 1 (or absent). A single sample never has both a multiplicity and a single timestamp.
public struct ProfileSample: Codable, Sendable, Equatable {
    /// Monotonic timestamp when backtrace capture began. Nil for an aggregated hang sample.
    public let timeStartUptime: UInt64?

    /// Monotonic timestamp when backtrace capture completed. Nil for an aggregated hang sample.
    public let timeEndUptime: UInt64?

    /// Duration of the backtrace capture in nanoseconds. Nil for an aggregated hang sample.
    public let duration: UInt64?

    /// Number of times this stack was observed. Absent means 1.
    public let count: Int?

    /// Indexes into the profile's frames array, deepest call first.
    public let frames: [Int]

    /// Observed multiplicity, treating an absent ``count`` as 1.
    public var effectiveCount: Int { count ?? 1 }

    public init(
        timeStartUptime: UInt64? = nil,
        timeEndUptime: UInt64? = nil,
        duration: UInt64? = nil,
        count: Int? = nil,
        frames: [Int]
    ) {
        self.timeStartUptime = timeStartUptime
        self.timeEndUptime = timeEndUptime
        self.duration = duration
        self.count = count
        self.frames = frames
    }

    enum CodingKeys: String, CodingKey {
        case timeStartUptime = "time_start_uptime"
        case timeEndUptime = "time_end_uptime"
        case duration
        case count
        case frames
    }
}
