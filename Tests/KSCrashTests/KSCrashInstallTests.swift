//
//  KSCrashInstallTests.swift
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
import XCTest

@testable import KSCrash

/// The one place the test process installs KSCrash: the C core installs once
/// per process, so every assertion about the installed state lives here.
final class KSCrashInstallTests: XCTestCase {
    /// A plugin over a minimal C monitor table, to prove registration round-trips.
    private final class TestPlugin: MonitorPlugin, @unchecked Sendable {
        private static let monitorID: UnsafePointer<CChar> = UnsafePointer(strdup("KSCrashInstallTestsPlugin")!)
        let api: UnsafeMutablePointer<KSCrashMonitorAPI>

        init() {
            api = .allocate(capacity: 1)
            api.initialize(to: KSCrashMonitorAPI())
            // The core calls these without a NULL check; the rest may stay NULL.
            api.pointee.`init` = { _, _ in }
            api.pointee.monitorId = { _ in TestPlugin.monitorID }
            api.pointee.monitorFlags = { _ in KSCrashMonitorFlagPlugin }
            api.pointee.setEnabled = { _, _ in }
            api.pointee.isEnabled = { _ in true }
            api.pointee.addContextualInfoToEvent = { _, _ in }
            api.pointee.notifyPostSystemEnable = { _ in }
        }
    }

    private static let plugin = TestPlugin()
    private static let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("KSCrashInstallTests-\(UUID().uuidString)", isDirectory: true)
    private static var configuration: InstallConfiguration = {
        var config = InstallConfiguration(namespace: "Tests")
        config.container = .url(base)
        config.monitors = []
        config.plugins = [plugin]
        return config
    }()
    private static var installError: Error?
    private static let installOnce: Void = {
        do {
            try KSCrash.shared.install(configuration)
        } catch {
            installError = error
        }
    }()

    override func setUpWithError() throws {
        _ = Self.installOnce
        if let error = Self.installError {
            throw error
        }
    }

    func test_installConfiguration_isTheOneInstalledWith() throws {
        let installed = try XCTUnwrap(KSCrash.shared.installConfiguration)
        XCTAssertEqual(installed.namespace, Self.configuration.namespace)
        XCTAssertEqual(installed.container, .url(Self.base))
        XCTAssertEqual(installed.monitors, [])
    }

    func test_install_createsTheStoresAtTheLocations() throws {
        let locations = try Self.configuration.locations
        XCTAssertTrue(locations.root.path.hasPrefix(Self.base.path), "the custom base carries the layout")
        for url in [locations.reports, locations.runs, locations.data] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), url.path)
            XCTAssertTrue(isDirectory.boolValue, url.path)
        }
        XCTAssertTrue(kscrash_isInstalled())
    }

    /// The C install derives its directories and Swift derives its Locations
    /// from the same constants; this pins them to each other.
    func test_locations_matchTheCStoresPaths() throws {
        let locations = try Self.configuration.locations
        XCTAssertEqual(String(cString: kscrash_getReportsPath()), locations.reports.path)
        XCTAssertEqual(String(cString: kscrash_getRunSummariesPath()), locations.runs.path)
        XCTAssertEqual(String(cString: kscrash_getRunSidecarsPath()), locations.runSidecars.path)
        let store = kscrash_getReportStoreConfiguration().pointee
        XCTAssertEqual(String(cString: store.reportSidecarsPath), locations.reportSidecars.path)
    }

    func test_invalidConfiguration_throwsBeforeTouchingAnything() {
        var bad = InstallConfiguration(namespace: "Tests")
        bad.maxReportCount = -1
        XCTAssertThrowsError(try KSCrash.shared.install(bad)) { error in
            guard case .invalidConfiguration? = error as? InstallError else {
                return XCTFail("\(error)")
            }
        }
    }

    func test_secondInstall_throwsAlreadyInstalled() {
        XCTAssertThrowsError(try KSCrash.shared.install(InstallConfiguration(namespace: "Again"))) { error in
            XCTAssertEqual(error as? InstallError, .alreadyInstalled)
        }
    }

    func test_installedPlugin_returnsTheRegisteredOne() {
        XCTAssertTrue(KSCrash.shared.installedPlugin(TestPlugin.self) === Self.plugin)
        XCTAssertNil(KSCrash.shared.installedPlugin(CMonitorPlugin.self))
    }
}
