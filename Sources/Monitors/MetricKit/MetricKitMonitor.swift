//
//  MetricKitMonitor.swift
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
final class MetricKitMonitor: @unchecked Sendable {

    private let lock = UnfairLock()

    private var _enabled: Bool = false
    var enabled: Bool {
        set { lock.withLock { _enabled = newValue } }
        get { lock.withLock { _enabled } }
    }

    private let _monitorId: UnsafeMutablePointer<CChar>? = strdup("MetricKit")
    var monitorId: UnsafePointer<CChar>? {
        _monitorId.map { UnsafePointer($0) }
    }

    deinit {
        free(_monitorId)
    }

    private var _callbacks: KSCrash_ExceptionHandlerCallbacks? = nil
    var callbacks: KSCrash_ExceptionHandlerCallbacks? {
        set { lock.withLock { _callbacks = newValue } }
        get { lock.withLock { _callbacks } }
    }

    #if os(iOS) || os(macOS)
        private var _receiver: MetricKitReceiver? = nil
        var receiver: MetricKitReceiver? {
            set { lock.withLock { _receiver = newValue } }
            get { lock.withLock { _receiver } }
        }
    #endif

    private var _dumpPayloadsToDocuments: Bool = false
    var dumpPayloadsToDocuments: Bool {
        set { lock.withLock { _dumpPayloadsToDocuments = newValue } }
        get { lock.withLock { _dumpPayloadsToDocuments } }
    }

    private var _threadcrumbEnabled: Bool = true
    var threadcrumbEnabled: Bool {
        set { lock.withLock { _threadcrumbEnabled = newValue } }
        get { lock.withLock { _threadcrumbEnabled } }
    }

    #if os(iOS) || os(macOS)
        let runIdHandler = MetricKitRunIdHandler()
    #endif

    /// Heap-allocated API struct whose `context` points back to this instance.
    /// Never deallocated — the plugin holds a strong reference that keeps self alive.
    let apiPointer: UnsafeMutablePointer<KSCrashMonitorAPI>

    init() {
        let api = KSCrashMonitorAPI(
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

        let p = UnsafeMutablePointer<KSCrashMonitorAPI>.allocate(capacity: 1)
        p.initialize(to: api)
        self.apiPointer = p
        // Safe: the plugin holds a strong reference, so self outlives the API pointer.
        p.pointee.context = Unmanaged.passUnretained(self).toOpaque()
    }

    /// Recovers the `MetricKitMonitor` instance from the opaque context pointer
    /// passed to every `KSCrashMonitorAPI` callback.
    static func from(_ context: UnsafeMutableRawPointer?) -> MetricKitMonitor? {
        guard let context = context else { return nil }
        return Unmanaged<MetricKitMonitor>.fromOpaque(context).takeUnretainedValue()
    }

    #if os(iOS) || os(macOS)
        func sidecarPathProvider(name: String, extension ext: String) -> URL? {
            guard let callbacks = callbacks,
                let getSidecarFilePath = callbacks.getSidecarFilePath,
                let monitorId = monitorId
            else {
                return nil
            }

            var pathBuffer = [CChar](repeating: 0, count: Int(KSCRS_MAX_PATH_LENGTH))
            guard getSidecarFilePath(monitorId, name, ext, &pathBuffer, pathBuffer.count) else {
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
    #endif
}

// MARK: - KSCrashMonitorAPI Callbacks

private func metricKitMonitorSetEnabled(_ isEnabled: Bool, _ context: UnsafeMutableRawPointer?) {
    #if os(iOS) || os(macOS)
        if #available(iOS 14.0, macOS 12.0, *) {
            guard let monitor = MetricKitMonitor.from(context) else { return }
            if isEnabled {
                if monitor.receiver == nil {
                    let config = MetricKitReceiverConfig(
                        apiPointer: monitor.apiPointer,
                        callbacks: monitor.callbacks,
                        dumpPayloadsToDocuments: monitor.dumpPayloadsToDocuments,
                        runIdHandler: monitor.runIdHandler,
                        monitorId: monitor.monitorId
                    )
                    let newReceiver = MetricKitReceiver(config: config)
                    newReceiver.diagnosticsState = .waiting
                    newReceiver.metricsState = .waiting

                    monitor.receiver = newReceiver
                    MXMetricManager.shared.add(newReceiver)
                    os_log(.default, log: metricKitLog, "[MONITORS] Subscribed to MXMetricManager")

                    if monitor.threadcrumbEnabled {
                        monitor.encodeRunIdThreadcrumb()
                    }
                }
            } else {
                if let existing = monitor.receiver {
                    MXMetricManager.shared.remove(existing)

                    monitor.receiver = nil
                    existing.diagnosticsState = .none
                    existing.metricsState = .none

                    os_log(.default, log: metricKitLog, "[MONITORS] Unsubscribed from MXMetricManager")
                }
            }
            monitor.enabled = isEnabled
        }
    #endif
}
