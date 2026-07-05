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
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashReportModel

#if canImport(CrashReportExtension)
    import CrashReportExtension
#endif

/// Configuration for an extension-reporting install: a process that writes crash
/// reports about other processes and detects no crashes of its own.
///
/// The reports land in this process's own report area, typically inside an App Group
/// container so the app can read them on a later launch:
///
/// ```swift
/// struct MyCrashReporter: CrashReporterExtension {
///     init() {
///         let config = ExtensionReportingConfiguration(
///             appName: "MyApp", appGroupIdentifier: "group.com.example.app")
///         try? KSCrash.shared.installForExtensionReporting(with: config)
///     }
///
///     func processCrashReport(process: CrashedProcess) {
///         _ = try? KSCrash.shared.captureCrashReport(from: process)
///     }
/// }
/// ```
public struct ExtensionReportingConfiguration {

    /// The app's name, exactly as the app's own install uses it. Report filenames embed it
    /// and the app's store scans by it; a mismatched name writes reports the app never finds.
    public let appName: String

    /// The App Group whose container holds this process's report area
    /// (`<container>/<namespace>`, where the namespace is "KSCrash" for a stock build and
    /// the namespaced identifier otherwise, so two KSCrash copies sharing one App Group
    /// cannot collide). The app reads reports from the same area later.
    public let appGroupIdentifier: String

    /// Debugging aid: when true, each capture writes the corpse's raw kcdata crash-info blob
    /// to `kcdataDirectory` before parsing it, best effort (a failed write never blocks the
    /// capture). Off by default.
    public var savesKCData: Bool = false

    /// Test seam: replaces the App Group container resolution with an explicit root.
    var installPathOverride: String?

    public init(appName: String, appGroupIdentifier: String) {
        self.appName = appName
        self.appGroupIdentifier = appGroupIdentifier
    }

    /// The directory the reports land in, or `nil` when the App Group container
    /// cannot be resolved (e.g. a missing entitlement).
    public var reportsDirectory: URL? {
        installRoot?.appendingPathComponent("Reports")
    }

    /// The directory `savesKCData` dumps raw kcdata blobs into (one
    /// `<processName>-<pid>-<timestamp>.kcdata` file per capture), or `nil` when the App Group
    /// container cannot be resolved.
    public var kcdataDirectory: URL? {
        installRoot?.appendingPathComponent("KCData")
    }

    var installRoot: URL? {
        if let override = installPathOverride {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(String(cString: kscrash_namespaceIdentifier()))
    }
}

/// The extension-reporting install's process-wide state: the capture flow reads settings
/// (e.g. `savesKCData`) off the configuration the install ran with.
enum ExtensionReporting {
    static var activeConfiguration: ExtensionReportingConfiguration?

    /// The monitor bridge the extension process installs and captures through. App-side, the
    /// developer registers `CrashReportExtensionMonitor` through `config.plugins` instead.
    static let bridge = Monitor(CrashReportExtensionMonitor.self)
}

/// Thrown by `install(with:)`.
public enum ExtensionReportingInstallError: Error {
    /// The App Group container could not be resolved from the configuration
    /// (e.g. a missing entitlement), so there is no report area to install into.
    case reportAreaUnresolved
    /// The underlying install failed.
    case install(KSCrashInstallError.Code)
}

extension ExtensionReporting {

    /// Install in extension-reporting mode: initializes the report store and the
    /// report-writing pipeline, registers the crash-report-extension monitor, and nothing
    /// else. No crash handlers, no app-lifecycle state, no console log. Call once, from the
    /// extension's init; each corpse is then reported with `captureCrashReport`.
    public static func install(with configuration: ExtensionReportingConfiguration) throws {
        guard let installRoot = configuration.installRoot else {
            throw ExtensionReportingInstallError.reportAreaUnresolved
        }
        let result = kscrash_installForExtensionReporting(installRoot.path, ExtensionReporting.bridge.api, 1)
        guard result == KSCrashInstallError.Code.none else {
            throw ExtensionReportingInstallError.install(result)
        }
        ExtensionReporting.activeConfiguration = configuration
    }
}

#if canImport(CrashReportExtension)

    @available(iOS 27.0, macOS 27.0, *)
    extension ExtensionReporting {

        /// Writes a standard KSCrash crash report for a crashed process, from inside a
        /// CrashReportExtension's `processCrashReport(process:)`. The report lands in the
        /// report area configured by `install(with:)`, stamped with the
        /// crashed run's ID when the process embedded KSCrash, and the app picks it up on a
        /// later launch. Returns the new report's ID.
        ///
        /// Each capture keeps the corpse threads' port rights for the process lifetime (by
        /// design for a short-lived extension; see `ksmc_getContextForTaskThread`).
        public static func captureCrashReport(from process: CrashedProcess) throws -> Report.ID {
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
