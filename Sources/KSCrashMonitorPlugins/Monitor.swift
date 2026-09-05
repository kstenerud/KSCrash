//
//  Monitor.swift
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
import KSCrashSwiftCore

/// The non-generic half of the bridge, owning everything C-facing (the api table, the id
/// string, the callbacks, the enabled flag) plus type-erased hooks that `Monitor<M>` fills
/// with closures. The C trampolines recover this class from the api's opaque context pointer.
///
/// Consumers use `Monitor<M>`; `api` is this class's only public member.
///
/// `@unchecked Sendable`: the pointers are immutable for the bridge's lifetime, and the only
/// mutable state is the lock-guarded callbacks and the atomic enabled flag.
public class MonitorCore: NSObject, MonitorPlugin, @unchecked Sendable {

    /// The C monitor api, alive for the bridge's lifetime (bridges live in `config.plugins`
    /// or as statics, effectively forever).
    public let api: UnsafeMutablePointer<KSCrashMonitorAPI>

    let monitorIdC: UnsafeMutablePointer<CChar>

    fileprivate let flags: MonitorFlags

    struct BridgeState {
        var callbacks: KSCrash_ExceptionHandlerCallbacks? = nil
    }
    private let lock = UnfairLock(BridgeState())

    // Lock-free on both sides: this is read during crash handling, where other threads are
    // suspended and taking a lock could deadlock.
    private let enabled = AtomicFlag()

    var callbacks: KSCrash_ExceptionHandlerCallbacks? {
        lock.withLock { $0.callbacks }
    }

    /// The bridge owns the enabled flag; monitors only get `enabledDidChange` notifications.
    var isEnabled: Bool { enabled.value }

    /// True once the pipeline has connected (install ran); handle() refuses before then.
    var isInstalled: Bool { lock.withLock { $0.callbacks != nil } }

    // Type-erased hooks, filled by Monitor<M> at init. All run on whatever thread the
    // pipeline calls the C table from.
    fileprivate var enabledChangeHandler: (Bool) -> Void = { _ in }
    fileprivate var monitorsDidEnableHandler: () -> Void = {}
    fileprivate var systemDidEnableHandler: () -> Void = {}
    fileprivate var writeSectionHandler:
        (UnsafePointer<KSCrash_MonitorContext>?, UnsafePointer<ReportWriter>?) -> Void = {
            _, _ in
        }
    /// CF Create Rule: returns +1 (the no-op default retains and returns the input); nil is a
    /// stitch error. The path is nil for the final pass, which has no sidecar file.
    fileprivate var stitchHandler: (CFDictionary, UnsafePointer<CChar>?, SidecarScope) -> Unmanaged<CFDictionary>? = {
        dict, _, _ in
        Unmanaged.passRetained(dict)
    }

    fileprivate init(id: String, flags: MonitorFlags, stitchPriority: Int) {
        self.monitorIdC = strdup(id)
        self.flags = flags
        self.api = UnsafeMutablePointer<KSCrashMonitorAPI>.allocate(capacity: 1)
        super.init()

        // Trampolines must be literal non-capturing closures; each recovers the bridge from
        // the opaque context pointer.
        self.api.initialize(
            to:
                KSCrashMonitorAPI(
                    context: nil,
                    priority: Int32(stitchPriority),
                    init: { callbacks, context in
                        guard let bridge = MonitorCore.from(context) else { return }
                        bridge.lock.withLock { $0.callbacks = callbacks?.pointee }
                    },
                    monitorId: { context in
                        MonitorCore.from(context).map { UnsafePointer($0.monitorIdC) }
                    },
                    monitorFlags: { context in
                        MonitorCore.from(context)?.flags ?? []
                    },
                    setEnabled: { isEnabled, context in
                        guard let bridge = MonitorCore.from(context) else { return }
                        if bridge.enabled.exchange(isEnabled) != isEnabled {
                            bridge.enabledChangeHandler(isEnabled)
                        }
                    },
                    isEnabled: { context in
                        MonitorCore.from(context)?.isEnabled ?? false
                    },
                    addContextualInfoToEvent: { _, _ in },
                    notifyPostMonitorsEnabled: { context in
                        MonitorCore.from(context)?.monitorsDidEnableHandler()
                    },
                    notifyPostSystemEnable: { context in
                        MonitorCore.from(context)?.systemDidEnableHandler()
                    },
                    writeInReportSection: { eventContext, writer, context in
                        MonitorCore.from(context)?.writeSectionHandler(eventContext, writer)
                    },
                    createStitchedReport: { reportDict, sidecarPath, scope, context in
                        // sidecarPath is NULL for the final pass; only the report is required.
                        guard let bridge = MonitorCore.from(context), let reportDict else {
                            return nil
                        }
                        return bridge.stitchHandler(reportDict, sidecarPath, scope)
                    }
                )
        )
        self.api.pointee.context = Unmanaged.passUnretained(self).toOpaque()
    }

