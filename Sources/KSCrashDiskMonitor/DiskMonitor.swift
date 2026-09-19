//
//  DiskMonitor.swift
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
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashSwiftCore

/// The disk monitor: records total and free storage on reports.
public enum DiskMonitor {
    /// Register in `InstallConfiguration.plugins`. Storage sizes are recorded
    /// when the monitor is enabled and re-sampled periodically, and free
    /// storage is refreshed at event time so a report carries the value from
    /// its own moment.
    public static func plugin() -> any MonitorPlugin { DiskMonitorPlugin() }
}

private final class DiskMonitorPlugin: MonitorPlugin, @unchecked Sendable {
    private static let monitorID: UnsafePointer<CChar> = UnsafePointer(strdup("DiscSpace")!)

    let api: UnsafeMutablePointer<KSCrashMonitorAPI>

    private struct State {
        var poller: Poller?
    }
    private let state = UnfairLock(State())

    /// Read by the `isEnabled` slot on the crash path, possibly with every
    /// other thread suspended: a lock-free flag, never the state lock.
    private let enabled = AtomicFlag()

    init() {
        api = .allocate(capacity: 1)
        api.initialize(to: KSCrashMonitorAPI())
        // Fill every slot with the core's defaults first; the core calls
        // slots without NULL checks.
        kscma_initAPI(api)
        api.pointee.monitorId = { _ in DiskMonitorPlugin.monitorID }
        api.pointee.monitorFlags = { _ in MonitorFlags.plugin }
        api.pointee.setEnabled = { enabled, context in
            context.map { DiskMonitorPlugin.from($0).setEnabled(enabled) }
        }
        api.pointee.isEnabled = { context in
            context.map { DiskMonitorPlugin.from($0).enabled.value } ?? false
        }
        // A C function, not a Swift closure: it runs on the event path,
        // where Swift must not.
        api.pointee.addContextualInfoToEvent = kscm_system_refreshFreeStorageAtEvent
        api.pointee.context = Unmanaged.passUnretained(self).toOpaque()
    }

    deinit {
        api.deinitialize(count: 1)
        api.deallocate()
    }

    private static func from(_ context: UnsafeMutableRawPointer) -> DiskMonitorPlugin {
        Unmanaged<DiskMonitorPlugin>.fromOpaque(context).takeUnretainedValue()
    }

    private func setEnabled(_ enabled: Bool) {
        state.withLock { state in
            guard enabled != self.enabled.value else { return }
            self.enabled.value = enabled
            if enabled {
                Self.record()
                // The guard covers a fire already in flight when the poller
                // is stopped on disable.
                let poller = Poller(every: 60, queue: DispatchQueue(label: "com.kscrash.diskmonitor", qos: .utility)) {
                    [weak self] in
                    guard let self, self.enabled.value else { return }
                    Self.record()
                }
                poller?.start()
                state.poller = poller
            } else {
                state.poller?.stop()
                state.poller = nil
            }
        }
    }

    private static func record() {
        var status = Darwin.statfs()
        guard statfs("/", &status) == 0 else { return }
        kscm_system_setDiscSpace(
            UInt64(status.f_blocks) * UInt64(status.f_bsize),
            UInt64(status.f_bfree) * UInt64(status.f_bsize))
    }
}
