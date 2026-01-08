//
//  ChromeTrace.swift
//
//  Created by Alexander Cohen on 2026-01-08.
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

/// Chrome Trace Event Format for visualization in Chrome DevTools and Perfetto.
///
/// This format is compatible with:
/// - Chrome DevTools (`chrome://tracing`)
/// - Perfetto UI (https://ui.perfetto.dev)
/// - Catapult trace viewer
///
/// The format uses JSON with an array of trace events. Each sample is represented
/// as a complete event ("X" phase) showing the full call stack.
///
/// Note: All timestamps in events are specified in **microseconds** as required by the format.
/// The `displayTimeUnit` only affects UI display formatting, not the actual values.
///
/// See: https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU
public struct ChromeTrace: Encodable, Sendable {
    /// Array of trace events.
    public let traceEvents: [Event]

    /// Display time unit hint for the viewer UI.
    /// This affects how times are formatted for display, not the actual timestamp values.
    public let displayTimeUnit: DisplayTimeUnit

    public init(traceEvents: [Event], displayTimeUnit: DisplayTimeUnit = .milliseconds) {
        self.traceEvents = traceEvents
        self.displayTimeUnit = displayTimeUnit
    }

    // MARK: - Display Time Unit

    /// Display time unit hint for the trace viewer UI.
    public enum DisplayTimeUnit: String, Encodable, Sendable {
        /// Display times in milliseconds.
        case milliseconds = "ms"
        /// Display times in nanoseconds.
        case nanoseconds = "ns"
    }

    // MARK: - Event Phase

    /// Phase type for trace events.
    public enum Phase: String, Encodable, Sendable {
        /// Duration event begin.
        case begin = "B"
        /// Duration event end.
        case end = "E"
        /// Complete event (begin + end combined).
        case complete = "X"
        /// Instant event.
        case instant = "i"
        /// Metadata event.
        case metadata = "M"
    }

    // MARK: - Event

    /// A single trace event.
    ///
    /// All time values (timestamp, duration) are in **microseconds**.
    public struct Event: Encodable, Sendable {
        /// Event name (typically the function/symbol name).
        public let name: String

        /// Event category.
        public let category: String

        /// Event phase type.
        public let phase: Phase

        /// Timestamp in microseconds since trace start.
        public let timestamp: Double

        /// Duration in microseconds (for complete events).
        public let duration: Double?

        /// Process ID.
        public let processID: Int

        /// Thread ID.
        public let threadID: Int

        /// Stack frame reference (for sampling).
        public let stackFrame: Int?

        /// Additional arguments.
        public let args: [String: String]?

        public init(
            name: String,
            category: String = "profile",
            phase: Phase,
            timestamp: Double,
            duration: Double? = nil,
            processID: Int = 1,
            threadID: Int = 1,
            stackFrame: Int? = nil,
            args: [String: String]? = nil
        ) {
            self.name = name
            self.category = category
            self.phase = phase
            self.timestamp = timestamp
            self.duration = duration
            self.processID = processID
            self.threadID = threadID
            self.stackFrame = stackFrame
            self.args = args
        }

        enum CodingKeys: String, CodingKey {
            case name
            case category = "cat"
            case phase = "ph"
            case timestamp = "ts"
            case duration = "dur"
            case processID = "pid"
            case threadID = "tid"
            case stackFrame = "sf"
            case args
        }
    }
}
