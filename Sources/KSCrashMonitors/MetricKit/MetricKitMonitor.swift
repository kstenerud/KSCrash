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
import KSCrashRecording
import KSCrashRecordingCore
import KSCrashSwiftCore

/// A monitor plugin that receives diagnostic and metric payloads from MetricKit.
@available(iOS 14.0, macOS 12.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public final class MetricKitMonitor: NSObject, MonitorPlugin, @unchecked Sendable {

    /// Posted once per diagnostic report as it is added, with the id of the report that was just
    /// added in `userInfo` under ``diagnosticReportIDUserInfoKey``. The notification object is the
    /// `MetricKitMonitor` instance.
    public static let diagnosticReportAddedNotification = Notification.Name("MetricKitMonitorDiagnosticReportAdded")

    /// `userInfo` key on ``diagnosticReportAddedNotification`` whose value is the `Int64` id of
    /// the diagnostic report that was just added.
    public static let diagnosticReportIDUserInfoKey = "diagnosticReportID"

    /// The underlying C monitor API.
    public let api: UnsafeMutablePointer<KSCrashMonitorAPI>

    /// The ids of every diagnostic report added by this monitor, in the order they were added.
    /// Each addition also posts ``diagnosticReportAddedNotification`` carrying just that id.
    public var diagnosticReportIDs: [Int64] {
        lock.withLock { $0.diagnosticReportIDs }
    }

    /// When true, writes all received payloads as JSON to Documents/MetricKit/.
    /// Useful for debugging and exploring MetricKit data.
    /// Default is false.
    public var dumpPayloadsToDocuments: Bool {
        set { lock.withLock { $0.dumpPayloadsToDocuments = newValue } }
        get { lock.withLock { $0.dumpPayloadsToDocuments } }
    }

    /// When true, encodes the KSCrash run ID into a threadcrumb for MetricKit report correlation.
    /// This allows matching MetricKit crash reports to KSCrash reports from the same process run.
    /// Default is true.
    public var threadcrumbEnabled: Bool {
        set { lock.withLock { $0.threadcrumbEnabled = newValue } }
        get { lock.withLock { $0.threadcrumbEnabled } }
    }

    // MARK: - Internal State

    struct MonitorState {
        var enabled: Bool = false
        var callbacks: KSCrash_ExceptionHandlerCallbacks? = nil
        var diagnosticReportIDs: [Int64] = []
        var dumpPayloadsToDocuments: Bool = false
        var threadcrumbEnabled: Bool = true
        // Gated to match the only code that uses it (the iOS 27 memory stream in
        // MetricKitMonitor+Subscriber). `Task` requires watchOS 6.0+, and this type is compiled
        // — though unavailable — on watchOS, so an ungated field breaks the watchOS build under
        // the package's lower deployment target.
        #if compiler(>=6.4) && os(iOS) && !targetEnvironment(macCatalyst)
            /// Long-lived task consuming the iOS 27+ `MetricManager.diagnosticReports` stream.
            var memoryDiagnosticsTask: Task<Void, Never>? = nil
        #endif
    }

    let lock = UnfairLock(MonitorState())

    /// Serializes skeleton-report production. The shared exception-handling state in
    /// KSCrashMonitor.c (`notify`/`handle`) is not safe to enter concurrently, and on iOS 27
    /// two MetricKit delivery mechanisms run on different threads — the legacy
    /// `MXMetricManagerSubscriber` (crash/hang) and the `MetricManager` async stream (memory).
    /// This lock keeps `writeSkeletonReport` calls from overlapping across them.
    let skeletonLock = UnfairLock()

    var enabled: Bool {
        set { lock.withLock { $0.enabled = newValue } }
        get { lock.withLock { $0.enabled } }
    }

    private let _monitorId: UnsafeMutablePointer<CChar>? = strdup("MetricKit")
    var monitorId: UnsafePointer<CChar>? {
        _monitorId.map { UnsafePointer($0) }
    }

    var callbacks: KSCrash_ExceptionHandlerCallbacks? {
        set { lock.withLock { $0.callbacks = newValue } }
        get { lock.withLock { $0.callbacks } }
    }

    let runIdHandler = MetricKitRunIdHandler()

    // MARK: - Lifecycle

    override public init() {
        self.api = UnsafeMutablePointer<KSCrashMonitorAPI>.allocate(capacity: 1)
        super.init()
        self.initAPI()
    }

    deinit {
        api.deinitialize(count: 1)
        api.deallocate()
        free(_monitorId)
    }
}
