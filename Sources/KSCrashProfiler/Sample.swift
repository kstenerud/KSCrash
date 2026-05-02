//
//  Sample.swift
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

// MARK: - Sample

/// A single backtrace sample captured during profiling.
///
/// `Sample` is a plain value type. Frame addresses are stored in a
/// right-sized `[UInt]` (length up to the profiler's `maxFrames`).
public struct Sample: Sendable {
    /// Timing metadata for this sample.
    public var metadata: SampleMetadata

    /// Captured stack frame addresses, deepest call first (matching the order
    /// produced by the unwinder). Length is at most the profiler's `maxFrames`.
    public var addresses: [UInt]

    /// Number of valid addresses captured. Equivalent to `addresses.count`.
    public var addressCount: Int { addresses.count }

    public init(metadata: SampleMetadata = SampleMetadata(), addresses: [UInt] = []) {
        self.metadata = metadata
        self.addresses = addresses
    }
}

// MARK: - Metadata

/// Timing metadata for a captured sample.
///
/// - `timestampBeginNs`: When backtrace capture began.
/// - `timestampEndNs`: When backtrace capture completed.
/// - `durationNs`: Time spent capturing the backtrace (computed).
public struct SampleMetadata: Sendable {
    /// Monotonic timestamp when backtrace capture began (nanoseconds from `CLOCK_UPTIME_RAW`).
    public var timestampBeginNs: UInt64 = 0

    /// Monotonic timestamp when backtrace capture completed (nanoseconds from `CLOCK_UPTIME_RAW`).
    public var timestampEndNs: UInt64 = 0

    /// Duration of the backtrace capture in nanoseconds.
    public var durationNs: UInt64 { timestampEndNs &- timestampBeginNs }

    public init(timestampBeginNs: UInt64 = 0, timestampEndNs: UInt64 = 0) {
        self.timestampBeginNs = timestampBeginNs
        self.timestampEndNs = timestampEndNs
    }
}
