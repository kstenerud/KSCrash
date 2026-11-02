//
//  MetricKitMonitor+CPUExceptionDiagnostic.swift
//
//  Created by Alexander Cohen on 2026-11-02.
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
import KSCrashReportModel
import os.log

#if KSCRASH_HAS_METRICKIT_LEGACY
    import MetricKit
#endif

// MARK: - CPU Exception Diagnostic Handling
//
// A CPU exception says the app used more CPU than the OS allows. Its call stack tree is a sampled
// trie of where that CPU time went (MetricKit merges every thread into one), so like a disk write
// exception it becomes a profile report: error.type == .profile, tagged error.subtype == .cpuUsage.
// Everything specific to CPU goes in the report's monitor_data under the monitor's id.
//
// The tree carries no threadcrumb, so the report has no run ID. It carries the process ID and
// MetricKit's time range, which a server can match against the run summaries it receives.

#if KSCRASH_HAS_METRICKIT_LEGACY

    /// The `monitor_data` section of a CPU exception report, under the MetricKit monitor's id.
    struct CPUExceptionMonitorData: Codable, Equatable {
        static let kind = "cpu_exception"

        let kind: String
        /// CPU time the app used, in nanoseconds. Absent when MetricKit's measurement is not a
        /// finite, non-negative duration.
        let totalCPUTimeNs: UInt64?
        /// How long MetricKit sampled the app, in nanoseconds. Absent on the same terms.
        let totalSampledTimeNs: UInt64?
        let timeRange: MetricKitTimeRange

        enum CodingKeys: String, CodingKey {
            case kind
            case totalCPUTimeNs = "total_cpu_time_ns"
            case totalSampledTimeNs = "total_sampled_time_ns"
            case timeRange = "time_range"
        }
    }

    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    extension MetricKitMonitor {

        /// Builds the error of a CPU exception report from either MetricKit API's diagnostic.
        ///
        /// - Parameters:
        ///   - callStackTree: The diagnostic's sampled call stack tree.
        ///   - totalCPUTime: The CPU time MetricKit says the app used.
        ///   - totalSampledTime: How long MetricKit says it sampled the app.
        ///   - timeRange: The period MetricKit gives for the diagnostic.
        /// - Returns: The report's error, or nil when the monitor data cannot be encoded.
        static func makeCPUExceptionError(
            callStackTree: CallStackTreeRepresentation,
            totalCPUTime: Measurement<UnitDuration>,
            totalSampledTime: Measurement<UnitDuration>,
            timeRange: MetricKitTimeRange
        ) -> CrashError? {
            let sampledNs = nanosToUInt64(totalSampledTime.converted(to: .seconds).value * 1_000_000_000)
            let profileData = buildProfileData(from: callStackTree)
            let profile = ProfileInfo(
                name: "com.kscrash.profile.cpu_usage",
                id: UUID().uuidString,
                // MetricKit says how long it sampled but not when it started.
                timeStartEpoch: nil,
                duration: sampledNs,
                frames: profileData.frames,
                threads: profileData.threads
            )

            let monitorData = CPUExceptionMonitorData(
                kind: CPUExceptionMonitorData.kind,
                totalCPUTimeNs: nanosToUInt64(totalCPUTime.converted(to: .seconds).value * 1_000_000_000),
                totalSampledTimeNs: sampledNs,
                timeRange: timeRange
            )
            guard let encoded = try? JSONEncoder().encode(monitorData),
                let section = try? JSONDecoder().decode(Metadata.self, from: encoded)
            else { return nil }

            return CrashError(
                type: .profile,
                subtype: .cpuUsage,
                profile: profile,
                isFatal: false,
                monitorData: [id: section]
            )
        }

        /// Turns a CPU exception diagnostic from either MetricKit API into a stored report.
        ///
        /// - Parameters:
        ///   - callStackTree: The diagnostic's sampled call stack tree.
        ///   - totalCPUTime: The CPU time MetricKit says the app used.
        ///   - totalSampledTime: How long MetricKit says it sampled the app.
        ///   - timeRange: The period MetricKit gives for the diagnostic.
        ///   - applicationVersion: The app's version, for logging.
        ///   - systemInfo: Builds the report's system info from the skeleton report.
        /// - Returns: The stored report's id, or nil when it could not be written.
        @discardableResult
        func processCPUException(
            callStackTree: CallStackTreeRepresentation,
            totalCPUTime: Measurement<UnitDuration>,
            totalSampledTime: Measurement<UnitDuration>,
            timeRange: MetricKitTimeRange,
            applicationVersion: String,
            systemInfo: (Report) -> SystemInfo
        ) -> Report.ID? {
            guard
                let error = Self.makeCPUExceptionError(
                    callStackTree: callStackTree, totalCPUTime: totalCPUTime, totalSampledTime: totalSampledTime,
                    timeRange: timeRange)
            else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to build MetricKit CPU exception report")
                return nil
            }
            return storeRunlessProfileReport(
                error, kind: "CPU exception", timestamp: timeRange.end, applicationVersion: applicationVersion,
                systemInfo: systemInfo)
        }

        /// The legacy `MXCPUExceptionDiagnostic` path. `timeRange` is the payload's.
        @discardableResult
        func processCPUExceptionDiagnostic(
            _ diagnostic: MXCPUExceptionDiagnostic, timeRange: MetricKitTimeRange
        ) -> Report.ID? {
            processCPUException(
                callStackTree: diagnostic.callStackTree.representation ?? CallStackTreeRepresentation(callStacks: []),
                totalCPUTime: diagnostic.totalCPUTime,
                totalSampledTime: diagnostic.totalSampledTime,
                timeRange: timeRange,
                applicationVersion: diagnostic.applicationVersion
            ) { skeleton in
                self.buildSystemInfo(
                    metaData: diagnostic.metaData, applicationVersion: diagnostic.applicationVersion,
                    skeleton: skeleton)
            }
        }
    }

#endif
