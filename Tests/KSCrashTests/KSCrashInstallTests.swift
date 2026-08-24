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
    override func setUpWithError() throws {
        try TestInstall.ensure()
    }

    func test_installConfiguration_isTheOneInstalledWith() throws {
        let installed = try XCTUnwrap(KSCrash.shared.installConfiguration)
        XCTAssertEqual(installed.namespace, TestInstall.configuration.namespace)
        XCTAssertEqual(installed.container, .url(TestInstall.base))
        XCTAssertEqual(installed.monitors, [.hangs])
    }

    func test_install_createsTheStoresAtTheLocations() throws {
        let locations = try TestInstall.configuration.locations
        XCTAssertTrue(locations.root.path.hasPrefix(TestInstall.base.path), "the custom base carries the layout")
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
        let locations = try TestInstall.configuration.locations
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
        XCTAssertTrue(KSCrash.shared.installedPlugin(TestInstall.Plugin.self) === TestInstall.plugin)
        XCTAssertNil(KSCrash.shared.installedPlugin(CMonitorPlugin.self))
    }
}
