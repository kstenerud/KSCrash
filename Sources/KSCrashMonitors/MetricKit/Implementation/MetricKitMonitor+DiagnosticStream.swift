//
//  MetricKitMonitor+DiagnosticStream.swift
//
//  Created by Alexander Cohen on 2026-11-01.
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
import KSCrashReportModel
import os.log

#if KSCRASH_HAS_METRICKIT_LEGACY
    import MetricKit
#endif

// MARK: - Diagnostic Stream (27+)
//
// On iOS, macOS, Mac Catalyst and visionOS 27 the monitor takes everything from the
// `MetricManager` async streams and never registers the legacy `MXMetricManagerSubscriber`
// (see `enabledDidChange`). Running both is not harmless: an opt-in
// `MetricManager(enabledStateReportingDomains:)` receives no diagnostics at all while the legacy
// subscriber is registered, and the two would deliver every crash and hang twice.
//
// Crash and hang go through the same handlers as the legacy path, and memory exceptions (iOS
// only) through their own. CPU exception, disk write exception and app launch diagnostics are
// only dumped, as they are on the legacy path.
//
// The API needs the 27 SDKs, so this compiles only under KSCRASH_HAS_METRICKIT_27_PLUS. An app
// built with an older Xcode uses the legacy subscriber on every OS version.

