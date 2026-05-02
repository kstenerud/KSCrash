//
//  ProfilerSampleMetric.swift
//
//  Created by Alexander Cohen on 2026-05-02.
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

import XCTest

#if !os(watchOS)
    /// Closure-backed `XCTMetric` for emitting custom benchmark numbers into
    /// the xcresult bundle.
    ///
    /// The xcresult-driven CI pipeline (`.github/scripts/parse_benchmarks.py`)
    /// only sees what XCTest records as a metric; anything `print()`ed to the
    /// test log is invisible. We use this metric to surface per-sample
    /// profiler latency (computed from `Profile.metrics`) for tests where the
    /// default wall-clock-time metric would just measure the surrounding
    /// `Thread.sleep` instead of profiler overhead.
    ///
    /// Threading: XCTest copies the metric per iteration, but iterations run
    /// sequentially. The `valueProvider` closure typically captures a `var` in
    /// the test scope, which all copies read; each iteration's block updates
    /// that `var` before `didStopMeasuring` runs on its copy. Each copy stores
    /// its own `capturedValue`, so values from one iteration cannot bleed into
    /// another.
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
    final class ProfilerSampleMetric: NSObject, XCTMetric {

        private let metricIdentifier: String
        private let metricDisplayName: String
        private let valueProvider: () -> Double
        private var capturedValue: Double = 0

        /// - Parameters:
        ///   - identifier: Stable identifier emitted into the xcresult. The
        ///     report parser matches on this; do not change without updating
        ///     `.github/scripts/parse_benchmarks.py`.
        ///   - displayName: Human-readable name shown by xcresulttool.
        ///   - valueProvider: Called from `didStopMeasuring` to read the
        ///     value for the just-finished iteration. Must return seconds so
        ///     the parser's existing `format_time` and threshold logic apply.
        init(
            identifier: String,
            displayName: String,
            valueProvider: @escaping () -> Double
        ) {
            self.metricIdentifier = identifier
            self.metricDisplayName = displayName
            self.valueProvider = valueProvider
        }

        func reportMeasurements(
            from startTime: XCTPerformanceMeasurementTimestamp,
            to endTime: XCTPerformanceMeasurementTimestamp
        ) throws -> [XCTPerformanceMeasurement] {
            return [
                XCTPerformanceMeasurement(
                    identifier: metricIdentifier,
                    displayName: metricDisplayName,
                    doubleValue: capturedValue,
                    unitSymbol: "s",
                    polarity: .prefersSmaller
                )
            ]
        }

        func willBeginMeasuring() {
            capturedValue = 0
        }

        func didStopMeasuring() {
            capturedValue = valueProvider()
        }

        func copy(with zone: NSZone? = nil) -> Any {
            return ProfilerSampleMetric(
                identifier: metricIdentifier,
                displayName: metricDisplayName,
                valueProvider: valueProvider
            )
        }
    }
#endif
