//
//  MonitorHost.swift
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

import Darwin
import Foundation
import KSCrashRecording
import KSCrashRecordingCore

/// A monitor's typed connection to the exception-handling pipeline, injected through
/// `CrashMonitor.init(host:configuration:)`.
///
/// The host goes live when the bridge installs; before then `handle` throws `.refused` and the
/// sidecar accessors return nil.
public struct MonitorHost<Payload> {
    /// The bridge, which owns the callbacks, the enabled flag, and the api identity. Unowned
    /// to break the cycle: the bridge owns the monitor that holds this host, and a host lives
    /// exactly as long as its bridge.
    private unowned let bridge: MonitorCore

    init(bridge: MonitorCore) {
        self.bridge = bridge
    }

    /// The monitor's enabled state, owned by the bridge.
    public var isEnabled: Bool { bridge.isEnabled }

    public enum EventError: Error {
        /// The pipeline refused the event (not yet installed, shutting down, or a recrash
        /// flood whose bail-out context must not be touched).
        case refused
        /// The pipeline accepted the event but produced no report.
        case notWritten
    }

    /// A report the pipeline wrote for one handled event.
    public struct WrittenReport {
        public let id: Int64
        /// The report file's location, when the pipeline reported one.
        public let url: URL?
    }

    /// Runs one event through the pipeline: notify → monitor-context fill → `configure` for the
    /// raw per-event fields → payload boxing → handle. Returns the written report.
    ///
    /// A nil `payload` writes the report WITHOUT this monitor's report section
    /// (`writeReportSection` never runs for the event); the corpse monitor uses this for
    /// snapshot-less captures.
    ///
    /// `configure` sets the raw per-event fields on the monitor context: mach codes, machine
    /// context, provided images, processName.
    ///
    /// `finalize` only applies to reports the store minted an ID for. An event whose `configure`
    /// sets a custom `reportPath` writes outside the store and never finalizes, even with
    /// `finalize: true`.
    public func handle(
        payload: Payload?,
        requirements: EventRequirements,
        subjectThread: thread_t = thread_t(MACH_PORT_NULL),
        finalize: Bool = false,
        configure: (UnsafeMutablePointer<KSCrash_MonitorContext>) -> Void
    ) throws -> WrittenReport {
        guard let payload else {
            return try handle(
                boxedPayload: nil, requirements: requirements, subjectThread: subjectThread,
                finalize: finalize, configure: configure)
        }
        // Retained across the write, released after; the bridge unboxes it for
        // writeReportSection.
        let box = Unmanaged.passRetained(PayloadBox(payload)).toOpaque()
        defer { Unmanaged<PayloadBox>.fromOpaque(box).release() }
        return try handle(
            boxedPayload: box, requirements: requirements, subjectThread: subjectThread,
            finalize: finalize, configure: configure)
    }

    private func handle(
        boxedPayload: UnsafeMutableRawPointer?,
        requirements: EventRequirements,
        subjectThread: thread_t,
        finalize: Bool,
        configure: (UnsafeMutablePointer<KSCrash_MonitorContext>) -> Void
    ) throws -> WrittenReport {
        guard let callbacks = bridge.callbacks,
            let context = callbacks.notify(subjectThread, requirements)
        else { throw EventError.refused }
        if context.pointee.requirements.shouldExitImmediately != 0 {
            // Pipeline meltdown (a recrash flood): the returned context is a shared bail-out
            // slot whose contract is do nothing, touch nothing, get out.
            throw EventError.refused
        }
        kscm_fillMonitorContext(context, bridge.api)
        // Assigned explicitly (nil included) so no stale pointer survives from a previous
        // event in this slot.
        context.pointee.callbackContext = boxedPayload
        configure(context)

        var result = KSCrash_ReportResult()
        callbacks.handleWithResult(context, &result, finalize)
        guard result.reportId > 0 else { throw EventError.notWritten }
        let path = withUnsafePointer(to: &result.path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(PATH_MAX)) { String(cString: $0) }
        }
        return WrittenReport(id: result.reportId, url: path.isEmpty ? nil : URL(fileURLWithPath: path))
    }

    /// This monitor's per-report sidecar path for `reportID`, or nil when sidecars are not
    /// configured.
    public func reportSidecarURL(reportID: Int64) -> URL? {
        guard let provider = bridge.callbacks?.getReportSidecarPath else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(KSCRS_MAX_PATH_LENGTH))
        guard provider(bridge.monitorIdC, reportID, &buffer, buffer.count) else { return nil }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    /// This monitor's named per-report sidecar path (`Sidecars/<id>/<name>.<extension>`),
    /// or nil when sidecars are not configured.
    public func reportSidecarURL(name: String, extension ext: String) -> URL? {
        guard let provider = bridge.callbacks?.getReportSidecarFilePath else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(KSCRS_MAX_PATH_LENGTH))
        guard provider(bridge.monitorIdC, name, ext, &buffer, buffer.count) else { return nil }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    /// This monitor's run-scoped sidecar path, or nil when sidecars are not configured.
    public func runSidecarURL() -> URL? {
        guard let provider = bridge.callbacks?.getRunSidecarPath else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(KSCRS_MAX_PATH_LENGTH))
        guard provider(bridge.monitorIdC, &buffer, buffer.count) else { return nil }
        return URL(fileURLWithPath: String(cString: buffer))
    }
}

extension MonitorHost where Payload == Void {
    /// The payload-less variant for monitors with no per-event payload; their
    /// `writeReportSection(payload:)` still runs for the event.
    public func handle(
        requirements: EventRequirements,
        subjectThread: thread_t = thread_t(MACH_PORT_NULL),
        finalize: Bool = false,
        configure: (UnsafeMutablePointer<KSCrash_MonitorContext>) -> Void
    ) throws -> WrittenReport {
        try handle(
            payload: nil, requirements: requirements, subjectThread: subjectThread,
            finalize: finalize, configure: configure)
    }
}

/// Carries a monitor's per-event payload through `KSCrash_MonitorContext.callbackContext`
/// from `MonitorHost.handle(payload:)` to the bridge's writeInReportSection trampoline.
final class PayloadBox {
    let value: Any
    init(_ value: Any) { self.value = value }
}

extension EventRequirements {
    /// A fatal event about a subject other than this process (a corpse): all of the subject's
    /// threads are recorded, and no process-local effect fires.
    public static let fatalRemoteSubject = EventRequirements(
        shouldRecordAllThreads: 1,
        shouldWriteReport: 1,
        isFatal: 1,
        isCleanExit: 0,
        asyncSafety: 0,
        asyncSafetyBecauseThreadsSuspended: 0,
        crashedDuringExceptionHandling: 0,
        shouldExitImmediately: 0,
        isRemoteSubject: 1
    )

    /// A non-fatal report about this process; the app keeps running.
    public static let nonFatal = EventRequirements(
        shouldRecordAllThreads: 0,
        shouldWriteReport: 1,
        isFatal: 0,
        isCleanExit: 0,
        asyncSafety: 0,
        asyncSafetyBecauseThreadsSuspended: 0,
        crashedDuringExceptionHandling: 0,
        shouldExitImmediately: 0,
        isRemoteSubject: 0
    )
}
