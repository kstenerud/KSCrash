//
//  MetricKitMonitor+DiskWriteDiagnostic.swift
//
//  Created by Alexander Cohen on 2026-11-01.
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

// MARK: - Disk Write Diagnostic Handling
//
// A disk write exception says the app wrote more to disk than the OS allows in a day. Its call
// stack tree is a sampled trie of where the writes happened (MetricKit merges every thread into
// one), so like a hang it becomes a profile report: error.type == .profile, tagged
// error.subtype == .diskWrites. Everything specific to disk writes goes in the report's
// monitor_data under the monitor's id.
//
// The tree carries no threadcrumb, so the report has no run ID. It carries the process ID and
// MetricKit's time range, which a server can match against the run summaries it receives.

#if KSCRASH_HAS_METRICKIT_LEGACY

    /// The `monitor_data` section of a disk write report, under the MetricKit monitor's id.
    struct DiskWriteMonitorData: Codable, Equatable {
        static let kind = "disk_write_exception"

        let kind: String
        /// Total bytes the app wrote, as MetricKit measured them. Absent when the measurement is not
        /// a finite, non-negative number of bytes.
        let totalBytesWritten: UInt64?
        let timeRange: MetricKitTimeRange

        enum CodingKeys: String, CodingKey {
            case kind
            case totalBytesWritten = "total_bytes_written"
            case timeRange = "time_range"
        }
    }

    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    extension MetricKitMonitor {

        /// Builds the error of a disk write report from either MetricKit API's diagnostic.
        ///
        /// - Parameters:
        ///   - callStackTree: The diagnostic's sampled call stack tree.
        ///   - totalBytesWritten: The bytes MetricKit says the app wrote.
        ///   - timeRange: The period MetricKit gives for the diagnostic.
        /// - Returns: The report's error, or nil when the monitor data cannot be encoded.
        static func makeDiskWriteError(
            callStackTree: CallStackTreeRepresentation,
            totalBytesWritten: Measurement<UnitInformationStorage>,
            timeRange: MetricKitTimeRange
        ) -> CrashError? {
            let profileData = buildProfileData(from: callStackTree)
            let profile = ProfileInfo(
                name: "com.kscrash.profile.disk_writes",
                id: UUID().uuidString,
                // MetricKit gives neither when the writes it counted began nor how long they
                // took; the period it does give is in the monitor data.
                timeStartEpoch: nil,
                duration: nil,
                frames: profileData.frames,
                threads: profileData.threads
            )

            let bytes = totalBytesWritten.converted(to: .bytes).value
            let monitorData = DiskWriteMonitorData(
                kind: DiskWriteMonitorData.kind,
                totalBytesWritten: bytes.isFinite && bytes >= 0 && bytes < Double(UInt64.max)
                    ? UInt64(bytes.rounded()) : nil,
                timeRange: timeRange
            )
            guard let encoded = try? JSONEncoder().encode(monitorData),
                let section = try? JSONDecoder().decode(Metadata.self, from: encoded)
            else { return nil }

            return CrashError(
                type: .profile,
                subtype: .diskWrites,
                profile: profile,
                isFatal: false,
                monitorData: [id: section]
            )
        }

        /// Turns a disk write exception diagnostic from either MetricKit API into a stored report.
        ///
        /// - Parameters:
        ///   - callStackTree: The diagnostic's sampled call stack tree.
        ///   - totalBytesWritten: The bytes MetricKit says the app wrote.
        ///   - timeRange: The period MetricKit gives for the diagnostic.
        ///   - applicationVersion: The app's version, for logging.
        ///   - systemInfo: Builds the report's system info from the skeleton report.
        /// - Returns: The stored report's id, or nil when it could not be written.
        @discardableResult
        func processDiskWrite(
            callStackTree: CallStackTreeRepresentation,
            totalBytesWritten: Measurement<UnitInformationStorage>,
            timeRange: MetricKitTimeRange,
            applicationVersion: String,
            systemInfo: (Report) -> SystemInfo
        ) -> Report.ID? {
            guard
                let error = Self.makeDiskWriteError(
                    callStackTree: callStackTree, totalBytesWritten: totalBytesWritten, timeRange: timeRange)
            else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to build MetricKit disk write report")
                return nil
            }
            return storeRunlessProfileReport(
                error, kind: "disk write", timestamp: timeRange.end, applicationVersion: applicationVersion,
                systemInfo: systemInfo)
        }

        /// The legacy `MXDiskWriteExceptionDiagnostic` path. `timeRange` is the payload's.
        @discardableResult
        func processDiskWriteDiagnostic(
            _ diagnostic: MXDiskWriteExceptionDiagnostic, timeRange: MetricKitTimeRange
        ) -> Report.ID? {
            processDiskWrite(
                callStackTree: diagnostic.callStackTree.representation ?? CallStackTreeRepresentation(callStacks: []),
                totalBytesWritten: diagnostic.totalWritesCaused,
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
