//
//  ExtensionReporting.swift
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

import Foundation
import KSCrash
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashReportModel

#if canImport(CrashReportExtension)
    import CrashReportExtension
#endif

/// The extension-reporting install's process-wide state: the capture flow reads the area and
/// kcdata options the install ran with.
enum ExtensionReporting {
    struct Active {
        let area: ExtensionConfiguration
        /// This process's install root inside the area.
        let root: URL
        let savesKCData: Bool
        let kcdataDirectory: URL
    }

    static var active: Active?

    /// The monitor bridge the extension process installs and captures through. App-side, the
    /// developer registers `CrashReportExtensionMonitor` through `config.plugins` instead.
    static let bridge = Monitor(CrashReportExtensionMonitor.self)
}

/// Thrown by `installForExtensionReporting(with:)`.
public enum ExtensionReportingInstallError: Error {
    /// The underlying install failed.
    case install(KSCrashInstallError.Code)
}

extension KSCrash {

    /// Install in extension-reporting mode: initializes the report store and the
    /// report-writing pipeline, registers the crash-report-extension monitor, and nothing
    /// else. No crash handlers, no app-lifecycle state, no console log. Call once, from the
    /// extension's init; each corpse is then reported with `captureCrashReport`.
    ///
    /// `area` is the same value the app lists in `SendConfiguration.extensionAreas`; both
    /// sides derive the report area's layout from it identically. Throws the area's own
    /// resolution errors (`InstallError.containerUnavailable` for an unresolvable app group)
    /// and `ExtensionReportingInstallError.install` when the install itself fails.
    ///
    /// ```swift
    /// struct MyCrashReporter: CrashReporterExtension {
    ///     init() {
    ///         let area = ExtensionConfiguration(
    ///             namespace: "MyApp", container: .appGroup("group.com.example.app"))
    ///         try? KSCrash.shared.installForExtensionReporting(with: area)
    ///     }
    ///
    ///     func processCrashReport(process: CrashedProcess) {
    ///         _ = try? KSCrash.shared.captureCrashReport(from: process)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - area: The shared report area to install into.
    ///   - savesKCData: Debugging aid: when true, each capture writes the corpse's raw kcdata
    ///     crash-info blob before parsing it, best effort. Off by default.
    ///   - kcdataDirectory: Where `savesKCData` dumps the blobs; the install root's `KCData`
    ///     directory when nil.
    public func installForExtensionReporting(
        with area: ExtensionConfiguration,
        savesKCData: Bool = false,
        kcdataDirectory: URL? = nil
    ) throws {
        let root = try area.processRoot
        let result = kscrash_installForExtensionReporting(root.path, ExtensionReporting.bridge.api, 1)
        guard result == KSCrashInstallError.Code.none else {
            throw ExtensionReportingInstallError.install(result)
        }
        ExtensionReporting.active = ExtensionReporting.Active(
            area: area,
            root: root,
            savesKCData: savesKCData,
            kcdataDirectory: kcdataDirectory ?? root.appendingPathComponent("KCData", isDirectory: true))
    }
}

#if canImport(CrashReportExtension)

    @available(iOS 27.0, macOS 27.0, *)
    extension KSCrash {

        /// Writes a standard KSCrash crash report for a crashed process, from inside a
        /// CrashReportExtension's `processCrashReport(process:)`. The report lands in the
        /// report area configured by `installForExtensionReporting(with:)`, stamped with the
        /// crashed run's ID when the process embedded KSCrash, and the app picks it up on a
        /// later launch. Returns the new report's ID.
        ///
        /// Each capture keeps the corpse threads' port rights for the process lifetime (by
        /// design for a short-lived extension; see `ksmc_getContextForTaskThread`).
        public func captureCrashReport(from process: CrashedProcess) throws -> Report.ID {
            let images = process.binaryImages.map { image in
                CorpseSnapshot.Image(
                    path: image.path,
                    uuid: image.uuid?.uuidString,
                    baseAddress: image.baseAddress,
                    size: image.size,
                    cpuType: image.cpuType,
                    cpuSubType: image.cpuSubType)
            }
            return try captureCrashReport(
                corpse: process.corpsePort, images: images, exception: process.reason.exception)
        }
    }

#endif
