//
//  MetricKitMonitor+HangDiagnostic.swift
//
//  Created by Alexander Cohen on 2026-02-05.
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
import KSCrashRecording
import KSCrashReportModel
import os.log

#if KSCRASH_HAS_METRICKIT
    import MetricKit
#endif

// MARK: - Hang Diagnostic Handling

#if KSCRASH_HAS_METRICKIT

    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    extension MetricKitMonitor {

        // MetricKit "Main Runloop Hang" diagnostics attribute the hang to the main thread,
        // which MetricKit always reports as call stack index 0.
        private static let mainRunloopHangThreadIndex = 0

        @discardableResult
        func processHangDiagnostic(_ diagnostic: MXHangDiagnostic, timestamp: Date) -> Report.ID? {
            guard let tempURL = writeSkeletonReport() else { return nil }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            return postProcessHangReport(atPath: tempURL.path, diagnostic: diagnostic, timestamp: timestamp)
        }

        // A hang diagnostic is a sampling profile of the hang window. We keep the report in
        // the profile lane (error.type == .profile) and tag it with the generic
        // error.subtype == .hang, rather than inventing a fatal error type. The report is
        // non-fatal and describes a previous window, so it must not touch current-run state.
        private func postProcessHangReport(atPath path: String, diagnostic: MXHangDiagnostic, timestamp: Date)
            -> Report.ID?
        {
            let url = URL(fileURLWithPath: path)

            guard let data = try? Data(contentsOf: url),
                let report = try? JSONDecoder().decode(Report.self, from: data)
            else {
                os_log(
                    .error, log: metricKitLog, "[MONITORS] Failed to read or decode skeleton report at %{public}@",
                    path
                )
                return nil
            }

            // The hang's call stack tree is a sample-merged trie across all threads. Convert
            // it to weighted per-thread samples for the profile body. The main thread is the
            // subject of a Main Runloop Hang.
            let profileData = diagnostic.callStackTree.extractProfileData(
                primaryThreadIndex: Self.mainRunloopHangThreadIndex)
            // The threadcrumb run ID lives in a flat per-thread backtrace, so decode it from
            // the crash-style extraction (cheap second pass over the same tree).
            let callStackData = diagnostic.callStackTree.extractCallStackData()

            let hangNs = diagnostic.hangDuration.converted(to: .seconds).value * 1_000_000_000
            guard let durationNs = nanosToUInt64(hangNs) else {
                os_log(
                    .error, log: metricKitLog, "[MONITORS] Skipping hang report with invalid duration at %{public}@",
                    path
                )
                return nil
            }

            let profile = ProfileInfo(
                name: "com.kscrash.profile.hang",
                id: UUID().uuidString,
                timeStartEpoch: epochNanos(for: timestamp, minus: durationNs),
                duration: durationNs,
                frames: profileData.frames,
                threads: profileData.threads
            )

            let newError = CrashError(
                type: .profile,
                subtype: .hang,
                profile: profile,
                isFatal: false
            )

            let newCrash = Report.Crash(diagnosis: nil, error: newError)

            let newSystem = buildSystemInfo(
                metaData: diagnostic.metaData,
                applicationVersion: diagnostic.applicationVersion,
                skeleton: report
            )

            let crashedRunId = runIdHandler.decode(from: callStackData) { name, ext in
                self.sidecarPathProvider(name: name, extension: ext)
            }

            // A hang is a moment within a run that kept going, so its last-moment run sidecar
            // does not align: finalized, so the store leaves it alone (see makeMetricKitReportInfo).
            let reportInfo = makeMetricKitReportInfo(
                skeleton: report, timestamp: timestamp, runId: crashedRunId, finalized: true)
            let newReport = Report(
                binaryImages: [],
                crash: newCrash,
                debug: nil,
                process: nil,
                report: reportInfo,
                system: newSystem
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let newData = try? encoder.encode(newReport) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode MetricKit hang report")
                return nil
            }

            guard let reportID = addMetricKitReport(newData) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to store MetricKit report")
                return nil
            }
            os_log(
                .default, log: metricKitLog,
                "[MONITORS] Added MetricKit hang report (id=%{public}@, %d bytes, %d threads, app %{public}@, runId=%{public}@)",
                reportID.description, newData.count, profileData.threads.count, diagnostic.applicationVersion,
                crashedRunId ?? "none")
            return reportID
        }

        // MARK: - Hang Helpers

        /// Converts a nanosecond count to `UInt64`, returning nil for non-finite, negative, or
        /// out-of-range values rather than trapping on the cast.
        private func nanosToUInt64(_ ns: Double) -> UInt64? {
            guard ns.isFinite, ns >= 0, ns < Double(UInt64.max) else { return nil }
            return UInt64(ns.rounded())
        }

        /// Wall-clock start estimate for a hang window: the payload end timestamp minus the
        /// hang duration. Returns nil if the timestamp is out of range or the subtraction
        /// would underflow.
        private func epochNanos(for timestamp: Date, minus durationNs: UInt64) -> UInt64? {
            guard let end = nanosToUInt64(timestamp.timeIntervalSince1970 * 1_000_000_000) else { return nil }
            return end >= durationNs ? end - durationNs : nil
        }
    }

#endif
