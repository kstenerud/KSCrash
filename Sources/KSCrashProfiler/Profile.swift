//
//  Profile.swift
//
//  Created by Alexander Cohen on 2026-05-10.
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

/// The result of a completed profiling session.
///
/// `Profile` describes the public surface common to every profile kind (time, allocation,
/// future variants): identity, time window, and report writing. Concrete profile types
/// (`TimeProfile`, future `AllocationProfile`) carry their own data alongside this surface
/// — samples and capture-timing metrics for `TimeProfile`, allocation events for an
/// allocation profile.
///
/// Callers that hold a concrete profile see all of its data directly. Callers that hold
/// `any Profile` can write reports and read the basic timing/identity fields, but must
/// downcast to inspect kind-specific data.
public protocol Profile: Sendable {
    /// Unique identifier for this profile session.
    var id: ProfileID { get }

    /// Human-readable name for this profile session.
    var name: String { get }

    /// Wall-clock time when profiling started.
    var startTime: Date { get }

    /// Monotonic timestamp when profiling started (nanoseconds from `CLOCK_UPTIME_RAW`).
    var startTimestampNs: UInt64 { get }

    /// Monotonic timestamp when profiling ended (nanoseconds from `CLOCK_UPTIME_RAW`).
    var endTimestampNs: UInt64 { get }

    /// Writes this profile to a crash report file.
    ///
    /// Performs synchronous disk I/O via the KSCrash report writing machinery. Call from
    /// a background queue or task to avoid blocking the main thread.
    ///
    /// - Returns: The URL of the written report file, or `nil` if the report could not be written.
    func writeReport() -> URL?
}

extension Profile {
    /// Total duration of this profile in nanoseconds.
    public var durationNs: UInt64 { endTimestampNs - startTimestampNs }
}
