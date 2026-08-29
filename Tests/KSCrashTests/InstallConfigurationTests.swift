//
//  InstallConfigurationTests.swift
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
import KSCrashRecording
import XCTest

@testable import KSCrash

final class InstallConfigurationTests: XCTestCase {
    func test_defaults() {
        let config = InstallConfiguration(namespace: "T")
        XCTAssertEqual(config.namespace, "T")
        XCTAssertEqual(config.monitors, .default)
        XCTAssertTrue(config.plugins.isEmpty)
        XCTAssertEqual(config.maxReportCount, 50)
        XCTAssertEqual(config.maxRunSummaryCount, 50)
        XCTAssertFalse(config.searchesQueueNames)
        XCTAssertEqual(config.memoryIntrospection, .disabled)
        XCTAssertFalse(config.includesConsoleLog)
        XCTAssertFalse(config.printsPreviousLog)
        XCTAssertTrue(config.swapsCxaThrow)
        XCTAssertFalse(config.usesSwiftAsyncStackTraces)
        XCTAssertFalse(config.reportsResolvedHangs)
        XCTAssertFalse(config.reportsCPUExceptions)
        XCTAssertFalse(config.compactsBinaryImages)
        XCTAssertNil(config.unsafeCrashTimeCallbacks)
        #if os(tvOS)
            XCTAssertEqual(config.container, .caches)
        #else
            XCTAssertEqual(config.container, .applicationSupport)
        #endif
        XCTAssertEqual(config.container, Container.default)
    }

    func test_locations_layout() throws {
        let locations = try InstallConfiguration(namespace: "Ns").locations
        let bundleID = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        XCTAssertEqual(locations.root.lastPathComponent, bundleID)
        XCTAssertEqual(locations.root.deletingLastPathComponent().lastPathComponent, "Ns")
        XCTAssertEqual(
            locations.root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,
            String(cString: kscrash_namespaceIdentifier()))
        // The names are the C store's constants, the same ones the C install uses.
        XCTAssertEqual(
            locations.reports, locations.root.appendingPathComponent(KSCRS_DEFAULT_REPORTS_FOLDER, isDirectory: true))
        XCTAssertEqual(
            locations.reportSidecars,
            locations.root.appendingPathComponent(KSCRS_DEFAULT_REPORT_SIDECARS_FOLDER, isDirectory: true))
        XCTAssertEqual(
            locations.runs, locations.root.appendingPathComponent(KSCRS_DEFAULT_RUNS_FOLDER, isDirectory: true))
        XCTAssertEqual(
            locations.runSidecars,
            locations.root.appendingPathComponent(KSCRS_DEFAULT_RUN_SIDECARS_FOLDER, isDirectory: true))
        XCTAssertEqual(
            locations.data, locations.root.appendingPathComponent(KSCRS_DEFAULT_DATA_FOLDER, isDirectory: true))
    }

    func test_locations_followTheContainer() throws {
        var config = InstallConfiguration(namespace: "Ns")
        config.container = .caches
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        XCTAssertTrue(try config.locations.root.path.hasPrefix(caches.path))
        config.container = .applicationSupport
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        XCTAssertTrue(try config.locations.root.path.hasPrefix(support.path))
    }

    func test_locations_throwForAnUnavailableAppGroup() throws {
        #if os(macOS) || targetEnvironment(simulator) || targetEnvironment(macCatalyst)
            // An unsandboxed macOS process, every simulator, and Mac Catalyst
            // are handed a container URL for any group id.
            throw XCTSkip("app group containers always resolve outside a device sandbox")
        #endif
        var config = InstallConfiguration(namespace: "Ns")
        config.container = .appGroup("group.does.not.exist.kscrash")
        XCTAssertThrowsError(try config.locations) { error in
            XCTAssertEqual(error as? InstallError, .containerUnavailable("group.does.not.exist.kscrash"))
        }
    }

    func test_urlContainer_mustBeAFileURL() throws {
        var config = InstallConfiguration(namespace: "Ns")
        config.container = .url(URL(string: "https://example.com/path")!)
        XCTAssertThrowsError(try config.locations) { error in
            guard case .invalidConfiguration? = error as? InstallError else { return XCTFail("\(error)") }
        }
        config.container = .url(URL(fileURLWithPath: "/tmp/kscrash-test"))
        XCTAssertNoThrow(try config.locations)
    }

    func test_namespace_mustBeADirectoryName() {
        for bad in ["", "/", "a/b", ".", ".."] {
            XCTAssertThrowsError(try InstallConfiguration(namespace: bad).locations, bad) { error in
                guard case .invalidConfiguration? = error as? InstallError else { return XCTFail("\(error)") }
            }
        }
        XCTAssertNoThrow(try InstallConfiguration(namespace: "My App.1").locations)
    }

    /// A minimal valid plugin table with its own id, for count tests.
    private final class CountedPlugin: MonitorPlugin, @unchecked Sendable {
        private let monitorID: UnsafePointer<CChar>
        let api: UnsafeMutablePointer<KSCrashMonitorAPI>

