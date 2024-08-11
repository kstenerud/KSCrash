//
//  IntegrationTestBase.swift
//
//  Created by Nikolay Volosatov on 2024-08-03.
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

import XCTest
import SampleUI
import CrashTriggers
import Logging
import IntegrationTestsHelper

class IntegrationTestBase: XCTestCase {

    private(set) var log: Logger!
    private(set) var app: XCUIApplication!

    private(set) var installUrl: URL!
    private(set) var appleReportsUrl: URL!

    var appLaunchTimeout: TimeInterval = 10.0
    var appTerminateTimeout: TimeInterval = 5.0
    var appCrashTimeout: TimeInterval = 10.0

    var screenLoadingTimeout: TimeInterval = 1.0
    var reportTimeout: TimeInterval = 5.0

    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = true

        log = Logger(label: name)
        installUrl = FileManager.default.temporaryDirectory
            .appending(component: "KSCrash")
            .appending(component: UUID().uuidString)
        appleReportsUrl = installUrl.appending(component: "__TEST_REPORTS__")

        try FileManager.default.createDirectory(at: appleReportsUrl, withIntermediateDirectories: true)
        log.info("KSCrash install path: \(installUrl.path())")

        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        app.terminate()
        _ = app.wait(for: .notRunning, timeout: appTerminateTimeout)

        if let files = FileManager.default.enumerator(atPath: installUrl.path()) {
            log.info("Remaining KSCrash files:")
            for file in files {
                log.info("\t\(file)")
            }
        }

        try? FileManager.default.removeItem(at: installUrl)
    }

    func launchAppAndRunScript() {
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: appLaunchTimeout))
    }

    func waitForCrash() {
        XCTAssert(app.wait(for: .notRunning, timeout: appCrashTimeout), "App crash is expected")
    }

    private func findRawCrashReportUrl() throws -> URL {
        enum Error: Swift.Error {
            case reportNotFound
        }

        let reportsUrl = installUrl.appending(component: "Reports")
        let reportUrl = try FileManager.default
            .contentsOfDirectory(atPath: reportsUrl.path())
            .first
            .flatMap { reportsUrl.appending(component:$0) }
        guard let reportUrl else { throw Error.reportNotFound }
        return reportUrl
    }

    func readRawCrashReportData() throws -> Data {
        enum Error: Swift.Error {
            case reportNotFound
        }

        let fileExpectation = XCTNSPredicateExpectation(
            predicate: .init { innerSelf, _ in
                (try? (innerSelf as! Self).findRawCrashReportUrl()) != nil
            },
            object: self
        )
        wait(for: [fileExpectation], timeout: reportTimeout)

        let reportPath = try findRawCrashReportUrl().path()
        let reportData = try Data(contentsOf: .init(filePath: reportPath))
        return reportData
    }

    func readRawCrashReport() throws -> [String: Any] {
        enum Error: Swift.Error {
            case unexpectedReportFormat
        }

        let reportData = try readRawCrashReportData()
        let reportObj = try JSONSerialization.jsonObject(with: reportData)
        let report = reportObj as? [String:Any]
        guard let report else { throw Error.unexpectedReportFormat }

        return report
    }

    func readPartialCrashReport() throws -> PartialCrashReport {
        let reportData = try readRawCrashReportData()
        let report = try JSONDecoder().decode(PartialCrashReport.self, from: reportData)
        return report
    }

    private func findAppleReportUrl() throws -> URL {
        enum Error: Swift.Error {
            case reportNotFound
        }

        let reportPath = try FileManager.default
            .contentsOfDirectory(atPath: appleReportsUrl.path())
            .first
            .flatMap { appleReportsUrl.appending(component:$0) }
        guard let reportPath else { throw Error.reportNotFound }
        return reportPath
    }

    func readAppleReport() throws -> String {
        let fileExpectation = XCTNSPredicateExpectation(
            predicate: .init { innerSelf, _ in
                (try? (innerSelf as! Self).findAppleReportUrl()) != nil
            },
            object: self
        )
        wait(for: [fileExpectation], timeout: reportTimeout)

        let url = try findAppleReportUrl()
        let appleReport = try String(contentsOf: url)
        return appleReport
    }

    func launchAndCrash(_ crashId: CrashTriggerId, installOverride: ((inout InstallConfig) throws -> Void)? = nil) throws {
        var installConfig = InstallConfig(installPath: installUrl.path())
        try installOverride?(&installConfig)
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            crash: .init(triggerId: crashId),
            install: installConfig
        )

        launchAppAndRunScript()
        waitForCrash()
    }

    func launchAndReportCrash() throws -> String {
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            report: .init(directoryPath: appleReportsUrl.path()),
            install: .init(installPath: installUrl.path())
        )

        launchAppAndRunScript()
        let report = try readAppleReport()
        return report
    }
}