    private static func from(_ context: UnsafeMutableRawPointer?) -> MonitorCore? {
        context.map { Unmanaged<MonitorCore>.fromOpaque($0).takeUnretainedValue() }
    }

    deinit {
        api.deinitialize(count: 1)
        api.deallocate()
        free(monitorIdC)
    }
}

/// Hosts a `CrashMonitor` on the C monitor pipeline. Register it with `MyMonitor.plugin(...)`,
/// or pass its `api` to an install function directly. The monitor is instantiated with the
/// bridge and reachable via `monitor` right away; `isInstalled` reports whether the pipeline
/// has connected yet.
public final class Monitor<M: CrashMonitor>: MonitorCore, @unchecked Sendable {

    /// Backing storage for `monitor`, set before `init` returns. Not a `let`, because building
    /// the monitor needs `self`, which is unavailable until `super.init()` has returned.
    private var _monitor: M!

    /// The hosted monitor.
    public var monitor: M { _monitor }

    /// The monitor's enabled state, owned by the bridge; monitors only get the
    /// `enabledDidChange` notification, not this flag itself.
    public override var isEnabled: Bool { super.isEnabled }

    /// True once the pipeline has connected (install ran); `host.handle` refuses before then.
    public override var isInstalled: Bool { super.isInstalled }

    /// Hosts `type`, instantiating it immediately with `configuration`.
    public init(_ type: M.Type, _ configuration: M.Configuration) {
        super.init(id: M.id, flags: M.flags, stitchPriority: M.stitchPriority)

        // `super.init` escapes self through api.context; the C side only calls back after
        // registration, which cannot happen before this initializer returns.
        self._monitor = M(host: MonitorHost(bridge: self), configuration: configuration)

        // The bridge outlives the hooks' every invocation; unowned avoids the cycle
        // bridge → hook → bridge.
        enabledChangeHandler = { [unowned self] isEnabled in
            self.monitor.enabledDidChange(isEnabled)
        }
        monitorsDidEnableHandler = { [unowned self] in
            self.monitor.monitorsDidEnable()
        }
        systemDidEnableHandler = { [unowned self] in
            self.monitor.systemDidEnable()
        }
        stitchHandler = { [unowned self] dict, path, scope in
            guard let report = dict as? [String: Any],
                let stitched = try? self.monitor.stitchedReport(
                    report, sidecarURL: path.map { URL(fileURLWithPath: String(cString: $0)) },
                    scope: scope)
            else { return nil }
            return Unmanaged.passRetained(stitched as CFDictionary)
        }
        writeSectionHandler = { [unowned self] eventContext, writerPointer in
            // The crash-time writer fences this callback's output into the monitor's own
            // section (crash.error.monitor_data.<id>, or the schema home of a typed section
            // like profile), so values are written directly; opening another id-named object
            // here would double-nest every section.
            guard let writer = ReportSectionWriter(writerPointer) else { return }
            // callbackContext on this monitor's events belongs to MonitorHost.handle, which
            // only ever puts a PayloadBox there (nil for payload-less events).
            if let raw = eventContext?.pointee.callbackContext {
                guard let payload = Unmanaged<PayloadBox>.fromOpaque(raw).takeUnretainedValue().value as? M.EventPayload
                else { return }
                self.monitor.writeReportSection(payload: payload, writer: writer)
            } else if let unit = () as? M.EventPayload {
                // Payload-less event of a Void-payload monitor: the callback still fires.
                self.monitor.writeReportSection(payload: unit, writer: writer)
            }
        }
    }
}

extension Monitor where M.Configuration == Void {
    /// Hosts a monitor that needs no configuration.
    public convenience init(_ type: M.Type) {
        self.init(type, ())
    }
}
