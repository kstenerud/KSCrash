//
//  MetricKitMonitor+Subscriber.swift
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
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashRecordingCore
import KSCrashReportModel
import os.log

#if KSCRASH_HAS_METRICKIT_LEGACY
    import MetricKit
#endif

// MARK: - Subscription
//
// The legacy `MXMetricManagerSubscriber`, used before 27 and in builds without the 27 SDKs (the
// 27 streams live in MetricKitMonitor+DiagnosticStream). Each kind's handling lives in its own
// MetricKitMonitor+<Kind>Diagnostic.swift; this file only delivers payloads and dispatches into
// those handlers, plus the report machinery shared across kinds.

#if KSCRASH_HAS_METRICKIT_LEGACY

    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    extension MetricKitMonitor: MXMetricManagerSubscriber {

        public func didReceive(_ payloads: [MXDiagnosticPayload]) {
            os_log(.default, log: metricKitLog, "[MONITORS] Received %d diagnostic payload(s)", payloads.count)

            for payload in payloads {
                let timestamp = payload.timeStampEnd
                let timeRange = MetricKitTimeRange(begin: payload.timeStampBegin, end: payload.timeStampEnd)
                if let diagnostics = payload.crashDiagnostics {
                    for diagnostic in diagnostics {
                        if let reportID = processCrashDiagnostic(diagnostic, timestamp: timestamp) {
                            recordDiagnosticReport(reportID)
                        }
                    }
                }
                if let diagnostics = payload.hangDiagnostics {
                    for diagnostic in diagnostics {
                        if let reportID = processHangDiagnostic(diagnostic, timestamp: timestamp) {
                            recordDiagnosticReport(reportID)
                        }
                    }
                }
                if let diagnostics = payload.cpuExceptionDiagnostics {
                    for diagnostic in diagnostics {
                        if let reportID = processCPUExceptionDiagnostic(diagnostic, timeRange: timeRange) {
                            recordDiagnosticReport(reportID)
                        }
                    }
                }
                if let diagnostics = payload.diskWriteExceptionDiagnostics {
                    for diagnostic in diagnostics {
                        if let reportID = processDiskWriteDiagnostic(diagnostic, timeRange: timeRange) {
                            recordDiagnosticReport(reportID)
                        }
                    }
                }
                if configuration.dumpsPayloadsToDocuments {
                    payload.dump()
                }
            }
        }

        public func didReceive(_ payloads: [MXMetricPayload]) {
            os_log(.default, log: metricKitLog, "[MONITORS] Received %d metric payload(s)", payloads.count)

            for payload in payloads {
                if configuration.dumpsPayloadsToDocuments {
                    payload.dump()
                }
            }
        }

        // MARK: - Shared Report Machinery

        /// Stores a profile report about a diagnostic that carries no run ID (disk writes, CPU).
        ///
        /// The report is non-fatal and describes a stretch of a run that kept going, so it is
        /// stored finalized and touches no current-run state.
        ///
        /// - Parameters:
        ///   - error: The report's error.
        ///   - kind: The diagnostic kind, for logging.
        ///   - timestamp: The report's timestamp.
        ///   - applicationVersion: The app's version, for logging.
        ///   - systemInfo: Builds the report's system info from the skeleton report.
        /// - Returns: The stored report's id, or nil when it could not be written.
        func storeRunlessProfileReport(
            _ error: CrashError,
            kind: String,
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
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode MetricKit %{public}@ report", kind)
                return nil
            }

            guard let reportID = addMetricKitReport(newData) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to store MetricKit report")
                return nil
            }
            os_log(
                .default, log: metricKitLog,
                "[MONITORS] Added MetricKit %{public}@ report (id=%{public}@, %d bytes, app %{public}@)",
                kind, reportID.description, newData.count, applicationVersion)
            return reportID
        }

        /// Writes a skeleton report to a temp file via the host and returns its URL.
        /// The caller is responsible for removing the file once it has been post-processed.
        /// Shared by every diagnostic handler (crash, hang, memory).
        func writeSkeletonReport() -> URL? {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("kscrash-metrickit-\(UUID().uuidString).json")

            // Use isFatal=0 for the skeleton so that Lifecycle's addContextualInfoToEvent
            // doesn't mark the current run as unclean — MetricKit diagnostics describe a
            // previous run. We set isFatal/isCleanExit on the final report in post-processing.
            // `.nonFatal` carries exactly those bits (shouldRecordAllThreads/isFatal/isCleanExit/
            // isRemoteSubject all 0, shouldWriteReport 1); `EventRequirements.init` is internal to
            // KSCrashMonitorPlugins, so a custom bitfield can't be built from outside that module.
            let skeletonRequirements = EventRequirements.nonFatal

            // notify()/handle() mutate shared exception-handling state in KSCrashMonitor.c that
            // is not safe to enter concurrently, and MetricKit promises nothing about which
            // thread, or how many at once, its deliveries arrive on. Serialize the whole sequence.
            return skeletonLock.withLock {
                // withCString's pointer is only valid inside its own closure, so the whole
                // host.handle call (which reads context.pointee.reportPath from inside
                // handleWithResult, after configure returns) must run inside it; setting
                // reportPath from within configure's own (narrower) closure would leave it
                // dangling by the time the write actually happens.
                let written = tempURL.path.withCString { cPath in
                    try? host.handle(
                        requirements: skeletonRequirements, subjectThread: thread_t(ksthread_self())
                    ) { context in
                        context.pointee.omitBinaryImages = true
                        context.pointee.reportPath = cPath
                    }
                }
                return written != nil ? tempURL : nil
            }
        }

        /// Builds system info from MetricKit metadata. The skeleton report's system info
        /// reflects the current session, not the session the diagnostic describes, so it is
        /// discarded except for the process name and bundle identifier fallbacks. The device hash,
        /// the one value every run of the app shares, comes from this run (see deviceAppHash).
        /// Used by the legacy crash, hang, CPU and disk write paths; the 27 streams build it from the
        /// typed environment.
        func buildSystemInfo(
            metaData meta: MXMetaData, applicationVersion: String, skeleton report: Report
        )
            -> SystemInfo
        {
            var processID: Int?
            var buildType: BuildType = .appStore
            var bundleIdentifier: String? = report.system?.cfBundleIdentifier
            var lowPowerMode: Bool?
            if #available(iOS 17.0, macOS 14.0, *) {
                let pid = meta.pid
                processID = pid >= 0 ? Int(pid) : nil
                if meta.isTestFlightApp {
                    buildType = .test
                }
                lowPowerMode = meta.lowPowerModeEnabled
            }
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                let metaBundleId = meta.bundleIdentifier
                if !metaBundleId.isEmpty {
                    bundleIdentifier = metaBundleId
                }
            }
            let osInfo = parseOSVersion(meta.osVersion)
            return SystemInfo(
                cfBundleIdentifier: bundleIdentifier,
                cfBundleShortVersionString: applicationVersion,
                cfBundleVersion: meta.applicationBuildVersion,
                cpuArch: meta.platformArchitecture,
                deviceAppHash: deviceAppHash(forDiagnosticBundleID: bundleIdentifier),
                machine: meta.deviceType,
                osVersion: osInfo.build,
                processID: processID,
                processName: report.system?.processName,
                systemName: osInfo.name,
                systemVersion: osInfo.version,
                buildType: buildType,
                lowPowerModeEnabled: lowPowerMode
            )
        }
    }

#endif
