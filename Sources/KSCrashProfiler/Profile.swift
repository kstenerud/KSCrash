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

/// Unique identifier for a profiling session
public typealias ProfileID = UUID

/// A single captured backtrace sample with timestamp
public struct Sample: Sendable {
    /// The monotonic timestamp in nanoseconds when capture started
    public let timestampBeginNs: UInt64

    /// The monotonic timestamp in nanoseconds when capture ended
    public let timestampEndNs: UInt64

    /// The captured backtrace addresses
    public let addresses: [UInt]

    /// The duration of the capture in nanoseconds
    public var captureDurationNs: UInt64 {
        timestampEndNs - timestampBeginNs
    }

    internal init(timestampBeginNs: UInt64, timestampEndNs: UInt64, addresses: [UInt]) {
        self.timestampBeginNs = timestampBeginNs
        self.timestampEndNs = timestampEndNs
        self.addresses = addresses
    }
}

/// A completed profile containing timing information and captured samples.
public struct Profile: Sendable {
    /// Unique identifier for this profile
    public let id: ProfileID

    /// The wall clock time when profiling started
    public let startTime: Date

    /// The monotonic timestamp in nanoseconds when profiling started
    public let startTimestampNs: UInt64

    /// The monotonic timestamp in nanoseconds when profiling ended
    public let endTimestampNs: UInt64

    /// The expected interval between samples in nanoseconds
    public let expectedSampleIntervalNs: UInt64

    /// The captured backtrace samples within this profile's time window
    public let samples: [Sample]

    /// The total duration of this profile in nanoseconds
    public var durationNs: UInt64 {
        endTimestampNs - startTimestampNs
    }

    internal init(
        id: ProfileID,
        startTime: Date,
        startTimestampNs: UInt64,
        endTimestampNs: UInt64,
        expectedSampleIntervalNs: UInt64,
        samples: [Sample]
    ) {
        self.id = id
        self.startTime = startTime
        self.startTimestampNs = startTimestampNs
        self.endTimestampNs = endTimestampNs
        self.expectedSampleIntervalNs = expectedSampleIntervalNs
        self.samples = samples
    }
}
