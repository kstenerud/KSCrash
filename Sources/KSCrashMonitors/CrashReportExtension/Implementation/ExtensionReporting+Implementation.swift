//
//  ExtensionReporting+Implementation.swift
//
//  Created by Alexander Cohen on 2026-07-05.
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
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashReportModel

extension ExtensionReporting {

    /// The debug dump for `savesKCData`: writes the raw blob to
    /// `<kcdataDirectory>/<processName>-<pid>-<timestamp>.kcdata`, best effort. Returns nil
    /// when disabled so the gatherer skips the work entirely.
    static func kcdataSaver() -> ((Data, CorpseSnapshot.CrashInfo?) -> Void)? {
        guard let configuration = activeConfiguration, configuration.savesKCData,
            let directory = configuration.kcdataDirectory
        else { return nil }
        return { data, crashInfo in
            let name = [
                crashInfo?.processName ?? "unknown",
                String(crashInfo?.pid ?? 0),
                String(UInt64(Date().timeIntervalSince1970 * 1000)),
            ].joined(separator: "-")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent(name + ".kcdata"))
        }
    }
}

extension ExtensionReporting {

    /// The full capture flow from raw corpse inputs: load the crashed run's ID out of the
    /// corpse (best effort), gather the snapshot, and write the report. The kcdata gather
    /// requires a genuine corpse, so this path is validated against one, not in-process.
    static func captureCrashReport(corpse: mach_port_t, images: [CorpseSnapshot.Image], exception: Int32) throws
        -> Report.ID
    {
        // Load-or-clear, best effort: the run id is per-corpse state, so clear the previous
        // capture's before loading this corpse's. A corpse whose id cannot be read (an app
        // without KSCrash, or one that crashed before install wrote the id) is reported with
        // no run id, which only costs the stitch against the crashed run's sidecars.
        kscrash_clearRunID()
        var imageAddresses = images.map { $0.baseAddress }
        _ = kscrash_loadRunIDFromCorpse(corpse, &imageAddresses, UInt32(imageAddresses.count))

        let snapshot = CorpseGatherer.gather(
            corpse: corpse, exception: exception, images: images,
            saveKCData: ExtensionReporting.kcdataSaver())
        return try captureCrashReport(snapshot: snapshot, corpse: corpse)
    }

    /// The capture core, orchestrating an already-gathered snapshot: the crash facts come
    /// from the snapshot's kcdata, the snapshot itself is embedded in the report by the
    /// monitor's report-section writer, and the report goes through the standard pipeline.
    static func captureCrashReport(snapshot: CorpseSnapshot, corpse: mach_port_t) throws -> Report.ID {
        // Without kcdata there is no crashed thread to unwind; a report without the crash's
        // own thread would be misleading rather than helpful.
        guard let crashInfo = snapshot.crashInfo, let crashedThreadID = crashInfo.crashedThreadID,
            let exception = snapshot.exception ?? crashInfo.machException
        else {
            throw CrashReportExtensionMonitor.CaptureFailure()
        }

        // The monitor exists immediately, but it is only connected to the pipeline once
        // installForExtensionReporting has run.
        let bridge = ExtensionReporting.bridge
        guard bridge.isInstalled else {
            throw CrashReportExtensionMonitor.CaptureFailure()
        }
        return try bridge.monitor.writeReport(
            corpse: corpse,
            crashedThreadID: crashedThreadID,
            images: snapshot.images,
            exception: exception.rawValue,
            code: crashInfo.machCode(for: exception),
            subcode: crashInfo.exceptionSubcode,
            signal: crashInfo.signal?.rawValue,
            processName: crashInfo.processName,
            snapshot: snapshot)
    }
}
