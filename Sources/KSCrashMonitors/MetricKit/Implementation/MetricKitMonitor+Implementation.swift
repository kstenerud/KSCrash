//
//  MetricKitMonitor+Implementation.swift
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
import KSCrashSwiftCore
import os.log

#if KSCRASH_HAS_METRICKIT
    import MetricKit
#endif

// MARK: - Internal Implementation

@available(iOS 14.0, macOS 12.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension MetricKitMonitor {

    /// Initializes the pre-allocated `api` pointer with the monitor's callback table
    /// and sets `context` to `self` (unretained) so every C callback can recover the instance.
    /// Expects `api` to already be allocated with a capacity of 1 `KSCrashMonitorAPI`.
    func initAPI() {
        self.api.initialize(
            to:
                KSCrashMonitorAPI(
                    context: nil,
                    priority: 0,
                    init: { callbacks, cntxt in
                        MetricKitMonitor.from(cntxt)?.callbacks = callbacks?.pointee
                    },
                    monitorId: {
                        MetricKitMonitor.from($0)?.monitorId
                    },
                    monitorFlags: { _ in KSCrashMonitorFlagPlugin },
                    setEnabled: metricKitMonitorSetEnabled,
                    isEnabled: { cntxt in
                        MetricKitMonitor.from(cntxt)?.enabled ?? false
                    },
                    addContextualInfoToEvent: { _, _ in },
                    notifyPostMonitorsEnabled: nil,
                    notifyPostSystemEnable: { _ in },
                    writeInReportSection: nil,
                    createStitchedReport: nil
                )
        )
        self.api.pointee.context = Unmanaged.passUnretained(self).toOpaque()
    }

    /// Recovers the `MetricKitMonitor` instance from the opaque context pointer
    /// passed to every `KSCrashMonitorAPI` callback.
    static func from(_ context: UnsafeMutableRawPointer?) -> MetricKitMonitor? {
        guard let context = context else { return nil }
        return Unmanaged<MetricKitMonitor>.fromOpaque(context).takeUnretainedValue()
    }

    /// Records a diagnostic report as it is added: appends its id to ``diagnosticReportIDs`` and
    /// posts ``diagnosticReportAddedNotification`` carrying just that id in `userInfo`.
    func recordDiagnosticReport(_ reportID: Int64) {
        lock.withLock { $0.diagnosticReportIDs.append(reportID) }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: MetricKitMonitor.diagnosticReportAddedNotification,
                object: self,
                userInfo: [MetricKitMonitor.diagnosticReportIDUserInfoKey: reportID]
            )
        }
    }

    func sidecarPathProvider(name: String, extension ext: String) -> URL? {
        guard let callbacks = callbacks,
            let getReportSidecarFilePath = callbacks.getReportSidecarFilePath,
            let monitorId = monitorId
        else {
            return nil
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(KSCRS_MAX_PATH_LENGTH))
        guard getReportSidecarFilePath(monitorId, name, ext, &pathBuffer, pathBuffer.count) else {
            return nil
        }

        return URL(fileURLWithPath: String(cString: pathBuffer))
    }

    func encodeRunIdThreadcrumb() {
        let runId = String(cString: kscrash_getRunID())

        let success = runIdHandler.encode(runId: runId) { name, ext in
            self.sidecarPathProvider(name: name, extension: ext)
        }

        if success {
            os_log(.default, log: metricKitLog, "[MONITORS] Encoded run ID into threadcrumb: %{public}@", runId)
        } else {
            os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode run ID into threadcrumb")
        }
    }
}

// MARK: - KSCrashMonitorAPI Callbacks

func metricKitMonitorSetEnabled(_ isEnabled: Bool, _ context: UnsafeMutableRawPointer?) {
    #if KSCRASH_HAS_METRICKIT
        if #available(iOS 14.0, macOS 12.0, *) {
            guard let monitor = MetricKitMonitor.from(context) else { return }
            if isEnabled {
                if !monitor.enabled {
                    MXMetricManager.shared.add(monitor)
                    os_log(.default, log: metricKitLog, "[MONITORS] Subscribed to MXMetricManager")

                    // iOS 27+ vends memory exception diagnostics only through the new
                    // MetricManager async API; subscribe to it in addition to the legacy path.
                    #if compiler(>=6.4) && os(iOS) && !targetEnvironment(macCatalyst)
                        if #available(iOS 27.0, *) {
                            monitor.startMemoryDiagnosticReporting()
                        }
                    #endif

                    if monitor.threadcrumbEnabled {
                        monitor.encodeRunIdThreadcrumb()
                    }
                }
            } else {
                if monitor.enabled {
                    MXMetricManager.shared.remove(monitor)

                    #if compiler(>=6.4) && os(iOS) && !targetEnvironment(macCatalyst)
                        if #available(iOS 27.0, *) {
                            monitor.stopMemoryDiagnosticReporting()
                        }
                    #endif

                    os_log(.default, log: metricKitLog, "[MONITORS] Unsubscribed from MXMetricManager")
                }
            }
            monitor.enabled = isEnabled
        }
    #endif
}
