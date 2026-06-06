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
import KSCrashRecording
import KSCrashRecordingCore
import KSCrashReportModel
import os.log

#if KSCRASH_HAS_METRICKIT
    import MetricKit
#endif

// Disambiguate from Foundation.MachError: the one we want lives in the KSCrashReportModel
// module and is ambiguous with Foundation's MachError, so qualify it.
private typealias _MachError = KSCrashReportModel.MachError

// MARK: - MXMetricManagerSubscriber

#if KSCRASH_HAS_METRICKIT

    @available(iOS 14.0, macOS 12.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    extension MetricKitMonitor: MXMetricManagerSubscriber {

        public func didReceive(_ payloads: [MXDiagnosticPayload]) {
            updateDiagnosticsState(.processing)

            os_log(.default, log: metricKitLog, "[MONITORS] Received %d diagnostic payload(s)", payloads.count)

            var reportIDs: [Int64] = []
            for payload in payloads {
                let timestamp = payload.timeStampEnd
                if let diagnostics = payload.crashDiagnostics {
                    for diagnostic in diagnostics {
                        if let reportID = processCrashDiagnostic(diagnostic, timestamp: timestamp) {
                            reportIDs.append(reportID)
                        }
                    }
                }
                if let diagnostics = payload.hangDiagnostics {
                    for diagnostic in diagnostics {
                        if let reportID = processHangDiagnostic(diagnostic, timestamp: timestamp) {
                            reportIDs.append(reportID)
                        }
                    }
                }
                if dumpPayloadsToDocuments {
                    payload.dump()
                }
            }

            updateDiagnosticsState(.completed, reportIDs: reportIDs)
        }

        // MXMetricPayload was API_UNAVAILABLE(macos) until the macOS 26 SDK (Xcode 26 / Swift 6.2).
        // On iOS it has been available since iOS 13.
        #if !os(macOS) || compiler(>=6.2)
            public func didReceive(_ payloads: [MXMetricPayload]) {
                updateMetricsState(.processing)
                defer { updateMetricsState(.completed) }

                os_log(.default, log: metricKitLog, "[MONITORS] Received %d metric payload(s)", payloads.count)

                for payload in payloads {
                    if dumpPayloadsToDocuments {
                        payload.dump()
                    }
                }
            }
        #endif

        // MARK: - Processing

        @discardableResult
        private func processCrashDiagnostic(_ diagnostic: MXCrashDiagnostic, timestamp: Date) -> Int64? {
            // Phase 1: Write skeleton report to a temp file via C callbacks.
            guard let tempURL = writeSkeletonReport() else { return nil }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            // Phase 2: Post-process and write final report
            return postProcessReport(atPath: tempURL.path, diagnostic: diagnostic, timestamp: timestamp)
        }

        @discardableResult
        private func processHangDiagnostic(_ diagnostic: MXHangDiagnostic, timestamp: Date) -> Int64? {
            guard let tempURL = writeSkeletonReport() else { return nil }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            return postProcessHangReport(atPath: tempURL.path, diagnostic: diagnostic, timestamp: timestamp)
        }

        /// Writes a skeleton report to a temp file via the C callbacks and returns its URL.
        /// The caller is responsible for removing the file once it has been post-processed.
        private func writeSkeletonReport() -> URL? {
            guard let callbacks = callbacks else {
                os_log(.error, log: metricKitLog, "[MONITORS] No callbacks available, skipping diagnostic")
                return nil
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("kscrash-metrickit-\(UUID().uuidString).json")

            // Use isFatal=0 for the skeleton so that Lifecycle's addContextualInfoToEvent
            // doesn't mark the current run as unclean — MetricKit diagnostics describe a
            // previous run. We set isFatal/isCleanExit on the final report in post-processing.
            let requirements = KSCrash_ExceptionHandlingRequirements(
                shouldRecordAllThreads: 0,
                shouldWriteReport: 1,
                isFatal: 0,
                isCleanExit: 0,
                asyncSafety: 0,
                asyncSafetyBecauseThreadsSuspended: 0,
                crashedDuringExceptionHandling: 0,
                shouldExitImmediately: 0
            )

            let context = callbacks.notify(thread_t(ksthread_self()), requirements)
            kscm_fillMonitorContext(context, api)
            context?.pointee.omitBinaryImages = true
            tempURL.path.withCString { cPath in
                context?.pointee.reportPath = cPath
                callbacks.handle(context)
            }

            return tempURL
        }

        // MARK: - Post-Processing

        private func postProcessReport(atPath path: String, diagnostic: MXCrashDiagnostic, timestamp: Date) -> Int64? {
            let url = URL(fileURLWithPath: path)

            guard let data = try? Data(contentsOf: url),
                let report = try? JSONDecoder().decode(BasicCrashReport.self, from: data)
            else {
                os_log(
                    .error, log: metricKitLog, "[MONITORS] Failed to read or decode skeleton report at %{public}@",
                    path
                )
                return nil
            }

            // Extract MetricKit call stack and binary image data
            let callStackData = diagnostic.callStackTree.extractCallStackData()

            // Build error info from the diagnostic
            let machError: _MachError?
            let signalError: SignalError?
            let nsexception: ExceptionInfo?
            let errorType: CrashErrorType
            let reason: String?

            if #available(iOS 17.0, macOS 14.0, *), let exceptionReason = diagnostic.exceptionReason {
                errorType = .nsexception
                nsexception = ExceptionInfo(
                    name: exceptionReason.exceptionName,
                    reason: exceptionReason.composedMessage
                )
                reason = exceptionReason.composedMessage
                if let exceptionType = diagnostic.exceptionType {
                    machError = _MachError(
                        code: diagnostic.exceptionCode.map { UInt64(truncating: $0) } ?? 0,
                        exception: UInt64(truncating: exceptionType)
                    )
                } else {
                    machError = nil
                }
                signalError = diagnostic.signal.map { SignalError(code: 0, signal: UInt64(truncating: $0)) }
            } else if let exceptionType = diagnostic.exceptionType {
                errorType = .mach
                machError = _MachError(
                    code: diagnostic.exceptionCode.map { UInt64(truncating: $0) } ?? 0,
                    exception: UInt64(truncating: exceptionType)
                )
                signalError = diagnostic.signal.map { SignalError(code: 0, signal: UInt64(truncating: $0)) }
                nsexception = nil
                reason = diagnostic.terminationReason
            } else if let sig = diagnostic.signal {
                errorType = .signal
                machError = nil
                signalError = SignalError(code: 0, signal: UInt64(truncating: sig))
                nsexception = nil
                reason = diagnostic.terminationReason
            } else {
                errorType = report.crash.error.type
                machError = nil
                signalError = nil
                nsexception = nil
                reason = diagnostic.terminationReason
            }

            // Parse faulting address from VM region info (bad-access crashes)
            let faultAddress: UInt64? = diagnostic.virtualMemoryRegionInfo.flatMap {
                parseVMRegionAddress(from: $0)
            }

            // Parse exit code from termination reason
            let exitReason: ExitReasonInfo?
            if let terminationReason = diagnostic.terminationReason,
                let exitCode = parseExitCode(from: terminationReason)
            {
                exitReason = ExitReasonInfo(code: exitCode)
            } else {
                exitReason = nil
            }

            let newError = CrashError(
                address: faultAddress,
                mach: machError,
                nsexception: nsexception,
                signal: signalError,
                type: errorType,
                exitReason: exitReason,
                reason: reason,
                isFatal: true,
                isCleanExit: false
            )

            let newCrash = BasicCrashReport.Crash(
                diagnosis: nil,
                error: newError,
                threads: callStackData.threads,
                crashedThread: nil  // this is just duplicate data
            )

            // Build system info from MetricKit metadata.
            // The skeleton report's system info reflects the current session,
            // not the session that crashed, so we discard it entirely.
            let newSystem = buildSystemInfo(
                metaData: diagnostic.metaData,
                applicationVersion: diagnostic.applicationVersion,
                skeleton: report
            )

            // Construct the final report.
            // The timestamp is the payload's timeStampEnd, which may represent:
            // - When the crash occurred
            // - When the report was delivered via MetricKit
            // - The end of the collection window (often 24 hours)
            // Extract run ID from threadcrumb stack hash
            let crashedRunId = runIdHandler.decode(from: callStackData) { name, ext in
                self.sidecarPathProvider(name: name, extension: ext)
            }

            let reportInfo = ReportInfo(
                id: report.report.id,
                processName: report.report.processName,
                timestamp: timestamp,
                type: report.report.type,
                version: report.report.version,
                runId: crashedRunId,
                monitorId: report.report.monitorId,
                finalized: true
            )
            let newReport = BasicCrashReport(
                binaryImages: callStackData.binaryImages,
                crash: newCrash,
                debug: nil,
                process: nil,
                report: reportInfo,
                system: newSystem
            )

            // Encode and add to the reports directory
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let newData = try? encoder.encode(newReport) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode MetricKit crash report")
                return nil
            }

            var reportID: Int64 = 0
            newData.withUnsafeBytes { buffer in
                guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
                reportID = kscrash_addUserReport(ptr, Int32(buffer.count))
                os_log(
                    .default, log: metricKitLog,
                    "[MONITORS] Added MetricKit report (id=%lld, %d bytes, %{public}@ error, app %{public}@, runId=%{public}@)",
                    reportID, buffer.count, errorType.rawValue, diagnostic.applicationVersion,
                    crashedRunId ?? "none")
            }
            return reportID
        }

        // MARK: - Hang Post-Processing

        // A hang diagnostic is a sampling profile of the hang window. We keep the report in
        // the profile lane (error.type == .profile) and tag it with the generic
        // error.subtype == .hang, rather than inventing a fatal error type. The report is
        // non-fatal and describes a previous window, so it must not touch current-run state.
        private func postProcessHangReport(atPath path: String, diagnostic: MXHangDiagnostic, timestamp: Date)
            -> Int64?
        {
            let url = URL(fileURLWithPath: path)

            guard let data = try? Data(contentsOf: url),
                let report = try? JSONDecoder().decode(BasicCrashReport.self, from: data)
            else {
                os_log(
                    .error, log: metricKitLog, "[MONITORS] Failed to read or decode skeleton report at %{public}@",
                    path
                )
                return nil
            }

            // The hang's call stack tree is a sample-merged trie across all threads. Convert
            // it to weighted per-thread samples for the profile body. The main thread (index 0)
            // is the subject of a Main Runloop Hang.
            let profileData = diagnostic.callStackTree.extractProfileData(primaryThreadIndex: 0)
            // The threadcrumb run ID lives in a flat per-thread backtrace, so decode it from
            // the crash-style extraction (cheap second pass over the same tree).
            let callStackData = diagnostic.callStackTree.extractCallStackData()

            let durationNs = UInt64((diagnostic.hangDuration.converted(to: .seconds).value * 1_000_000_000).rounded())

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

            let newCrash = BasicCrashReport.Crash(diagnosis: nil, error: newError)

            let newSystem = buildSystemInfo(
                metaData: diagnostic.metaData,
                applicationVersion: diagnostic.applicationVersion,
                skeleton: report
            )

            let crashedRunId = runIdHandler.decode(from: callStackData) { name, ext in
                self.sidecarPathProvider(name: name, extension: ext)
            }

            let reportInfo = ReportInfo(
                id: report.report.id,
                processName: report.report.processName,
                timestamp: timestamp,
                type: report.report.type,
                version: report.report.version,
                runId: crashedRunId,
                monitorId: report.report.monitorId,
                finalized: true
            )
            let newReport = BasicCrashReport(
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

            var reportID: Int64 = 0
            newData.withUnsafeBytes { buffer in
                guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
                reportID = kscrash_addUserReport(ptr, Int32(buffer.count))
                os_log(
                    .default, log: metricKitLog,
                    "[MONITORS] Added MetricKit hang report (id=%lld, %d bytes, %d threads, app %{public}@, runId=%{public}@)",
                    reportID, buffer.count, profileData.threads.count, diagnostic.applicationVersion,
                    crashedRunId ?? "none")
            }
            return reportID
        }

        // MARK: - Shared Builders

        /// Builds system info from MetricKit metadata. The skeleton report's system info
        /// reflects the current session, not the session the diagnostic describes, so it is
        /// discarded except for the process name and bundle identifier fallbacks.
        private func buildSystemInfo(
            metaData meta: MXMetaData, applicationVersion: String, skeleton report: BasicCrashReport
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
            // MXMetaData.bundleIdentifier was added in the macOS 26 / iOS 26 SDK (Xcode 26 / Swift 6.2).
            #if compiler(>=6.2)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                    let metaBundleId = meta.bundleIdentifier
                    if !metaBundleId.isEmpty {
                        bundleIdentifier = metaBundleId
                    }
                }
            #endif
            let osInfo = parseOSVersion(meta.osVersion)
            return SystemInfo(
                cfBundleIdentifier: bundleIdentifier,
                cfBundleShortVersionString: applicationVersion,
                cfBundleVersion: meta.applicationBuildVersion,
                cpuArch: meta.platformArchitecture,
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

        /// Wall-clock start estimate for a hang window: the payload end timestamp minus the
        /// hang duration. Returns nil if the subtraction would underflow.
        private func epochNanos(for timestamp: Date, minus durationNs: UInt64) -> UInt64? {
            let endNs = timestamp.timeIntervalSince1970 * 1_000_000_000
            guard endNs.isFinite, endNs >= 0 else { return nil }
            let end = UInt64(endNs.rounded())
            return end >= durationNs ? end - durationNs : nil
        }

    }

#endif
