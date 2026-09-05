//
//  InstallConfiguration.swift
//
//  Created by Alexander Cohen on 2026-08-22.
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

/// Where an install keeps its files.
public enum Container: Sendable, Equatable {
    case applicationSupport
    case caches
    /// The container of an app group; sharing between processes is always explicit.
    case appGroup(String)
    /// A directory of the caller's choosing; the install's layout still applies under it.
    case url(URL)

    /// Application Support, except on tvOS where only Caches is writable.
    public static var `default`: Container {
        #if os(tvOS)
            return .caches
        #else
            return .applicationSupport
        #endif
    }
}

extension Container {
    /// The container's base directory. Throws when an app group does not resolve or a
    /// custom URL is not a file URL.
    var base: URL {
        get throws {
            switch self {
            case .applicationSupport:
                return try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            case .caches:
                return try FileManager.default.url(
                    for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            case .appGroup(let identifier):
                guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
                else {
                    throw InstallError.containerUnavailable(identifier)
                }
                return url
            case .url(let url):
                guard url.isFileURL else {
                    throw InstallError.invalidConfiguration("the container URL must be a file URL: \(url)")
                }
                return url
            }
        }
    }

    /// `<container>/KSCrash/<namespace>/` — the directory whose bundle-id subdirectories are
    /// per-process install roots. The one derivation both the install and an extension area
    /// use, so two processes sharing a container and namespace cannot disagree on the layout.
    func namespaceRoot(for namespace: String) throws -> URL {
        if namespace.isEmpty || namespace == "." || namespace == ".." || namespace.contains("/")
            || namespace.contains("\0")
        {
            throw InstallError.invalidConfiguration("namespace must be a single directory name: \(namespace)")
        }
        return
            try base
            .appendingPathComponent(String(cString: kscrash_namespaceIdentifier()), isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
    }
}

/// Whether memory near the stack and registers is read at crash time.
public enum MemoryIntrospection: Sendable, Equatable {
    case disabled
    /// Instances of the named classes are recorded by class name only.
    case enabled(excludingClasses: [String])
}

/// Everything an install is given. A value: `install` takes a copy, so
/// changing a configuration afterwards changes nothing.
public struct InstallConfiguration: Sendable {
    /// Names the family of processes this install belongs to; never reuse a
    /// namespace across processes that should not share run data.
    public let namespace: String

    public var container: Container = .default
    public var plugins: [any MonitorPlugin] = []
    /// Crash-time callbacks; see `UnsafeCrashTimeCallbacks` for the contract.
    public var unsafeCrashTimeCallbacks: UnsafeCrashTimeCallbacks?

    // Every knob below starts at the C default (`KSCrashCConfiguration_Default`),
    // the one place a default value is written; the doc comments state them.

    /// Default `.default`.
    public var monitors: Monitors
    /// Default 50.
    public var maxReportCount: Int
    /// Default 50.
    public var maxRunSummaryCount: Int
    /// Record each thread's dispatch queue name at crash time. Default false.
    public var searchesQueueNames: Bool
    /// Default `.disabled`.
    public var memoryIntrospection: MemoryIntrospection
    /// Append the KSLOG console log to each report. Default false.
    public var includesConsoleLog: Bool
    /// Print the previous run's console log at install. Default false.
    public var printsPreviousLog: Bool
    /// Catch C++ exceptions by swapping `__cxa_throw`. Default true.
    public var swapsCxaThrow: Bool
    /// Use `backtrace_async` for self-thread captures. Default false.
    public var usesSwiftAsyncStackTraces: Bool
    /// Keep hangs that resolve as non-fatal reports; needs `.hangs`. Default false.
    public var reportsResolvedHangs: Bool
    /// Report sustained CPU usage reaching the warning and critical thresholds. Default false.
    public var reportsCPUExceptions: Bool
    /// Limit `binary_images` to the images backtraces reference. Default false.
    public var compactsBinaryImages: Bool

    public init(namespace: String) {
        self.namespace = namespace
        let defaults = KSCrashCConfiguration_Default()
        monitors = Monitors(rawValue: defaults.monitors.rawValue)
        maxReportCount = Int(defaults.maxReportCount)
        maxRunSummaryCount = Int(defaults.maxRunSummaryCount)
        searchesQueueNames = defaults.enableQueueNameSearch
        memoryIntrospection = defaults.enableMemoryIntrospection ? .enabled(excludingClasses: []) : .disabled
        includesConsoleLog = defaults.addConsoleLogToReport
        printsPreviousLog = defaults.printPreviousLogOnStartup
        swapsCxaThrow = defaults.enableSwapCxaThrow
        usesSwiftAsyncStackTraces = defaults.enableSwiftAsyncStackTraces
        reportsResolvedHangs = defaults.enableHangReporting
        reportsCPUExceptions = defaults.enableCPUExceptionReporting
        compactsBinaryImages = defaults.enableCompactBinaryImages
    }
}

extension InstallConfiguration {
    /// The directories an install uses: `<container>/KSCrash/<namespace>/<bundle id>/`
    /// and the stores inside it.
    public struct Locations: Sendable, Equatable {
        public let root: URL
        public let reports: URL
        public let reportSidecars: URL
        public let runs: URL
        public let runSidecars: URL
        public let data: URL
    }

    /// Where this configuration installs. Throws `InstallError.invalidConfiguration`
    /// for a namespace that cannot be a directory name and
    /// `InstallError.containerUnavailable` when an app group does not resolve.
    public var locations: Locations {
        get throws {
            let bundleID = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            let root = try container.namespaceRoot(for: namespace)
                .appendingPathComponent(bundleID, isDirectory: true)
            // The names are the C store's; the install derives the same directories.
            return Locations(
                root: root,
                reports: root.appendingPathComponent(KSCRS_DEFAULT_REPORTS_FOLDER, isDirectory: true),
                reportSidecars: root.appendingPathComponent(KSCRS_DEFAULT_REPORT_SIDECARS_FOLDER, isDirectory: true),
                runs: root.appendingPathComponent(KSCRS_DEFAULT_RUNS_FOLDER, isDirectory: true),
                runSidecars: root.appendingPathComponent(KSCRS_DEFAULT_RUN_SIDECARS_FOLDER, isDirectory: true),
                data: root.appendingPathComponent(KSCRS_DEFAULT_DATA_FOLDER, isDirectory: true)
            )
        }
    }
}

extension InstallConfiguration {
    /// Everything `install` refuses up front, so a bad configuration fails at the
    /// call site instead of as a missing directory or a dead monitor later.
    func validate() throws {
        // The C configuration carries the counts as Int32; the bridge
        // conversion must never be the place a bad value surfaces.
        if !(0...Int(Int32.max)).contains(maxReportCount) {
            throw InstallError.invalidConfiguration("maxReportCount must be between 0 and \(Int32.max)")
        }
        if !(0...Int(Int32.max)).contains(maxRunSummaryCount) {
            throw InstallError.invalidConfiguration("maxRunSummaryCount must be between 0 and \(Int32.max)")
        }
        if case .enabled(let classes) = memoryIntrospection, classes.contains(where: \.isEmpty) {
            throw InstallError.invalidConfiguration("memoryIntrospection excludes an empty class name")
        }
        if plugins.count > Int(KSC_MAX_PLUGINS) {
            throw InstallError.invalidConfiguration("at most \(KSC_MAX_PLUGINS) plugins can be registered")
        }
        var monitorIDs = Set<String>()
        for plugin in plugins {
            let api = plugin.api.pointee
            // The one list of callbacks the core invokes without a NULL
            // check. The registry's registration asserts vanish in release,
            // so this throw is the release-mode enforcement.
            guard kscma_hasRequiredCallbacks(plugin.api), let monitorId = api.monitorId else {
                throw InstallError.invalidConfiguration("a plugin's monitor table is missing a required entry")
            }
            guard let idPointer = monitorId(api.context) else {
                throw InstallError.invalidConfiguration("a plugin's monitor table has no monitor id")
            }
            let id = String(cString: idPointer)
            if id.isEmpty || !monitorIDs.insert(id).inserted {
                throw InstallError.invalidConfiguration("plugin monitor ids must be non-empty and unique: \(id)")
            }
            if id == KSCRASH_MONITOR_ID_UNSET {
                throw InstallError.invalidConfiguration("a plugin's monitor table must set a real monitor id")
            }
            if kscrash_isBuiltInMonitorID(id) {
                throw InstallError.invalidConfiguration("plugin monitor id collides with a built-in monitor: \(id)")
            }
        }
    }

}
