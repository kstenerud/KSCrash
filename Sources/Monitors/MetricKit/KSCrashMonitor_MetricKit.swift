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
@available(tvOS, unavailable)
@available(watchOS, unavailable)
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

    #if os(iOS) || os(macOS)
        static private var _receiver: MetricKitReceiver? = nil
        static var receiver: MetricKitReceiver? {
            set { lock.withLock { _receiver = newValue } }
            get { lock.withLock { _receiver } }
        }
    #endif

    static private var _dumpPayloadsToDocuments: Bool = false
    static var dumpPayloadsToDocuments: Bool {
        set { lock.withLock { _dumpPayloadsToDocuments = newValue } }
        get { lock.withLock { _dumpPayloadsToDocuments } }
    }

    static private var _threadcrumbEnabled: Bool = true
    static var threadcrumbEnabled: Bool {
        set { lock.withLock { _threadcrumbEnabled = newValue } }
        get { lock.withLock { _threadcrumbEnabled } }
    }

    #if os(iOS) || os(macOS)
        static let runIdHandler = MetricKitRunIdHandler()
    #endif

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
        #if os(iOS) || os(macOS)
            MetricKitMonitor.callbacks = callbacks?.pointee
        #endif
    }
}

private func metricKitMonitorGetId() -> UnsafePointer<CChar>? {
    if #available(iOS 14.0, macOS 12.0, *) {
        #if os(iOS) || os(macOS)
            return MetricKitMonitor.monitorId
        #else
            return nil
        #endif
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
                    newReceiver.diagnosticsState = .waiting
                    newReceiver.metricsState = .waiting

                    MetricKitMonitor.receiver = newReceiver
                    MXMetricManager.shared.add(newReceiver)
                    os_log(.default, log: metricKitLog, "[MONITORS] Subscribed to MXMetricManager")

                    // Encode run ID into threadcrumb stack for MetricKit report correlation
                    if MetricKitMonitor.threadcrumbEnabled {
                        encodeRunIdThreadcrumb()
                    }
                }
            } else {
                if let existing = MetricKitMonitor.receiver {
                    MXMetricManager.shared.remove(existing)

                    MetricKitMonitor.receiver = nil
                    existing.diagnosticsState = .none
                    existing.metricsState = .none

                    os_log(.default, log: metricKitLog, "[MONITORS] Unsubscribed from MXMetricManager")
                }
            }
            MetricKitMonitor.enabled = isEnabled
        }
    #endif
}

#if os(iOS) || os(macOS)
    @available(iOS 14.0, macOS 12.0, *)
    func sidecarPathProvider(name: String, extension ext: String) -> URL? {
        guard let callbacks = MetricKitMonitor.callbacks,
            let getSidecarFilePath = callbacks.getSidecarFilePath,
            let monitorId = MetricKitMonitor.monitorId
        else {
            return nil
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(KSCRS_MAX_PATH_LENGTH))
        guard getSidecarFilePath(monitorId, name, ext, &pathBuffer, pathBuffer.count) else {
            return nil
        }

        return URL(fileURLWithPath: String(cString: pathBuffer))
    }

    @available(iOS 14.0, macOS 12.0, *)
    private func encodeRunIdThreadcrumb() {
        let runId = String(cString: kscrash_getRunID())

        let success = MetricKitMonitor.runIdHandler.encode(runId: runId, pathProvider: sidecarPathProvider)

        if success {
            os_log(.default, log: metricKitLog, "[MONITORS] Encoded run ID into threadcrumb: %{public}@", runId)
        } else {
            os_log(.error, log: metricKitLog, "[MONITORS] Failed to encode run ID into threadcrumb")
        }
    }
#endif

private func metricKitMonitorIsEnabled() -> Bool {
    if #available(iOS 14.0, macOS 12.0, *) {
        #if os(iOS) || os(macOS)
            return MetricKitMonitor.enabled
        #else
            return false
        #endif
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
