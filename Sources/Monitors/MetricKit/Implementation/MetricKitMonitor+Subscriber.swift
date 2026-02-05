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
import os.log

#if KSCRASH_HAS_METRICKIT
    import MetricKit
#endif

#if SWIFT_PACKAGE
    import KSCrashRecording
    import KSCrashRecordingCore
    import Report
#endif

// Disambiguate from Foundation.MachError.
// Under SPM, MachError lives in the Report module (ambiguous with Foundation).
// Under CocoaPods, it's in the current module (KSCrash) which takes priority.
#if SWIFT_PACKAGE
    private typealias _MachError = Report.MachError
#else
    private typealias _MachError = MachError
#endif

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
            guard let callbacks = callbacks else {
                os_log(.error, log: metricKitLog, "[MONITORS] No callbacks available, skipping diagnostic")
                return nil
            }

            // Phase 1: Write skeleton report to a temp file via C callbacks.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("kscrash-metrickit-\(UUID().uuidString).json")
            let tempPath = tempURL.path

            let requirements = KSCrash_ExceptionHandlingRequirements(
                shouldRecordAllThreads: 0,
                shouldWriteReport: 1,
                isFatal: 0,
                asyncSafety: 0,
                asyncSafetyBecauseThreadsSuspended: 0,
                crashedDuringExceptionHandling: 0,
                shouldExitImmediately: 0
            )

            let context = callbacks.notify(thread_t(ksthread_self()), requirements)
            kscm_fillMonitorContext(context, api)
            // this ensures we don't flag this report as "last crash"
            context?.pointee.currentSnapshotUserReported = true
            context?.pointee.omitBinaryImages = true
            tempPath.withCString { cPath in
                context?.pointee.reportPath = cPath
                callbacks.handle(context)
            }

            defer { try? FileManager.default.removeItem(at: tempURL) }

            // Phase 2: Post-process and write final report
            return postProcessReport(atPath: tempPath, diagnostic: diagnostic, timestamp: timestamp)
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
                reason: reason
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
            let meta = diagnostic.metaData
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
            let newSystem = SystemInfo(
                cfBundleIdentifier: bundleIdentifier,
                cfBundleShortVersionString: diagnostic.applicationVersion,
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
                monitorId: report.report.monitorId
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

    }

#endif
