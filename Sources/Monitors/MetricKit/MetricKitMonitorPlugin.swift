//
//  MetricKitMonitorPlugin.swift
//
//  Created by Alexander Cohen on 2026-02-03.
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
#endif

/// The processing state of the MetricKit receiver.
@available(iOS 14.0, macOS 12.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public enum MetricKitProcessingState: String, Sendable {
    case none
    case waiting
    case processing
    case completed
}

/// A monitor plugin that receives diagnostic and metric payloads from MetricKit.
@available(iOS 14.0, macOS 12.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public final class MetricKitMonitorPlugin: NSObject, MonitorPlugin {

    /// Posted when the diagnostics or metrics processing state changes.
    /// The notification object is the `MetricKitMonitorPlugin` instance.
    public static let stateDidChangeNotification = Notification.Name("MetricKitMonitorPluginStateDidChange")

    let monitor = MetricKitMonitor()

    public var api: UnsafeMutablePointer<KSCrashMonitorAPI> {
        monitor.apiPointer
    }

    /// The current state of diagnostic payload processing.
    public var diagnosticsState: MetricKitProcessingState {
        #if os(iOS) || os(macOS)
            return monitor.receiver?.diagnosticsState ?? .none
        #else
            return .none
        #endif
    }

    /// The current state of metric payload processing.
    public var metricsState: MetricKitProcessingState {
        #if os(iOS) || os(macOS)
            return monitor.receiver?.metricsState ?? .none
        #else
            return .none
        #endif
    }

    /// When true, writes all received payloads as JSON to Documents/MetricKit/.
    /// Useful for debugging and exploring MetricKit data.
    /// Default is false.
    public var dumpPayloadsToDocuments: Bool {
        get { monitor.dumpPayloadsToDocuments }
        set { monitor.dumpPayloadsToDocuments = newValue }
    }

    /// When true, encodes the KSCrash run ID into a threadcrumb for MetricKit report correlation.
    /// This allows matching MetricKit crash reports to KSCrash reports from the same process run.
    /// Default is true.
    public var threadcrumbEnabled: Bool {
        get { monitor.threadcrumbEnabled }
        set { monitor.threadcrumbEnabled = newValue }
    }
}