        init(_ index: Int) {
            monitorID = UnsafePointer(strdup("CountedPlugin\(index)")!)
            api = .allocate(capacity: 1)
            api.initialize(to: KSCrashMonitorAPI())
            // The production pattern: defaults for every slot first.
            kscma_initAPI(api)
            api.pointee.monitorFlags = { _ in KSCrashMonitorFlagPlugin }
            let id = monitorID
            api.pointee.context = UnsafeMutableRawPointer(mutating: id)
            api.pointee.monitorId = { context in
                context.map { UnsafePointer($0.assumingMemoryBound(to: CChar.self)) }
            }
        }
    }

    func test_validate_requiresEveryCallbackTheCoreInvokes() {
        var config = InstallConfiguration(namespace: "Ns")
        let plugin = CountedPlugin(0)
        plugin.api.pointee.notifyPostSystemEnable = nil
        config.plugins = [plugin]
        XCTAssertThrowsError(try config.validate(), "a hole the core would call must fail validation") { error in
            guard case .invalidConfiguration? = error as? InstallError else { return XCTFail("\(error)") }
        }
        plugin.api.pointee.notifyPostSystemEnable = { _ in }
        plugin.api.pointee.addContextualInfoToEvent = nil
        XCTAssertThrowsError(try config.validate())
    }

    func test_validate_boundsThePluginCount() {
        var config = InstallConfiguration(namespace: "Ns")
        config.plugins = (0..<Int(KSC_MAX_PLUGINS)).map(CountedPlugin.init)
        XCTAssertNoThrow(try config.validate())
        config.plugins.append(CountedPlugin(Int(KSC_MAX_PLUGINS)))
        XCTAssertThrowsError(try config.validate()) { error in
            guard case .invalidConfiguration? = error as? InstallError else { return XCTFail("\(error)") }
        }
    }

    func test_validate_refusesNegativeCountsAndEmptyClassNames() {
        var config = InstallConfiguration(namespace: "Ns")
        XCTAssertNoThrow(try config.validate())
        config.maxRunSummaryCount = -1
        XCTAssertThrowsError(try config.validate())
        config.maxRunSummaryCount = Int(Int32.max) + 1
        XCTAssertThrowsError(try config.validate(), "counts past Int32 must throw, not trap in the bridge")
        config.maxRunSummaryCount = 0
        config.maxReportCount = Int(Int32.max) + 1
        XCTAssertThrowsError(try config.validate())
        config.maxReportCount = 0
        config.maxRunSummaryCount = 0
        config.memoryIntrospection = .enabled(excludingClasses: [""])
        XCTAssertThrowsError(try config.validate())
    }

    func test_locations_underACustomBase() throws {
        var config = InstallConfiguration(namespace: "Ns")
        let base = URL(fileURLWithPath: "/tmp/custom", isDirectory: true)
        config.container = .url(base)
        let locations = try config.locations
        XCTAssertTrue(locations.root.path.hasPrefix(base.path))
        XCTAssertEqual(locations.root.deletingLastPathComponent().lastPathComponent, "Ns")
    }

    /// A default Swift configuration bridges to exactly the C default, field by
    /// field: a knob added on one side without the other shows up here.
    func test_bridge_roundTripsTheCDefaults() {
        var bridged = InstallConfiguration(namespace: "Ns").makeCConfiguration()
        defer { KSCrashCConfiguration_Release(&bridged) }
        let c = KSCrashCConfiguration_Default()
        XCTAssertEqual(bridged.maxReportCount, c.maxReportCount)
        XCTAssertEqual(bridged.maxRunSummaryCount, c.maxRunSummaryCount)
        XCTAssertEqual(bridged.monitors, c.monitors)
        XCTAssertEqual(bridged.enableQueueNameSearch, c.enableQueueNameSearch)
        XCTAssertEqual(bridged.enableMemoryIntrospection, c.enableMemoryIntrospection)
        XCTAssertEqual(bridged.doNotIntrospectClasses.length, c.doNotIntrospectClasses.length)
        XCTAssertEqual(bridged.addConsoleLogToReport, c.addConsoleLogToReport)
        XCTAssertEqual(bridged.printPreviousLogOnStartup, c.printPreviousLogOnStartup)
        XCTAssertEqual(bridged.enableSwapCxaThrow, c.enableSwapCxaThrow)
        XCTAssertEqual(bridged.enableSwiftAsyncStackTraces, c.enableSwiftAsyncStackTraces)
        XCTAssertEqual(bridged.enableHangReporting, c.enableHangReporting)
        XCTAssertEqual(bridged.enableCPUExceptionReporting, c.enableCPUExceptionReporting)
        XCTAssertEqual(bridged.enableCompactBinaryImages, c.enableCompactBinaryImages)
        XCTAssertEqual(bridged.plugins.length, c.plugins.length)
        XCTAssertNil(bridged.willWriteReportCallback)
        XCTAssertNil(bridged.isWritingReportCallback)
        XCTAssertNil(bridged.didWriteReportCallback)
    }

    func test_isAValue() {
        let original = InstallConfiguration(namespace: "Ns")
        var copy = original
        copy.maxReportCount = 1
        XCTAssertEqual(original.maxReportCount, 50)
    }
}
