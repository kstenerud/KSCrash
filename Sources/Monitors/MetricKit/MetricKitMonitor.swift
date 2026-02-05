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

#if SWIFT_PACKAGE
    import KSCrashRecording
    import KSCrashRecordingCore
    import SwiftCore
#endif

/// A monitor plugin that receives diagnostic and metric payloads from MetricKit.
@available(iOS 14.0, macOS 12.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public final class MetricKitMonitor: NSObject, MonitorPlugin, @unchecked Sendable {

    /// The processing state of the MetricKit receiver.
    public enum ProcessingState: String, Sendable {
        case none
        case waiting
        case processing
        case completed
    }

    /// Posted when the diagnostics or metrics processing state changes.
    /// The notification object is the `MetricKitMonitor` instance.
    public static let processingStateDidChangeNotification = Notification.Name("MetricKitMonitorStateDidChange")

    /// The underlying C monitor API.
    public let api: UnsafeMutablePointer<KSCrashMonitorAPI>

    /// The current state of diagnostic payload processing.
    public var diagnosticsState: ProcessingState {
        lock.withLock { $0.diagnosticsState }
    }

    /// The current state of metric payload processing.
    public var metricsState: ProcessingState {
        lock.withLock { $0.metricsState }
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
        var diagnosticsState: ProcessingState = .none
        var metricsState: ProcessingState = .none
        var dumpPayloadsToDocuments: Bool = false
        var threadcrumbEnabled: Bool = true
    }

    let lock = UnfairLock(MonitorState())

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
        free(_monitorId)
    }
}
