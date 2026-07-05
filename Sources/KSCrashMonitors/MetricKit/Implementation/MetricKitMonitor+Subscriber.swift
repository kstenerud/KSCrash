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

// MARK: - Subscription
//
// Everything about *receiving* MetricKit data lives here, for both delivery mechanisms: the
// legacy `MXMetricManagerSubscriber` (crash, hang, metrics; all OS versions) and the iOS 27+
// `MetricManager.diagnosticReports` async stream (memory exceptions). Each kind's handling
// lives in its own MetricKitMonitor+<Kind>Diagnostic.swift; this file only delivers payloads
// and dispatches into those handlers, plus the report machinery shared across kinds.

#if KSCRASH_HAS_METRICKIT

    @available(iOS 14.0, macOS 12.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    extension MetricKitMonitor: MXMetricManagerSubscriber {

        public func didReceive(_ payloads: [MXDiagnosticPayload]) {
            os_log(.default, log: metricKitLog, "[MONITORS] Received %d diagnostic payload(s)", payloads.count)

            for payload in payloads {
                let timestamp = payload.timeStampEnd
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
                if dumpPayloadsToDocuments {
                    payload.dump()
                }
            }
        }

        // MXMetricPayload was API_UNAVAILABLE(macos) until the macOS 26 SDK (Xcode 26 / Swift 6.2).
        // On iOS it has been available since iOS 13.
        #if !os(macOS) || compiler(>=6.2)
            public func didReceive(_ payloads: [MXMetricPayload]) {
                os_log(.default, log: metricKitLog, "[MONITORS] Received %d metric payload(s)", payloads.count)

                for payload in payloads {
                    if dumpPayloadsToDocuments {
                        payload.dump()
                    }
                }
            }
        #endif

        // MARK: - Shared Report Machinery

        /// Writes a skeleton report to a temp file via the C callbacks and returns its URL.
        /// The caller is responsible for removing the file once it has been post-processed.
        /// Shared by every diagnostic handler (crash, hang, memory).
        func writeSkeletonReport() -> URL? {
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
                shouldExitImmediately: 0,
                isRemoteSubject: 0
            )

            // notify()/handle() mutate shared exception-handling state in KSCrashMonitor.c that
            // is not safe to enter concurrently. The legacy subscriber and the iOS 27 memory
            // stream deliver on different threads, so serialize the whole sequence.
            return skeletonLock.withLock {
                let context = callbacks.notify(thread_t(ksthread_self()), requirements)
                kscm_fillMonitorContext(context, api)
                context?.pointee.omitBinaryImages = true
                tempURL.path.withCString { cPath in
                    context?.pointee.reportPath = cPath
                    callbacks.handle(context)
                }
                return tempURL
            }
        }

        /// Builds system info from MetricKit metadata. The skeleton report's system info
        /// reflects the current session, not the session the diagnostic describes, so it is
        /// discarded except for the process name and bundle identifier fallbacks. Shared by the
        /// crash and hang handlers (the memory handler builds its own from the typed environment).
        func buildSystemInfo(
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
    }

    // MARK: - Memory Exception Subscription (iOS 27+)
    //
    // iOS 27 vends memory exception diagnostics only through the new `MetricManager` async API,
    // which is also where the legacy `MXDiagnosticPayload` path is headed. We consume it
    // additively: the subscriber above keeps handling crash/hang on every OS version, and this
    // stream adds memory exceptions on iOS 27+. There is no overlap, since the old payload never
    // vends memory exceptions and this stream ignores every other `DiagnosticResult` case.
    //
    // The `.memoryException` case is iOS-only (unavailable on macOS, Mac Catalyst, visionOS) and
    // the API needs the iOS 27 SDK, so this compiles only with Xcode 27+ (Swift 6.4) targeting
    // iOS device/simulator. Under Xcode 26 the package builds exactly as before.

    #if compiler(>=6.4) && os(iOS) && !targetEnvironment(macCatalyst)

        @available(iOS 27.0, *)
        extension MetricKitMonitor {

            /// Starts consuming `MetricManager.diagnosticReports` so memory exceptions are turned
            /// into reports (see MetricKitMonitor+MemoryDiagnostic). Safe to call repeatedly: an
            /// existing observer task is left running.
            func startMemoryDiagnosticReporting() {
                // Check-and-set under a single lock acquisition so concurrent callers can't both
                // start a stream. The manager is captured by the task so it stays alive for the
                // stream's lifetime; `self` is captured weakly so the long-lived task never keeps
                // the monitor alive.
                lock.withLock { state in
                    guard state.memoryDiagnosticsTask == nil else { return }
                    let manager = MetricManager()
                    state.memoryDiagnosticsTask = Task { [weak self] in
                        os_log(
                            .default, log: metricKitLog,
                            "[MONITORS] Observing MetricManager.diagnosticReports for memory exceptions")
                        for await report in manager.diagnosticReports {
                            if Task.isCancelled { break }
                            guard case .memoryException(let diagnostic) = report.result else { continue }
                            self?.handleMemoryException(diagnostic, in: report)
                        }
                    }
                }
            }

            /// Cancels the diagnostic reports observer, if running.
            func stopMemoryDiagnosticReporting() {
                lock.withLock { state in
                    state.memoryDiagnosticsTask?.cancel()
                    state.memoryDiagnosticsTask = nil
                }
            }
        }

    #endif

#endif
