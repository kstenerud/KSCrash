//
//  KSCrashMonitor_MetricKit.swift
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
import os.log

#if os(iOS) || os(macOS)
    import MetricKit
#endif

#if SWIFT_PACKAGE
    import KSCrashRecording
    import KSCrashRecordingCore
    import SwiftCore
#endif

// MARK: - MetricKit Monitor

@available(iOS 14.0, macOS 12.0, *)
final class MetricKitMonitor: Sendable {

    static let lock = UnfairLock()

    static private var _enabled: Bool = false
    static var enabled: Bool {
        set { lock.withLock { _enabled = newValue } }
        get { lock.withLock { _enabled } }
    }

    static private let _monitorId = strdup("MetricKit")
    static var monitorId: UnsafePointer<CChar>? {
        lock.withLock { _monitorId.map { UnsafePointer($0) } }
    }

    static private var _callbacks: KSCrash_ExceptionHandlerCallbacks? = nil
    static var callbacks: KSCrash_ExceptionHandlerCallbacks? {
        set { lock.withLock { _callbacks = newValue } }
        get { lock.withLock { _callbacks } }
    }

    static private var _receiver: MetricKitReceiver? = nil
    static var receiver: MetricKitReceiver? {
        set { lock.withLock { _receiver = newValue } }
        get { lock.withLock { _receiver } }
    }

    static let api: UnsafeMutablePointer<KSCrashMonitorAPI> = {
        let api = KSCrashMonitorAPI(
            init: metricKitMonitorInit,
            monitorId: metricKitMonitorGetId,
            monitorFlags: metricKitMonitorGetFlags,
            setEnabled: metricKitMonitorSetEnabled,
            isEnabled: metricKitMonitorIsEnabled,
            addContextualInfoToEvent: metricKitMonitorAddContextualInfoToEvent,
            notifyPostSystemEnable: metricKitMonitorNotifyPostSystemEnable,
            writeInReportSection: metricKitMonitorWriteInReportSection,
            stitchReport: nil
        )

        let p = UnsafeMutablePointer<KSCrashMonitorAPI>.allocate(capacity: 1)  // never deallocated
        p.initialize(to: api)
        return p
    }()
}

// MARK: - C Function Pointer Callbacks

private func metricKitMonitorInit(
    _ callbacks: UnsafeMutablePointer<KSCrash_ExceptionHandlerCallbacks>?
) {
    if #available(iOS 14.0, macOS 12.0, *) {
        MetricKitMonitor.callbacks = callbacks?.pointee
    }
}

private func metricKitMonitorGetId() -> UnsafePointer<CChar>? {
    if #available(iOS 14.0, macOS 12.0, *) {
        return MetricKitMonitor.monitorId
    }
    return nil
}

private func metricKitMonitorGetFlags() -> KSCrashMonitorFlag {
    .init(0)
}

private func metricKitMonitorSetEnabled(_ isEnabled: Bool) {
    #if os(iOS) || os(macOS)
        if #available(iOS 14.0, macOS 12.0, *) {
            if isEnabled {
                if MetricKitMonitor.receiver == nil {
                    let newReceiver = MetricKitReceiver()
                    MetricKitMonitor.receiver = newReceiver
                    MXMetricManager.shared.add(newReceiver)
                    newReceiver.diagnosticsState = .waiting
                    newReceiver.metricsState = .waiting
                    os_log(.default, log: metricKitLog, "[MONITORS] Subscribed to MXMetricManager")

                    // Emit run ID via mxSignpost so MetricKit can capture it in diagnostics
                    emitRunIdSignpost()
                }
            } else {
                if let existing = MetricKitMonitor.receiver {
                    MXMetricManager.shared.remove(existing)
                    existing.diagnosticsState = .none
                    existing.metricsState = .none
                    MetricKitMonitor.receiver = nil
                    os_log(.default, log: metricKitLog, "[MONITORS] Unsubscribed from MXMetricManager")
                }
            }
            MetricKitMonitor.enabled = isEnabled
        }
    #endif
}

#if os(iOS) || os(macOS)
    @available(iOS 14.0, macOS 12.0, *)
    private func emitRunIdSignpost() {
        let runId = String(cString: kscrash_getRunID())

        // Emit with run ID as category
        let log1 = MXMetricManager.makeLogHandle(category: runId)
        mxSignpost(.event, log: log1, name: "com.kscrash.report.run_id")

        // Emit with run ID in format string (for testing)
        let log2 = MXMetricManager.makeLogHandle(category: "com.kscrash.report.run_id")
        mxSignpost(.event, log: log2, name: "run_id", "%{public, signpost:metrics}@", [runId])

        os_log(.default, log: metricKitLog, "[MONITORS] Emitted run ID signposts: %{public}@", runId)
    }
#endif

private func metricKitMonitorIsEnabled() -> Bool {
    if #available(iOS 14.0, macOS 12.0, *) {
        return MetricKitMonitor.enabled
    }
    return false
}

private func metricKitMonitorAddContextualInfoToEvent(
    _ eventContext: UnsafeMutablePointer<KSCrash_MonitorContext>?
) {
}

private func metricKitMonitorNotifyPostSystemEnable() {
}

private func metricKitMonitorWriteInReportSection(
    _ context: UnsafePointer<KSCrash_MonitorContext>?,
    _ writerRef: UnsafePointer<ReportWriter>?
) {
}
