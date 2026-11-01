//
//  MetricKitMonitor+MemoryDiagnostic.swift
//
//  Created by Alexander Cohen on 2026-06-21.
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

#if KSCRASH_HAS_METRICKIT_LEGACY
    import MetricKit
#endif

// MARK: - Memory Exception Diagnostics (iOS 27+)
//
// Handling for the iOS 27 `MemoryExceptionDiagnostic`, the OOM-style termination that finally
// carries a call stack. Delivery lives in MetricKitMonitor+DiagnosticStream; this file turns each
// delivered diagnostic into a report. A memory exception is modelled like the heuristic OOMs: a
// fatal `.termination` with `terminationReason == .memoryLimit` and
// `subtype == .memoryException`.
//
// The `.memoryException` result is iOS-only (unavailable on macOS, Mac Catalyst and visionOS),
// and the API needs the iOS 27 SDK, so this file compiles only under KSCRASH_HAS_METRICKIT_27_PLUS
// when targeting iOS device or simulator.

#if KSCRASH_HAS_METRICKIT_27_PLUS && os(iOS) && !targetEnvironment(macCatalyst)

    @available(iOS 27.0, *)
    extension MetricKitMonitor {

        /// Turns a memory exception into a stored report.
        ///
        /// - Parameters:
        ///   - diagnostic: The delivered memory exception.
        ///   - timestamp: When the process was killed.
        ///   - systemInfo: Builds the report's system info from the skeleton report.
        /// - Returns: The stored report's id, or nil when it could not be written.
        func processMemoryException(
            _ diagnostic: MemoryExceptionDiagnostic,
            timestamp: Date,
            systemInfo: (Report) -> SystemInfo
        ) -> Report.ID? {
            guard let tempURL = writeSkeletonReport() else { return nil }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            guard let data = try? Data(contentsOf: tempURL),
                let skeleton = try? JSONDecoder().decode(Report.self, from: data)
            else {
                os_log(
                    .error, log: metricKitLog,
                    "[MONITORS] Failed to read or decode skeleton report at %{public}@", tempURL.path)
                return nil
            }

            let callStackData = buildCallStackData(from: diagnostic.callStackTree.callStackRepresentation)

            // `.memoryLimit` is what marks this as an OOM in the delivered report's
            // `terminationReason`: a MetricKit memory exception is exactly the
            // per-process (jetsam) memory-limit kill.
            let newError = CrashError(
                type: .termination,
                subtype: .memoryException,
                isFatal: true,
                isCleanExit: false,
                terminationReason: .memoryLimit
            )

            let newCrash = Report.Crash(
                diagnosis: nil,
                error: newError,
                threads: callStackData.threads,
                crashedThread: nil  // duplicate data; the crashed thread is flagged inline
            )

            let crashedRunId = runIdHandler.decode(from: callStackData) { name, ext in
                self.sidecarPathProvider(name: name, extension: ext)
            }

            // A memory exception is the dead run's last moment, so its run sidecars (memory
            // state, breadcrumbs, lifecycle) are aligned data: not finalized, so the store
            // stitches them in on read (see makeMetricKitReportInfo).
            let reportInfo = makeMetricKitReportInfo(
                skeleton: skeleton, timestamp: timestamp, runId: crashedRunId, finalized: false)
            let system = systemInfo(skeleton)
            let newReport = Report(
                binaryImages: callStackData.binaryImages,
                crash: newCrash,
                debug: nil,
                process: nil,
                report: reportInfo,
                system: system
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let newData = try? encoder.encode(newReport) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode MetricKit memory report")
                return nil
            }

            guard let reportID = addMetricKitReport(newData) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to store MetricKit report")
                return nil
            }
            os_log(
                .default, log: metricKitLog,
                "[MONITORS] Added MetricKit memory report (id=%{public}@, %d bytes, %d threads, app %{public}@, runId=%{public}@)",
                reportID.description, newData.count, callStackData.threads.count,
                system.cfBundleShortVersionString ?? "unknown", crashedRunId ?? "none")
            return reportID
        }
    }

#endif
