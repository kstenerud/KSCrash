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
// timestamp, which a server can match against the run summaries it receives.

#if KSCRASH_HAS_METRICKIT_LEGACY

    /// The `monitor_data` section of a disk write report, under the MetricKit monitor's id.
    struct DiskWriteMonitorData: Codable, Equatable {
        static let kind = "disk_write_exception"

        let kind: String
        /// Total bytes the app wrote, as MetricKit measured them. Absent when the measurement is not
        /// a finite, non-negative number of bytes.
        let totalBytesWritten: UInt64?

        enum CodingKeys: String, CodingKey {
            case kind
            case totalBytesWritten = "total_bytes_written"
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
        /// - Returns: The report's error, or nil when the monitor data cannot be encoded.
        static func makeDiskWriteError(
            callStackTree: CallStackTreeRepresentation,
            totalBytesWritten: Measurement<UnitInformationStorage>
        ) -> CrashError? {
            let profileData = buildProfileData(from: callStackTree)
            let profile = ProfileInfo(
                name: "com.kscrash.profile.disk_writes",
                id: UUID().uuidString,
                // MetricKit gives neither when the writes it counted began nor how long they
                // took; the diagnostic's own time is the report's timestamp.
                timeStartEpoch: nil,
                duration: nil,
                frames: profileData.frames,
                threads: profileData.threads
            )

            let bytes = totalBytesWritten.converted(to: .bytes).value
            let monitorData = DiskWriteMonitorData(
                kind: DiskWriteMonitorData.kind,
                totalBytesWritten: bytes.isFinite && bytes >= 0 && bytes < Double(UInt64.max)
                    ? UInt64(bytes.rounded()) : nil
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
        /// The report is non-fatal and describes a moment in a run that kept going, so it is
        /// stored finalized and touches no current-run state.
        ///
        /// - Parameters:
        ///   - callStackTree: The diagnostic's sampled call stack tree.
        ///   - totalBytesWritten: The bytes MetricKit says the app wrote.
        ///   - timestamp: When MetricKit says it happened, as the delivering API reports it.
        ///   - applicationVersion: The app's version, for logging.
        ///   - systemInfo: Builds the report's system info from the skeleton report.
        /// - Returns: The stored report's id, or nil when it could not be written.
        @discardableResult
        func processDiskWrite(
            callStackTree: CallStackTreeRepresentation,
            totalBytesWritten: Measurement<UnitInformationStorage>,
            timestamp: Date,
            applicationVersion: String,
            systemInfo: (Report) -> SystemInfo
        ) -> Report.ID? {
            guard let tempURL = writeSkeletonReport() else { return nil }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            guard let data = try? Data(contentsOf: tempURL),
                let skeleton = try? JSONDecoder().decode(Report.self, from: data)
            else {
                os_log(
                    .error, log: metricKitLog, "[MONITORS] Failed to read or decode skeleton report at %{public}@",
                    tempURL.path
                )
                return nil
            }

            guard
                let error = Self.makeDiskWriteError(callStackTree: callStackTree, totalBytesWritten: totalBytesWritten)
            else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to build MetricKit disk write report")
                return nil
            }

            let newReport = Report(
                binaryImages: [],
                crash: Report.Crash(diagnosis: nil, error: error),
                debug: nil,
                process: nil,
                report: makeMetricKitReportInfo(skeleton: skeleton, timestamp: timestamp, runId: nil, finalized: true),
                system: systemInfo(skeleton)
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let newData = try? encoder.encode(newReport) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode MetricKit disk write report")
                return nil
            }

            guard let reportID = addMetricKitReport(newData) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to store MetricKit report")
                return nil
            }
            os_log(
                .default, log: metricKitLog,
                "[MONITORS] Added MetricKit disk write report (id=%{public}@, %d bytes, app %{public}@)",
                reportID.description, newData.count, applicationVersion)
            return reportID
        }

        /// The legacy `MXDiskWriteExceptionDiagnostic` path. `timestamp` is the payload's
        /// `timeStampEnd`.
        @discardableResult
        func processDiskWriteDiagnostic(_ diagnostic: MXDiskWriteExceptionDiagnostic, timestamp: Date) -> Report.ID? {
            processDiskWrite(
                callStackTree: diagnostic.callStackTree.representation ?? CallStackTreeRepresentation(callStacks: []),
                totalBytesWritten: diagnostic.totalWritesCaused,
                timestamp: timestamp,
                applicationVersion: diagnostic.applicationVersion
            ) { skeleton in
                self.buildSystemInfo(
                    metaData: diagnostic.metaData, applicationVersion: diagnostic.applicationVersion,
                    skeleton: skeleton)
            }
        }
    }

#endif
