//
//  SidecarMetadataMonitorPlugin.swift
//
//  Created by Alexander Cohen on 2025-12-14.
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
import KSCrashReportModel
import KSCrashSwiftCore
import os

/// A monitor that records metadata into its own run sidecar while enabled and
/// stitches it into the report's system section at delivery. Nothing runs at
/// crash time; the sidecar on disk is the record.
public final class SidecarMetadataMonitorPlugin: MonitorPlugin, @unchecked Sendable {
    public let api: UnsafeMutablePointer<KSCrashMonitorAPI>

    private struct State {
        var sidecarPathProvider: KSCrashSidecarRunPathProviderFunc?
        var store: SidecarMetadata?
        var poller: Poller?
    }

    private let monitorID: UnsafePointer<CChar>
    private let record: @Sendable (SidecarMetadata) -> Void
    private let makePoller: (@Sendable (@escaping @Sendable () -> Void) -> Poller?)?
    private let stitch: @Sendable (any MetadataStore, NSMutableDictionary) -> Void
    private let state = UnfairLock(State())

    /// Read by the `isEnabled` slot on the crash path, possibly with every
    /// other thread suspended: a lock-free flag, never the state lock.
    private let enabled = AtomicFlag()

    /// `record` writes the current values into the store; `poller` (when set)
    /// repeats it while enabled; `stitch` merges the sidecar's values into the
    /// report's system section at delivery.
    public init(
        monitorID: String,
        record: @escaping @Sendable (SidecarMetadata) -> Void,
        poller: (@Sendable (@escaping @Sendable () -> Void) -> Poller?)?,
        stitch: @escaping @Sendable (any MetadataStore, NSMutableDictionary) -> Void
    ) {
        self.monitorID = UnsafePointer(strdup(monitorID)!)
        self.record = record
        self.makePoller = poller
        self.stitch = stitch
        api = .allocate(capacity: 1)
        api.initialize(to: KSCrashMonitorAPI())
        // Fill every slot with the core's defaults first; the core calls
        // slots without NULL checks.
        kscma_initAPI(api)
        api.pointee.`init` = { callbacks, context in
            guard let callbacks, let context else { return }
            // Copy the one provider used; the callbacks struct is the core's.
            SidecarMetadataMonitorPlugin.from(context).state.withLock {
                $0.sidecarPathProvider = callbacks.pointee.getRunSidecarPath
            }
        }
        api.pointee.monitorId = { context in
            context.map { SidecarMetadataMonitorPlugin.from($0).monitorID }
        }
        // Plugins never count toward the registry's any-monitor-active
        // gate: install success must not hinge on a plugin enabling.
        api.pointee.monitorFlags = { _ in .plugin }
        api.pointee.setEnabled = { enabled, context in
            context.map { SidecarMetadataMonitorPlugin.from($0).setEnabled(enabled) }
        }
        api.pointee.isEnabled = { context in
            context.map { SidecarMetadataMonitorPlugin.from($0).enabled.value } ?? false
        }
        api.pointee.createStitchedReport = { reportDict, sidecarPath, scope, context in
            guard let reportDict, let context else { return nil }
            return SidecarMetadataMonitorPlugin.from(context)
                .stitched(reportDict, sidecarPath: sidecarPath, scope: scope)
        }
        api.pointee.context = Unmanaged.passUnretained(self).toOpaque()
    }

    deinit {
        api.deinitialize(count: 1)
        api.deallocate()
        free(UnsafeMutablePointer(mutating: monitorID))
    }

    private static func from(_ context: UnsafeMutableRawPointer) -> SidecarMetadataMonitorPlugin {
        Unmanaged<SidecarMetadataMonitorPlugin>.fromOpaque(context).takeUnretainedValue()
    }

    private func setEnabled(_ enabled: Bool) {
        state.withLock { state in
            guard enabled != self.enabled.value else { return }
            if !enabled {
                state.poller?.stop()
                state.poller = nil
                state.store = nil
                self.enabled.value = false
                return
            }
            guard let provider = state.sidecarPathProvider else {
                os_log(.error, "%{public}@ cannot enable: no run sidecar path provider", String(cString: monitorID))
                return
            }
            var path = [CChar](repeating: 0, count: Int(KSFU_MAX_PATH_LENGTH))
            guard provider(monitorID, &path, path.count) else {
                os_log(.error, "%{public}@ cannot enable: no run sidecar path", String(cString: monitorID))
                return
            }
            let config = KSKVSConfig(initialCapacity: 512)
            let store: SidecarMetadata
            do {
                store = try SidecarMetadata.creating(at: String(cString: path), config: config)
            } catch {
                os_log(
                    .error, "%{public}@ cannot enable: sidecar store failed to open: %{public}@",
                    String(cString: monitorID), String(describing: error))
                return
            }
            state.store = store
            self.enabled.value = true
            record(store)
            if let makePoller {
                if let poller = makePoller({ [weak self] in self?.recordCurrent() }) {
                    poller.start()
                    state.poller = poller
                } else {
                    // The enable-time sample above still stands; it just never refreshes.
                    os_log(
                        .error, "%{public}@: no poller; recorded once at enable, never re-sampled",
                        String(cString: monitorID))
                }
            }
        }
    }

    private func recordCurrent() {
        state.withLock { state in
            guard enabled.value, let store = state.store else { return }
            record(store)
        }
    }

    private func stitched(
        _ reportDict: CFDictionary, sidecarPath: UnsafePointer<CChar>?, scope: SidecarScope
    ) -> Unmanaged<CFDictionary>? {
        guard scope == SidecarScope.run, let sidecarPath else {
            return .passRetained(reportDict)
        }
        guard let values = SidecarMetadata.reading(at: String(cString: sidecarPath)) else {
            // A missing or torn sidecar holds nothing recoverable; deliver as is.
            return .passRetained(reportDict)
        }
        let report = (reportDict as NSDictionary).mutableCopy() as! NSMutableDictionary
        let system =
            (report[CrashField.system.rawValue] as? NSDictionary).map { $0.mutableCopy() as! NSMutableDictionary }
            ?? NSMutableDictionary()
        stitch(values, system)
        report[CrashField.system.rawValue] = system
        return .passRetained(report as CFDictionary)
    }
}
