//
//  ProfileExport+ChromeTrace.swift
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

// MARK: - Chrome Trace Export

extension ProfileInfo {

    /// Converts this profile to Chrome Trace Event format.
    ///
    /// - Returns: A `ChromeTrace` structure ready for encoding.
    public func toChromeTrace() -> ChromeTrace {
        var events: [ChromeTrace.Event] = []

        // Add metadata event for the profile name
        events.append(
            ChromeTrace.Event(
                name: "process_name",
                category: "__metadata",
                phase: .metadata,
                timestamp: 0,
                processID: 1,
                threadID: 0,
                args: ["name": name]
            ))

        // For each sample, emit complete events for each frame in the stack.
        // Use sample index * interval for timing to ensure non-overlapping samples.
        let sampleDuration = Double(expectedSampleInterval) / 1000.0  // Convert to microseconds

        for (sampleIndex, sample) in samples.enumerated() {
            // Use sample index for evenly spaced, non-overlapping samples
            let sampleTimestamp = Double(sampleIndex) * sampleDuration

            // Emit events for each frame (from root to leaf)
            for frameIndex in sample.frames.reversed() {
                let frame = frames[frameIndex]
                events.append(
                    ChromeTrace.Event(
                        name: frame.lossyDisplayName,
                        category: frame.objectName ?? "unknown",
                        phase: .complete,
                        timestamp: sampleTimestamp,
                        duration: sampleDuration,
                        processID: 1,
                        threadID: 1
                    ))
            }
        }

        return ChromeTrace(traceEvents: events, displayTimeUnit: .nanoseconds)
    }

    /// Exports this profile to Chrome Trace Event JSON format.
    ///
    /// The Chrome Trace format can be opened in Chrome DevTools (`chrome://tracing`)
    /// or Perfetto UI (https://ui.perfetto.dev) for visualization.
    ///
    /// - Returns: JSON data in Chrome Trace format.
    /// - Throws: An error if JSON encoding fails.
    public func exportToChromeTrace() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(toChromeTrace())
    }
}
