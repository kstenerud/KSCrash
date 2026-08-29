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

/// The boot monitor: records the system's boot time on reports.
public enum BootMonitor {
    /// Register in `InstallConfiguration.plugins`. Boot time is constant for
    /// a run, so it is recorded once when the monitor is enabled.
    public static func plugin() -> any MonitorPlugin {
        SidecarMetadataMonitorPlugin(
            monitorID: "BootTime",
            record: { store in
                var value = timeval()
                var size = MemoryLayout<timeval>.size
                guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0, value.tv_sec > 0 else { return }
                store[bootTimeKey] = UInt64(value.tv_sec)
                // Termination classification compares boot time across runs;
                // the plugin's enable runs before RunContext reads it.
                kscm_system_setBootTime(Int64(value.tv_sec))
            },
            poller: nil,
            stitch: { values, system in
                // A torn sidecar can hold any bytes; an unconvertible value is
                // absence, never a trap.
                guard let seconds: UInt64 = values[bootTimeKey], let timestamp = time_t(exactly: seconds) else {
                    return
                }
                // The same wall-clock string the system stitch writes for boot_time.
                var buffer = [CChar](repeating: 0, count: Int(KSDATE_BUFFERSIZE))
                ksdate_utcStringFromTimestamp(timestamp, &buffer, buffer.count)
                system[CrashField.bootTime.rawValue] = String(cString: buffer)
            })
    }
}

/// Reserved store key; the stitch maps it to the report's boot_time field.
private let bootTimeKey = "com.kscrash.boot.time"
