//
//  MetricKitReceiver.swift
//
//  Created by Alexander Cohen on 2026-01-31.
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
import Report
import os.log

#if SWIFT_PACKAGE
    import KSCrashRecording
    import KSCrashRecordingCore
#endif

#if os(iOS) || os(macOS)
    import MetricKit
#endif

let metricKitLog = OSLog(subsystem: "com.kscrash", category: "MetricKit")

// MARK: - MetricKitReceiver

#if os(iOS) || os(macOS)

    @available(iOS 14.0, macOS 12.0, *)
    final class MetricKitReceiver: NSObject, MXMetricManagerSubscriber {

        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            os_log(.default, log: metricKitLog, "[MONITORS] Received %d diagnostic payload(s)", payloads.count)

            for payload in payloads {
                if let crashDiagnostics = payload.crashDiagnostics {
                    for diagnostic in crashDiagnostics {
                        processCrashDiagnostic(diagnostic)
                    }
                }
            }
        }

        // MARK: - Processing

        private func processCrashDiagnostic(_ diagnostic: MXCrashDiagnostic) {
            guard let callbacks = MetricKitMonitor.callbacks else {
                os_log(.error, log: metricKitLog, "[MONITORS] No callbacks available, skipping diagnostic")
                return
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

            let api = MetricKitMonitor.api
            let context = callbacks.notify(mach_thread_self(), requirements)
            kscm_fillMonitorContext(context, api)
            context?.pointee.omitBinaryImages = true
            tempPath.withCString { cPath in
                context?.pointee.reportPath = cPath
                callbacks.handle(context)
            }

            defer { try? FileManager.default.removeItem(at: tempURL) }

            // Phase 2: Post-process and write final report
            postProcessReport(atPath: tempPath, diagnostic: diagnostic)
        }

        // MARK: - Post-Processing

        private func postProcessReport(atPath path: String, diagnostic: MXCrashDiagnostic) {
            let url = URL(fileURLWithPath: path)

            guard let data = try? Data(contentsOf: url),
                let report = try? JSONDecoder().decode(BasicCrashReport.self, from: data)
            else {
                os_log(
                    .error, log: metricKitLog, "[MONITORS] Failed to read or decode skeleton report at %{public}@", path
                )
                return
            }

            // Extract MetricKit call stack and binary image data
            let callStackData = diagnostic.callStackTree.extractCallStackData()

            // Build error info from the diagnostic
            let machError: Report.MachError?
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
                    machError = Report.MachError(
                        code: diagnostic.exceptionCode.map { UInt64(truncating: $0) } ?? 0,
                        exception: UInt64(truncating: exceptionType)
                    )
                } else {
                    machError = nil
                }
                signalError = diagnostic.signal.map { SignalError(code: 0, signal: UInt64(truncating: $0)) }
            } else if let exceptionType = diagnostic.exceptionType {
                errorType = .mach
                machError = Report.MachError(
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
                mach: machError,
                nsexception: nsexception,
                signal: signalError,
                type: errorType,
                exitReason: exitReason,
                reason: reason
            )

            // Build crash section with MetricKit threads
            let crashedThread: BasicCrashReport.Thread?
            if callStackData.crashedThreadIndex < callStackData.threads.count {
                crashedThread = callStackData.threads[callStackData.crashedThreadIndex]
            } else {
                crashedThread = nil
            }

            let newCrash = BasicCrashReport.Crash(
                diagnosis: nil,
                error: newError,
                threads: callStackData.threads,
                crashedThread: crashedThread
            )

            // Build system info from MetricKit metadata.
            // The skeleton report's system info reflects the current session,
            // not the session that crashed, so we discard it entirely.
            let meta = diagnostic.metaData
            var processID: Int?
            var buildType: BuildType = .appStore
            var bundleIdentifier: String? = report.system?.cfBundleIdentifier
            if #available(iOS 17.0, macOS 14.0, *) {
                let pid = meta.pid
                processID = pid >= 0 ? Int(pid) : nil
                if meta.isTestFlightApp {
                    buildType = .test
                }
            }
            if #available(iOS 26.0, macOS 26.0, *) {
                let metaBundleId = meta.bundleIdentifier
                if !metaBundleId.isEmpty {
                    bundleIdentifier = metaBundleId
                }
            }
            let osInfo = parseOSVersion(meta.osVersion)
            let newSystem = SystemInfo(
                cfBundleIdentifier: bundleIdentifier,
                cfBundleShortVersionString: diagnostic.applicationVersion,
                cfBundleVersion: meta.applicationBuildVersion,
                cpuArch: meta.platformArchitecture,
                machine: meta.deviceType,
                osVersion: osInfo.build,
                processID: processID,
                systemName: osInfo.name,
                systemVersion: osInfo.version,
                buildType: buildType
            )

            // Construct the final report
            let newReport = BasicCrashReport(
                binaryImages: callStackData.binaryImages,
                crash: newCrash,
                debug: nil,
                process: nil,
                report: report.report,
                system: newSystem
            )

            // Encode and add to the reports directory
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let newData = try? encoder.encode(newReport) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode MetricKit crash report")
                return
            }

            newData.withUnsafeBytes { buffer in
                guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
                let reportID = kscrash_addUserReport(ptr, Int32(buffer.count))
                os_log(
                    .default, log: metricKitLog,
                    "[MONITORS] Added MetricKit report (id=%lld, %d bytes, %{public}@ error, app %{public}@)",
                    reportID, buffer.count, errorType.rawValue, diagnostic.applicationVersion)
            }
        }

    }

    // MARK: - OS Version Parsing

    struct OSVersionInfo {
        let name: String?
        let version: String?
        let build: String?
    }

    /// Parses a MetricKit OS version string into its components.
    /// Format: "<Name> <Version> (<Build>)" e.g. "iPhone OS 26.2.1 (23C71)"
    /// Falls back to using the raw string as systemVersion if parsing fails.
    func parseOSVersion(_ raw: String) -> OSVersionInfo {
        let pattern = #"^(.+?)\s+([\d.]+)\s+\((.+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
            match.numberOfRanges == 4,
            let nameRange = Range(match.range(at: 1), in: raw),
            let versionRange = Range(match.range(at: 2), in: raw),
            let buildRange = Range(match.range(at: 3), in: raw)
        else {
            return OSVersionInfo(name: nil, version: raw, build: nil)
        }
        return OSVersionInfo(
            name: String(raw[nameRange]),
            version: String(raw[versionRange]),
            build: String(raw[buildRange])
        )
    }

    // MARK: - Termination Reason Parsing

    /// Parses the exit code from a termination reason string.
    /// Format: "Namespace <NAME>, Code <VALUE> [optional description]"
    /// The code value may be decimal or hex (0x prefix).
    func parseExitCode(from terminationReason: String) -> UInt64? {
        guard let codeRange = terminationReason.range(of: "Code ") else {
            return nil
        }
        let afterCode = terminationReason[codeRange.upperBound...]
        let codeString = String(afterCode.prefix(while: { !$0.isWhitespace }))
        if codeString.hasPrefix("0x") || codeString.hasPrefix("0X") {
            return UInt64(codeString.dropFirst(2), radix: 16)
        }
        return UInt64(codeString)
    }

#else

    // Non-iOS/macOS stub
    final class MetricKitReceiver: NSObject {
    }

#endif
