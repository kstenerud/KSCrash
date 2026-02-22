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
import os.log

#if KSCRASH_HAS_METRICKIT
    import MetricKit
#endif

#if SWIFT_PACKAGE
    import KSCrashRecording
    import KSCrashRecordingCore
    import SwiftCore
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
                    init: { callbacks, cntxt in
                        MetricKitMonitor.from(cntxt)?.callbacks = callbacks?.pointee
                    },
                    monitorId: {
                        MetricKitMonitor.from($0)?.monitorId
                    },
                    monitorFlags: { _ in KSCrashMonitorFlag(0) },
                    setEnabled: metricKitMonitorSetEnabled,
                    isEnabled: { cntxt in
                        MetricKitMonitor.from(cntxt)?.enabled ?? false
                    },
                    addContextualInfoToEvent: { _, _ in },
                    notifyPostSystemEnable: { _ in },
                    writeInReportSection: nil,
                    stitchReport: nil
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

    func updateDiagnosticsState(_ state: ProcessingState, reportIDs: [Int64] = []) {
        lock.withLock {
            $0.diagnosticReportIDs = reportIDs
            $0.diagnosticsState = state
        }
        postStateChangeNotification()
    }

    func updateMetricsState(_ state: ProcessingState) {
        lock.withLock { $0.metricsState = state }
        postStateChangeNotification()
    }

    func postStateChangeNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: MetricKitMonitor.processingStateDidChangeNotification,
                object: self
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
                    monitor.updateDiagnosticsState(.waiting)
                    monitor.updateMetricsState(.waiting)

                    MXMetricManager.shared.add(monitor)
                    os_log(.default, log: metricKitLog, "[MONITORS] Subscribed to MXMetricManager")

                    if monitor.threadcrumbEnabled {
                        monitor.encodeRunIdThreadcrumb()
                    }
                }
            } else {
                if monitor.enabled {
                    MXMetricManager.shared.remove(monitor)

                    monitor.updateDiagnosticsState(.none)
                    monitor.updateMetricsState(.none)

                    os_log(.default, log: metricKitLog, "[MONITORS] Unsubscribed from MXMetricManager")
                }
            }
            monitor.enabled = isEnabled
        }
    #endif
}
