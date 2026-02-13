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
/// with frame deduplication to minimize file size.
public struct ProfileInfo: Codable, Sendable {
    /// Human-readable name for this profile session.
    public let name: String

    /// Unique identifier for this profile session (UUID string).
    public let id: String

    /// Wall-clock start time in nanoseconds since epoch.
    public let timeStartEpoch: UInt64

    /// Monotonic start timestamp in nanoseconds.
    public let timeStartUptime: UInt64

    /// Monotonic end timestamp in nanoseconds.
    public let timeEndUptime: UInt64

    /// Expected interval between samples in nanoseconds.
    public let expectedSampleInterval: UInt64

    /// Profile duration in nanoseconds.
    public let duration: UInt64

    /// Time units used (typically "nanoseconds").
    public let timeUnits: String

    /// Array of unique symbolicated frames referenced by samples.
    public let frames: [StackFrame]

    /// Array of captured samples, each referencing frames by index.
    public let samples: [ProfileSample]

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
    }
}

/// A captured sample in a profile.
///
/// Each sample contains timing information and references to frames
/// by index into the profile's frames array.
public struct ProfileSample: Codable, Sendable {
    /// Monotonic timestamp when backtrace capture began.
    public let timeStartUptime: UInt64

    /// Monotonic timestamp when backtrace capture completed.
    public let timeEndUptime: UInt64

    /// Duration of the backtrace capture in nanoseconds.
    public let duration: UInt64

    /// Indexes into the profile's frames array.
    public let frames: [Int]

    enum CodingKeys: String, CodingKey {
        case timeStartUptime = "time_start_uptime"
        case timeEndUptime = "time_end_uptime"
        case duration
        case frames
    }
}
