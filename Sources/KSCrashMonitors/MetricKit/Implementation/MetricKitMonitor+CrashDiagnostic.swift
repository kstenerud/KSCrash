//
//  MetricKitMonitor+CrashDiagnostic.swift
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

// Disambiguate from Foundation.MachError: the one we want lives in the KSCrashReportModel
// module and is ambiguous with Foundation's MachError, so qualify it.
private typealias _MachError = KSCrashReportModel.MachError

// MARK: - Crash Diagnostic Handling

#if KSCRASH_HAS_METRICKIT

    @available(iOS 14.0, macOS 12.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    extension MetricKitMonitor {

        @discardableResult
        func processCrashDiagnostic(_ diagnostic: MXCrashDiagnostic, timestamp: Date) -> Int64? {
            // Phase 1: Write skeleton report to a temp file via C callbacks.
            guard let tempURL = writeSkeletonReport() else { return nil }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            // Phase 2: Post-process and write final report
            return postProcessReport(atPath: tempURL.path, diagnostic: diagnostic, timestamp: timestamp)
        }

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

            // A crash is the dead run's last moment, so its run sidecars are aligned data:
            // not finalized, so the store stitches them in on read (see makeMetricKitReportInfo).
            let reportInfo = makeMetricKitReportInfo(
                skeleton: report, timestamp: timestamp, runId: crashedRunId, finalized: false)
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
