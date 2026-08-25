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
    /// Register in `InstallConfiguration.plugins`. Free storage is sampled
    /// when the monitor is enabled and re-sampled every `pollInterval`
    /// seconds, so a report carries the value from the latest poll.
    public static func plugin(pollInterval: TimeInterval = 60) -> any MonitorPlugin {
        SidecarMetadataMonitorPlugin(
            monitorID: "DiscSpace",
            record: { store in
                var status = Darwin.statfs()
                guard statfs("/", &status) == 0 else { return }
                store[Keys.storage] = UInt64(status.f_blocks) * UInt64(status.f_bsize)
                store[Keys.freeStorage] = UInt64(status.f_bfree) * UInt64(status.f_bsize)
            },
            poller: { record in
                Poller(every: pollInterval, queue: DispatchQueue(label: "com.kscrash.diskmonitor", qos: .utility)) {
                    record()
                }
            },
            stitch: { values, system in
                if let storage: UInt64 = values[Keys.storage] {
                    system[CrashField.storage.rawValue] = NSNumber(value: storage)
                }
                if let free: UInt64 = values[Keys.freeStorage] {
                    system[CrashField.freeStorage.rawValue] = NSNumber(value: free)
                }
            })
    }

    /// Reserved store keys; the stitch maps them to the report's field names.
    private enum Keys {
        static let storage = "com.kscrash.disk.storage"
        static let freeStorage = "com.kscrash.disk.freeStorage"
    }
}
