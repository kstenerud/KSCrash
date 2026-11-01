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

#if KSCRASH_HAS_METRICKIT_LEGACY
    import MetricKit
#endif

// Disambiguate from Foundation.MachError: the one we want lives in the KSCrashReportModel
// module and is ambiguous with Foundation's MachError, so qualify it.
private typealias _MachError = KSCrashReportModel.MachError

// MARK: - Crash Diagnostic Fields

/// The parts of a crash diagnostic that shape the report, read off either MetricKit API (the
/// legacy `MXCrashDiagnostic` or the iOS 27 `CrashDiagnostic`), so one handler serves both.
struct CrashDiagnosticFields {
    var exceptionType: UInt64?
    var exceptionCode: UInt64?
    var signal: UInt64?
    var terminationReason: String?
    var virtualMemoryRegionInfo: String?
    var exceptionName: String?
    var exceptionMessage: String?
}

/// Builds the report's error from a crash diagnostic. An Objective-C exception reason makes it an
/// NSException; otherwise the Mach exception, then the signal, decides the type, and
/// `fallbackType` (the skeleton report's) is used when the diagnostic carries none of them.
func makeCrashError(from fields: CrashDiagnosticFields, fallbackType: CrashErrorType) -> CrashError {
    let machError = fields.exceptionType.map {
        _MachError(code: fields.exceptionCode ?? 0, exception: $0)
    }
    let signalError = fields.signal.map { SignalError(code: 0, signal: $0) }

    let errorType: CrashErrorType
    let nsexception: ExceptionInfo?
    let reason: String?
    if let exceptionName = fields.exceptionName, let exceptionMessage = fields.exceptionMessage {
        errorType = .nsexception
        nsexception = ExceptionInfo(name: exceptionName, reason: exceptionMessage)
        reason = exceptionMessage
    } else {
        errorType = machError != nil ? .mach : signalError != nil ? .signal : fallbackType
        nsexception = nil
        reason = fields.terminationReason
    }

    // A bad-access crash names the faulting address at the start of the VM region info.
    let faultAddress = fields.virtualMemoryRegionInfo.flatMap { parseVMRegionAddress(from: $0) }
    let exitReason = fields.terminationReason.flatMap { parseExitCode(from: $0) }.map { ExitReasonInfo(code: $0) }

    return CrashError(
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
}

// MARK: - Crash Diagnostic Handling

#if KSCRASH_HAS_METRICKIT_LEGACY

    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    extension MetricKitMonitor {

        /// Turns a crash diagnostic from either MetricKit API into a stored report.
        ///
        /// - Parameters:
        ///   - fields: The diagnostic's error fields.
        ///   - callStackTree: The diagnostic's call stack tree.
        ///   - timestamp: When the crash happened, as the delivering API reports it.
        ///   - applicationVersion: The crashed app's version, for logging.
        ///   - systemInfo: Builds the report's system info from the skeleton report.
        /// - Returns: The stored report's id, or nil when it could not be written.
        @discardableResult
        func processCrash(
            _ fields: CrashDiagnosticFields,
            callStackTree: CallStackTreeRepresentation,
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

            let callStackData = buildCallStackData(from: callStackTree)
            let newError = makeCrashError(from: fields, fallbackType: skeleton.crash.error.type)

            let newCrash = Report.Crash(
                diagnosis: nil,
                error: newError,
                threads: callStackData.threads,
                crashedThread: nil  // this is just duplicate data
            )

            let crashedRunId = runIdHandler.decode(from: callStackData) { name, ext in
                self.sidecarPathProvider(name: name, extension: ext)
            }

            // A crash is the dead run's last moment, so its run sidecars are aligned data:
            // not finalized, so the store stitches them in on read (see makeMetricKitReportInfo).
            let reportInfo = makeMetricKitReportInfo(
                skeleton: skeleton, timestamp: timestamp, runId: crashedRunId, finalized: false)
            let newReport = Report(
                binaryImages: callStackData.binaryImages,
                crash: newCrash,
                debug: nil,
                process: nil,
                report: reportInfo,
                system: systemInfo(skeleton)
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let newData = try? encoder.encode(newReport) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode MetricKit crash report")
                return nil
            }

            guard let reportID = addMetricKitReport(newData) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to store MetricKit report")
                return nil
            }
            os_log(
                .default, log: metricKitLog,
                "[MONITORS] Added MetricKit report (id=%{public}@, %d bytes, %{public}@ error, app %{public}@, runId=%{public}@)",
                reportID.description, newData.count, newError.type.rawValue, applicationVersion,
                crashedRunId ?? "none")
            return reportID
        }

        /// The legacy `MXCrashDiagnostic` path. `timestamp` is the payload's `timeStampEnd`.
        @discardableResult
        func processCrashDiagnostic(_ diagnostic: MXCrashDiagnostic, timestamp: Date) -> Report.ID? {
            var fields = CrashDiagnosticFields(
                exceptionType: diagnostic.exceptionType.map { UInt64(truncating: $0) },
                exceptionCode: diagnostic.exceptionCode.map { UInt64(truncating: $0) },
                signal: diagnostic.signal.map { UInt64(truncating: $0) },
                terminationReason: diagnostic.terminationReason,
                virtualMemoryRegionInfo: diagnostic.virtualMemoryRegionInfo
            )
            if #available(iOS 17.0, macOS 14.0, *), let exceptionReason = diagnostic.exceptionReason {
                fields.exceptionName = exceptionReason.exceptionName
                fields.exceptionMessage = exceptionReason.composedMessage
            }
            return processCrash(
                fields,
                callStackTree: diagnostic.callStackTree.representation ?? CallStackTreeRepresentation(callStacks: []),
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
