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

import CrashTriggers
import IntegrationTestsHelper
import Logging
import SampleUI
import XCTest

class IntegrationTestBase: XCTestCase {

    private(set) var log: Logger!
    private(set) var app: XCUIApplication!

    private(set) var installUrl: URL!
    private(set) var appleReportsUrl: URL!
    private(set) var stateUrl: URL!

    var appLaunchTimeout: TimeInterval = 10.0
    var appTerminateTimeout: TimeInterval = 5.0
    var appCrashTimeout: TimeInterval = 10.0

    var reportTimeout: TimeInterval = 5.0

    var expectSingleCrash: Bool = true

    lazy var actionDelay: TimeInterval = Self.defaultActionDelay
    private static var defaultActionDelay: TimeInterval {
        #if os(iOS)
            return 5.0
        #else
            return 2.0
        #endif
    }

    private var runConfig: IntegrationTestRunner.RunConfig {
        .init(
            delay: actionDelay,
            stateSavePath: stateUrl.path
        )
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        continueAfterFailure = true

        log = Logger(label: name)
        installUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("KSCrash")
            .appendingPathComponent(UUID().uuidString)
        appleReportsUrl = installUrl.appendingPathComponent("__TEST_REPORTS__")
        stateUrl = installUrl.appendingPathComponent("__test_state__.json")

        try FileManager.default.createDirectory(at: appleReportsUrl, withIntermediateDirectories: true)
        log.info("KSCrash install path: \(installUrl.path)")

        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        app.terminate()
        _ = app.wait(for: .notRunning, timeout: appTerminateTimeout)

        if let files = FileManager.default.enumerator(atPath: installUrl.path) {
            log.info("Remaining KSCrash files:")
            for file in files {
                log.info("\t\(file)")
            }
        }

        try? FileManager.default.removeItem(at: installUrl)
    }

    func launchAppAndRunScript() {
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: appLaunchTimeout)
    }

    func waitForCrash() {
        #if os(macOS)
            // This is a workaround. App actually crashes, but tests don't see it.
            Thread.sleep(forTimeInterval: actionDelay + appCrashTimeout)
        #else
            XCTAssert(app.wait(for: .notRunning, timeout: actionDelay + appCrashTimeout), "App crash is expected")
        #endif
    }

    private func waitForFile(in dir: URL, timeout: TimeInterval? = nil) throws -> URL {
        enum Error: Swift.Error {
            case fileNotFound
            case tooManyFiles
        }

        let getFileUrl = { [unowned self] in
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            guard let fileName = files.first else {
                throw Error.fileNotFound
            }
            if self.expectSingleCrash {
                guard files.count == 1 else {
                    throw Error.tooManyFiles
                }
            }
            return dir.appendingPathComponent(fileName)
        }

        if let timeout {
            let fileExpectation = XCTNSPredicateExpectation(
                predicate: .init { _, _ in (try? getFileUrl()) != nil },
                object: nil
            )
            wait(for: [fileExpectation], timeout: timeout)
        }
        return try getFileUrl()
    }

    private func findRawCrashReportUrl() throws -> URL {
        enum LocalError: Error {
            case reportNotFound
        }

        let reportsUrl = installUrl.appendingPathComponent("Reports")
        let reportUrl = try FileManager.default
            .contentsOfDirectory(atPath: reportsUrl.path)
            .first
            .flatMap { reportsUrl.appendingPathComponent($0) }
        guard let reportUrl else { throw LocalError.reportNotFound }
        return reportUrl
    }

    func readRawCrashReportData() throws -> Data {
        let reportsDirUrl = installUrl.appendingPathComponent("Reports")
        let reportUrl = try waitForFile(in: reportsDirUrl, timeout: reportTimeout)
        let reportData = try Data(contentsOf: reportUrl)
        return reportData
    }

    func readRawCrashReport() throws -> [String: Any] {
        enum LocalError: Error {
            case unexpectedReportFormat
        }

        let reportData = try readRawCrashReportData()
        let reportObj = try JSONSerialization.jsonObject(with: reportData)
        let report = reportObj as? [String: Any]
        guard let report else { throw LocalError.unexpectedReportFormat }

        return report
    }

    func readPartialCrashReport() throws -> PartialCrashReport {
        let reportData = try readRawCrashReportData()
        let report = try JSONDecoder().decode(PartialCrashReport.self, from: reportData)
        return report
    }

    func hasCrashReport() throws -> Bool {
        let reportsDirUrl = installUrl.appendingPathComponent("Reports")
        let files = try? FileManager.default.contentsOfDirectory(atPath: reportsDirUrl.path)
        return (files ?? []).isEmpty == false
    }

    func readAppleReport() throws -> String {
        let url = try waitForFile(in: appleReportsUrl, timeout: reportTimeout)
        let appleReport = try String(contentsOf: url)
        return appleReport
    }

    func launchAndInstall(installOverride: ((inout InstallConfig) throws -> Void)? = nil) throws {
        var installConfig = InstallConfig(installPath: installUrl.path)
        try installOverride?(&installConfig)
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            install: installConfig,
            config: runConfig
        )

        launchAppAndRunScript()
    }

    func launchAndCrash(_ crashId: CrashTriggerId, installOverride: ((inout InstallConfig) throws -> Void)? = nil)
        throws
    {
        var installConfig = InstallConfig(installPath: installUrl.path)
        try installOverride?(&installConfig)
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            crash: .init(triggerId: crashId),
            install: installConfig,
            config: runConfig
        )

        launchAppAndRunScript()
        waitForCrash()
    }

    func launchAndMakeUserReport(
        userException: UserReportConfig.UserException? = nil,
        nsException: UserReportConfig.NSExceptionReport? = nil,
        installOverride: ((inout InstallConfig) throws -> Void)? = nil
    ) throws {
        var installConfig = InstallConfig(installPath: installUrl.path)
        try installOverride?(&installConfig)
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            userReport: .init(userException: userException, nsException: nsException),
            install: installConfig,
            config: runConfig
        )

        launchAppAndRunScript()
    }

    func launchAndReportCrash() throws -> String {
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            report: .init(directoryPath: appleReportsUrl.path),
            install: .init(installPath: installUrl.path),
            config: runConfig
        )

        launchAppAndRunScript()
        let report = try readAppleReport()
        return report
    }

    func readState() throws -> KSCrashState {
        let data = try Data(contentsOf: stateUrl)
        let state = try JSONDecoder().decode(KSCrashState.self, from: data)
        return state
    }

    func terminate() throws {
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: self.appTerminateTimeout)
    }
}
