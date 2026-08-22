//
//  CrashMonitor.swift
//
//  Created by Alexander Cohen on 2026-07-11.
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

/// A plugin monitor written in Swift. Conform, then register `MyMonitor.plugin(configuration)`
/// (or `MyMonitor.plugin()` when `Configuration == Void`) in `config.plugins`; the system
/// instantiates the monitor immediately, handing it its `MonitorHost` and its configuration.
/// Everything below `init(host:configuration:)` is optional and defaults to a no-op.
///
/// Plugin monitors run in a healthy process (MetricKit, Profiler, corpse reporting), never
/// inside a crash handler.
public protocol CrashMonitor: AnyObject {
    /// Typed per-event payload, carried from `host.handle(payload:)` to
    /// `writeReportSection(payload:)`. `Void` for monitors that don't write report sections.
    associatedtype EventPayload = Void

    /// Whatever configuration this monitor needs, passed through `MyMonitor.plugin(config)`
    /// and delivered at instantiation. `Void` for monitors that need none.
    associatedtype Configuration = Void

    /// The monitor id, e.g. "Corpse". Also names the report's monitor section.
    static var id: String { get }

    /// Defaults to `.plugin`.
    static var flags: MonitorFlags { get }

    /// Sidecar stitch ordering; higher wins on overlapping keys. Defaults to 0.
    static var stitchPriority: Int { get }

    /// Called when the bridge is created, before installation. An event raised from inside
    /// `init` is written without this monitor's report section.
    init(host: MonitorHost<EventPayload>, configuration: Configuration)

    /// The enabled state changed. The flag itself lives on the bridge, readable through
    /// `host.isEnabled`.
    func enabledDidChange(_ isEnabled: Bool)

    /// After all monitors are enabled, before RunContext init (notifyPostMonitorsEnabled).
    func monitorsDidEnable()

    /// After RunContext is initialized (notifyPostSystemEnable). Never fires in an
    /// extension-reporting install, where RunContext does not initialize.
    func systemDidEnable()

    /// Runs during the report write, inside this monitor's object under
    /// `crash.error.monitor_data` (the profile's typed schema key for the profiler), with the
    /// payload that was passed to `host.handle(payload:)` for this event.
    func writeReportSection(payload: EventPayload, writer: ReportSectionWriter)

    /// Stitches this monitor's sidecar data into a report at delivery time. Runs at normal app
    /// startup, not during crash handling. Return the (possibly modified) report; throw to
    /// signal a stitch error (finalization aborts the write-back so the report is retried on
    /// the next read; normal reads keep the original silently).
    ///
    /// For `.final` there is no sidecar (`sidecarURL` is nil): after all sidecar stitching,
    /// every monitor gets one last chance to modify the report, drawing on the report itself.
    func stitchedReport(_ report: [String: Any], sidecarURL: URL?, scope: SidecarScope) throws -> [String: Any]
}

extension CrashMonitor {
    public static var flags: MonitorFlags { .plugin }
    public static var stitchPriority: Int { 0 }
    public func enabledDidChange(_ isEnabled: Bool) {}
    public func monitorsDidEnable() {}
    public func systemDidEnable() {}
    public func writeReportSection(payload: EventPayload, writer: ReportSectionWriter) {}
    public func stitchedReport(_ report: [String: Any], sidecarURL: URL?, scope: SidecarScope) throws -> [String: Any] {
        report
    }
}

extension CrashMonitor {
    /// Registration shorthand: `config.plugins = [MyMonitor.plugin(configuration)]`.
    public static func plugin(_ configuration: Configuration) -> Monitor<Self> {
        Monitor(Self.self, configuration)
    }
}

/// The C types a conformer names, re-exported so it needs no `KSCrashRecordingCore` import.
public typealias MonitorFlags = KSCrashRecordingCore.MonitorFlags
public typealias SidecarScope = KSCrashRecordingCore.SidecarScope
public typealias EventRequirements = KSCrashRecordingCore.EventRequirements

extension CrashMonitor where Configuration == Void {
    /// Registration shorthand for configuration-less monitors.
    public static func plugin() -> Monitor<Self> {
        Monitor(Self.self, ())
    }
}
