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
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashRecordingCore
import KSCrashReportModel
import KSCrashSwiftCore
import os.log

#if KSCRASH_HAS_METRICKIT
    import MetricKit
#endif

// MARK: - Internal Implementation

@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension MetricKitMonitor {

    /// The bridge owns enable/disable dispatch and only calls this on an actual state change
    /// (see `Monitor<M>`), so no idempotency guard is needed here, unlike the old hand-rolled
    /// C `setEnabled` callback this replaces.
    public func enabledDidChange(_ isEnabled: Bool) {
        #if KSCRASH_HAS_METRICKIT
            if isEnabled {
                MXMetricManager.shared.add(self)
                os_log(.default, log: metricKitLog, "[MONITORS] Subscribed to MXMetricManager")

                // iOS 27+ vends memory exception diagnostics only through the new
                // MetricManager async API; subscribe to it in addition to the legacy path.
                #if compiler(>=6.4) && os(iOS) && !targetEnvironment(macCatalyst)
                    if #available(iOS 27.0, *) {
                        startMemoryDiagnosticReporting()
                    }
                #endif

                if configuration.threadcrumbEnabled {
                    encodeRunIdThreadcrumb()
                }
            } else {
                MXMetricManager.shared.remove(self)

                #if compiler(>=6.4) && os(iOS) && !targetEnvironment(macCatalyst)
                    if #available(iOS 27.0, *) {
                        stopMemoryDiagnosticReporting()
                    }
                #endif

                os_log(.default, log: metricKitLog, "[MONITORS] Unsubscribed from MXMetricManager")
            }
        #endif
    }

    /// Records a diagnostic report as it is added: appends its id to ``diagnosticReportIDs`` and
    /// posts ``diagnosticReportAddedNotification`` carrying just that id in `userInfo`.
    func recordDiagnosticReport(_ reportID: Report.ID) {
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
        host.reportSidecarURL(name: name, extension: ext)
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

/// Stores a report payload through the C store. nil when it could not be
/// written; the id the store keyed it by otherwise.
func addMetricKitReport(_ data: Data) -> Report.ID? {
    var idBuffer = [CChar](repeating: 0, count: Int(KSID_LENGTH) + 1)
    let stored = data.withUnsafeBytes { buffer -> Bool in
        guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return false }
        return kscrash_addUserReport(ptr, Int32(buffer.count), &idBuffer)
    }
    guard stored else { return nil }
    return Report.ID(String(cString: idBuffer))
}
