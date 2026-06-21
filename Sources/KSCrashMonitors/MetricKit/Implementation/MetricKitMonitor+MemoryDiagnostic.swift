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

#if KSCRASH_HAS_METRICKIT
    import MetricKit
#endif

// MARK: - Memory Exception Diagnostics (iOS 27+)
//
// Handling for the iOS 27 `MemoryExceptionDiagnostic` — the OOM-style termination that finally
// carries a call stack. Delivery lives in MetricKitMonitor+Subscriber (the `MetricManager`
// async stream); this file turns each delivered diagnostic into a report and optionally dumps
// it. A memory exception is modelled like the heuristic OOMs: a fatal `.termination` with
// `terminationReason == .memoryLimit` and `subtype == .memoryException`.
//
// All parsing goes through the typed iOS 27 API (`CallStackTree`, `CallStackFrame`,
// `DiagnosticReport.Environment`, `OSVersion`); the JSON dump is only a debugging aid.
//
// The `.memoryException` enum case is iOS-only (unavailable on macOS, Mac Catalyst and
// visionOS), and the whole API requires the iOS 27 SDK, so this file compiles only with
// Xcode 27+ (Swift 6.4) when targeting iOS device or simulator. Under Xcode 26 the package
// builds exactly as before with no memory support.

#if KSCRASH_HAS_METRICKIT && compiler(>=6.4) && os(iOS) && !targetEnvironment(macCatalyst)

    @available(iOS 27.0, *)
    extension MetricKitMonitor {

        // MARK: - Handling

        // Called from the diagnostic reports stream (see MetricKitMonitor+Subscriber) for each
        // delivered memory exception.
        func handleMemoryException(
            _ diagnostic: MemoryExceptionDiagnostic, in report: DiagnosticReport
        ) {
            os_log(
                .default, log: metricKitLog,
                "[MONITORS] Received memory exception diagnostic (app %{public}@, %d thread(s))",
                report.environment.applicationVersion,
                diagnostic.callStackTree.callStackThreads.count)

            // Optional raw dump for debugging/exploration. The whole report carries the
            // environment metadata and time range, so dump it alongside the diagnostic.
            if dumpPayloadsToDocuments {
                MetricKitJSONDumper.dump(encodable: report, type: "MemoryException/Report")
                MetricKitJSONDumper.dump(encodable: diagnostic, type: "MemoryException/Diagnostic")
            }

            if let reportID = processMemoryDiagnostic(diagnostic, report: report) {
                recordDiagnosticReport(reportID)
            }
        }

        // MARK: - Processing

        // A memory exception is an OOM-style termination: the OS killed the process for
        // exceeding its memory limit. We model it like other terminations (`.termination`,
        // fatal) but tag it `subtype == .memoryException` and attach the call stack the new
        // diagnostic finally provides.
        @discardableResult
        private func processMemoryDiagnostic(
            _ diagnostic: MemoryExceptionDiagnostic, report: DiagnosticReport
        ) -> Int64? {
            guard let tempURL = writeSkeletonReport() else { return nil }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            guard let data = try? Data(contentsOf: tempURL),
                let skeleton = try? JSONDecoder().decode(BasicCrashReport.self, from: data)
            else {
                os_log(
                    .error, log: metricKitLog,
                    "[MONITORS] Failed to read or decode skeleton report at %{public}@", tempURL.path)
                return nil
            }

            // Parse the call stack via the typed iOS 27 API and reuse the shared crash
            // extraction (linear backtrace per thread, plus binary images).
            let callStackData = buildCallStackData(from: diagnostic.callStackTree.callStackRepresentation)

            // `.memoryLimit` is what marks this as an OOM: KSCrashDoctor keys off the
            // termination reason to diagnose "the app exceeded its memory limit and was
            // terminated by the OS." A MetricKit memory exception is exactly that per-process
            // (jetsam) memory-limit kill.
            let newError = CrashError(
                type: .termination,
                subtype: .memoryException,
                isFatal: true,
                isCleanExit: false,
                terminationReason: .memoryLimit
            )

            let newCrash = BasicCrashReport.Crash(
                diagnosis: nil,
                error: newError,
                threads: callStackData.threads,
                crashedThread: nil  // duplicate data; the crashed thread is flagged inline
            )

            let newSystem = buildSystemInfo(from: report.environment, skeleton: skeleton)

            let crashedRunId = runIdHandler.decode(from: callStackData) { name, ext in
                self.sidecarPathProvider(name: name, extension: ext)
            }

            // The diagnostic only spans an instant for a memory kill (begin == end), so the
            // end of the time range is the effective timestamp.
            let timestamp = report.timeRange.end

            // A memory exception is the dead run's last moment, so its run sidecars (memory
            // state, breadcrumbs, lifecycle) are aligned data: not finalized, so the store
            // stitches them in on read (see makeMetricKitReportInfo).
            let reportInfo = makeMetricKitReportInfo(
                skeleton: skeleton, timestamp: timestamp, runId: crashedRunId, finalized: false)
            let newReport = BasicCrashReport(
                binaryImages: callStackData.binaryImages,
                crash: newCrash,
                debug: nil,
                process: nil,
                report: reportInfo,
                system: newSystem
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let newData = try? encoder.encode(newReport) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode MetricKit memory report")
                return nil
            }

            var reportID: Int64 = 0
            newData.withUnsafeBytes { buffer in
                guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
                reportID = kscrash_addUserReport(ptr, Int32(buffer.count))
                os_log(
                    .default, log: metricKitLog,
                    "[MONITORS] Added MetricKit memory report (id=%lld, %d bytes, %d threads, app %{public}@, runId=%{public}@)",
                    reportID, buffer.count, callStackData.threads.count, report.environment.applicationVersion,
                    crashedRunId ?? "none")
            }
            return reportID
        }

        // MARK: - System Info

        /// Builds system info from the typed `DiagnosticReport.Environment`. The skeleton
        /// report's system info reflects the current session, not the session that was
        /// terminated, so it is discarded except for the process name fallback.
        private func buildSystemInfo(
            from environment: DiagnosticReport.Environment, skeleton report: BasicCrashReport
        ) -> SystemInfo {
            let os = environment.osVersion
            let pid = environment.pid
            return SystemInfo(
                cfBundleIdentifier: environment.bundleIdentifier,
                cfBundleShortVersionString: environment.applicationVersion,
                cfBundleVersion: environment.applicationBuildVersion,
                cpuArch: environment.platformArchitecture,
                machine: environment.deviceType,
                osVersion: os.buildNumber,
                processID: pid.map { Int($0) },
                processName: report.system?.processName,
                systemName: os.platform,
                systemVersion: os.number,
                buildType: environment.isTestFlightApp ? .test : .appStore,
                lowPowerModeEnabled: environment.lowPowerModeEnabled
            )
        }
    }

    // MARK: - Typed CallStackTree Adapter

    // Adapts the typed iOS 27 `CallStackTree` into the shared `CallStackTreeRepresentation`
    // used by the crash/profile extraction, so all the tree-walking logic (and its tests) is
    // reused unchanged. Unlike the legacy `MXCallStackTree`, the new tree carries binary names
    // in a separate `binaryInfo` table rather than per-frame, so `binaryName(from:)` resolves
    // them as each frame is converted.
    @available(iOS 27.0, *)
    extension CallStackTree {
        var callStackRepresentation: CallStackTreeRepresentation {
            func convert(_ frame: CallStackFrame) -> CallStackTreeRepresentation.Frame {
                // `address` is optional in the new API. When it is absent there is no base to
                // subtract the offset from, so drop the offset too — otherwise the shared
                // extraction would compute `0 - offset` and trap on UInt64 underflow.
                let address = frame.address
                return CallStackTreeRepresentation.Frame(
                    address: address ?? 0,
                    binaryUUID: frame.binaryUUID?.uuidString,
                    binaryName: frame.binaryName(from: self),
                    offsetIntoBinaryTextSegment: address == nil ? nil : frame.offsetIntoBinaryTextSegment,
                    sampleCount: frame.sampleCount,
                    subFrames: frame.subFrames.isEmpty ? nil : frame.subFrames.map(convert)
                )
            }
            let stacks = callStackThreads.map { thread in
                CallStackTreeRepresentation.CallStack(
                    threadAttributed: thread.threadAttributed,
                    callStackRootFrames: thread.rootFrames.map(convert)
                )
            }
            return CallStackTreeRepresentation(callStacks: stacks)
        }
    }

#endif