#if KSCRASH_HAS_METRICKIT_27_PLUS

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    extension MetricKitMonitor {

        /// Starts consuming `MetricManager.diagnosticReports` and `metricReports`. Safe to call
        /// repeatedly: running streams are left alone.
        func startDiagnosticReporting() {
            // Check-and-set under one lock acquisition so concurrent callers can't both start
            // streams. The manager is captured by the tasks so it lives as long as they do;
            // `self` is captured weakly so the long-lived tasks never keep the monitor alive.
            lock.withLock { state in
                guard state.diagnosticsTask == nil else { return }
                let manager = MetricManager()
                state.diagnosticsTask = Task { [weak self] in
                    os_log(.default, log: metricKitLog, "[MONITORS] Observing MetricManager.diagnosticReports")
                    for await report in manager.diagnosticReports {
                        if Task.isCancelled { break }
                        self?.handle(report)
                    }
                }
                // visionOS has no metric reports.
                #if !os(visionOS)
                    state.metricsTask = Task { [weak self] in
                        for await report in manager.metricReports {
                            if Task.isCancelled { break }
                            guard let self, self.configuration.dumpsPayloadsToDocuments else { continue }
                            MetricKitJSONDumper.dump(encodable: report, type: "27+/Metric")
                        }
                    }
                #endif
            }
        }

        /// Cancels the stream observers, if running.
        func stopDiagnosticReporting() {
            lock.withLock { state in
                state.diagnosticsTask?.cancel()
                state.diagnosticsTask = nil
                state.metricsTask?.cancel()
                state.metricsTask = nil
            }
        }

        private func handle(_ report: DiagnosticReport) {
            dump(report)

            let environment = report.environment
            // A crash or memory kill spans an instant (begin == end); for a hang the end is when
            // the hang finished. Either way the end is the timestamp, as the legacy payload's
            // timeStampEnd is.
            let timestamp = report.timeRange.end
            // The skeleton report's system info reflects the current session, not the one the
            // diagnostic describes, so only its process name survives.
            let systemInfo: (Report) -> SystemInfo = { skeleton in
                makeSystemInfo(from: environment, processName: skeleton.system?.processName)
            }

            let reportID: Report.ID?
            switch report.result {
            case .crash(let diagnostic):
                reportID = processCrash(
                    diagnostic.fields,
                    callStackTree: diagnostic.callStackTree.callStackRepresentation,
                    timestamp: timestamp,
                    applicationVersion: environment.applicationVersion,
                    systemInfo: systemInfo)
            case .hang(let diagnostic):
                reportID = processHang(
                    callStackTree: diagnostic.callStackTree.callStackRepresentation,
                    hangDuration: diagnostic.hangDuration,
                    timestamp: timestamp,
                    applicationVersion: environment.applicationVersion,
                    systemInfo: systemInfo)
            #if os(iOS) && !targetEnvironment(macCatalyst)
                case .memoryException(let diagnostic):
                    reportID = processMemoryException(diagnostic, timestamp: timestamp, systemInfo: systemInfo)
            #endif
            default:
                reportID = nil
            }
            if let reportID {
                recordDiagnosticReport(reportID)
            }
        }

        /// Dumps every stream result, handled or not, as the legacy payload dump does.
        private func dump(_ report: DiagnosticReport) {
            guard configuration.dumpsPayloadsToDocuments else { return }
            let kind: String
            switch report.result {
            case .crash: kind = "Crash"
            case .hang: kind = "Hang"
            case .cpuException: kind = "CPUException"
            case .diskWriteException: kind = "DiskWriteException"
            #if !os(visionOS)
                case .appLaunch: kind = "AppLaunch"
            #endif
            #if os(iOS) && !targetEnvironment(macCatalyst)
                case .memoryException: kind = "MemoryException"
            #endif
            default: kind = "Unknown"
            }
            MetricKitJSONDumper.dump(encodable: report, type: "27+/\(kind)")
        }
    }

    /// Builds a report's system info from the typed `DiagnosticReport.Environment`.
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    func makeSystemInfo(from environment: DiagnosticReport.Environment, processName: String?) -> SystemInfo {
        let os = environment.osVersion
        return SystemInfo(
            cfBundleIdentifier: environment.bundleIdentifier,
            cfBundleShortVersionString: environment.applicationVersion,
            cfBundleVersion: environment.applicationBuildVersion,
            cpuArch: environment.platformArchitecture,
            machine: environment.deviceType,
            osVersion: os.buildNumber,
            processID: environment.pid.map { Int($0) },
            processName: processName,
            systemName: os.platform,
            systemVersion: os.number,
            buildType: environment.isTestFlightApp ? .test : .appStore,
            lowPowerModeEnabled: environment.lowPowerModeEnabled
        )
    }

    // MARK: - Typed Diagnostic Adapters

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    extension CrashDiagnostic {
        var fields: CrashDiagnosticFields {
            CrashDiagnosticFields(
                exceptionType: exceptionType.map { UInt64(truncatingIfNeeded: $0) },
                exceptionCode: exceptionCode,
                signal: signal.map { UInt64(truncatingIfNeeded: $0) },
                terminationReason: terminationReason?.rawValue,
                virtualMemoryRegionInfo: virtualMemoryRegionInfo,
                exceptionName: exceptionReason?.exceptionName,
                exceptionMessage: exceptionReason?.composedMessage
            )
        }
    }

    // Adapts the typed `CallStackTree` into the shared `CallStackTreeRepresentation` used by the
    // crash and profile extraction, so all the tree-walking logic (and its tests) is reused
    // unchanged. Unlike the legacy `MXCallStackTree`, the new tree carries binary names in a
    // separate `binaryInfo` table rather than per frame, so `binaryName(from:)` resolves them as
    // each frame is converted.
    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    extension CallStackTree {
        var callStackRepresentation: CallStackTreeRepresentation {
            func convert(_ frame: CallStackFrame) -> CallStackTreeRepresentation.Frame {
                // `address` is optional in the new API. A frame without one becomes address 0
                // and keeps its binary UUID and offset, which is all that tells it apart from
                // other address-less frames (see `buildProfileData`).
                CallStackTreeRepresentation.Frame(
                    address: frame.address ?? 0,
                    binaryUUID: frame.binaryUUID?.uuidString,
                    binaryName: frame.binaryName(from: self),
                    offsetIntoBinaryTextSegment: frame.offsetIntoBinaryTextSegment,
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
