//
//  BootMonitor.swift
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
import KSCrashRecordingCore
import KSCrashSwiftCore

/// The boot monitor: records the system's boot time on reports.
public enum BootMonitor {
    /// Register in `InstallConfiguration.plugins`. Boot time is constant for
    /// a run and is recorded through the System sidecar, the report's one
    /// source for `system.boot_time`.
    public static func plugin() -> any MonitorPlugin { BootMonitorPlugin() }
}

final class BootMonitorPlugin: MonitorPlugin, @unchecked Sendable {
    private static let monitorID: UnsafePointer<CChar> = UnsafePointer(strdup("BootTime")!)
    let api: UnsafeMutablePointer<KSCrashMonitorAPI>
    private let enabled = AtomicFlag()

    init() {
        api = .allocate(capacity: 1)
        api.initialize(to: KSCrashMonitorAPI())
        // Fill every slot with the core's defaults; the core calls slots
        // without NULL checks.
        kscma_initAPI(api)
        api.pointee.monitorId = { _ in BootMonitorPlugin.monitorID }
        api.pointee.monitorFlags = { _ in MonitorFlags.plugin }
        api.pointee.setEnabled = { enabled, context in
            context.map { BootMonitorPlugin.from($0).enabled.value = enabled }
        }
        api.pointee.isEnabled = { context in
            context.map { BootMonitorPlugin.from($0).enabled.value } ?? false
        }
        // Step 2 of the install sequence, before RunContext init: reboot
        // detection compares this run's boot time against the previous run's.
        api.pointee.notifyPostMonitorsEnabled = { _ in
            let value = kssysctl_timevalForName("kern.boottime")
            if value.tv_sec > 0 {
                kscm_system_setBootTime(Int64(value.tv_sec))
            }
        }
        api.pointee.context = Unmanaged.passUnretained(self).toOpaque()
    }

    deinit {
        api.deinitialize(count: 1)
        api.deallocate()
    }

    private static func from(_ context: UnsafeMutableRawPointer) -> BootMonitorPlugin {
        Unmanaged<BootMonitorPlugin>.fromOpaque(context).takeUnretainedValue()
    }
}
