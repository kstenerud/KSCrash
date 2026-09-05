//
//  CrashReportExtensionMonitor.swift
//
//  Created by Alexander Cohen on 2026-07-04.
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
import KSCrashRecordingCore
import KSCrashReportModel

/// Writes crash reports for other processes' corpses from an iOS 27 CrashReportExtension, and
/// enriches them on the app side at read time.
///
/// In the extension it is registered by `KSCrash.installForExtensionReporting(with:)` and
/// driven by `KSCrash.captureCrashReport`; the report write itself lives in
/// `writeReport(corpse:...)` (Implementation). In the app that ingests the extension's
/// reports, register it like any plugin (`config.plugins =
/// [CrashReportExtensionMonitor.plugin()]`); there it detects nothing and only stitches,
/// replacing run-cached sidecar values with the corpse's at-death data and moving the snapshot
/// out of the error section to the report root (`+Stitch`).
public final class CrashReportExtensionMonitor: CrashMonitor {
    public typealias EventPayload = CorpseSnapshot

    public static let id = "corpse"

    /// Where the snapshot lands in a delivered report: at the root, since it describes the
    /// crashed process rather than the error. The final-pass stitch moves it there.
    static let rootKey = "corpse"

    /// Above every sidecar layer (see KSCrashStitchPriority*): the corpse's at-death data
    /// must replace whatever the run sidecars stitched in.
    public static let stitchPriority = Int(KSCrashStitchPriorityCorpse)

    let host: MonitorHost<CorpseSnapshot>

    public init(host: MonitorHost<CorpseSnapshot>, configuration: Void) {
        self.host = host
    }

    public func writeReportSection(payload: CorpseSnapshot, writer: ReportSectionWriter) {
        try? writer.encode("snapshot", payload.forEmbedding())
    }
}
