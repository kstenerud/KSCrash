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
import KSCrashReportModel
import Logging
import SampleUI
import XCTest

@MainActor
class IntegrationTestBase: XCTestCase {

    private(set) var log: Logger!
    private(set) var app: TargetApp!

    private(set) var installUrl: URL!
    private(set) var deliveredReportsUrl: URL!
    private(set) var stateUrl: URL!
    private(set) var actionCompletedUrl: URL!

    var appLaunchTimeout: TimeInterval = 10.0
    var appTerminateTimeout: TimeInterval = 5.0
    var appCrashTimeout: TimeInterval = 10.0

    /// How long a report may take once the script's `actionDelay` has passed. Waits for a
    /// report count from launch, so they add the delay: the launch returns long before the
    /// script acts.
    var reportTimeout: TimeInterval = 5.0

    var expectSingleCrash: Bool = true

    lazy var actionDelay: TimeInterval = TargetPlatform.current == .iOS ? 5.0 : 2.0

    /// The platforms this class's tests run on. The tests always run on the Mac, so a class
    /// that only makes sense on some targets says so here instead of in `#if os(...)`, and the
    /// rest are skipped with the reason visible in the results.
    class var platforms: Set<TargetPlatform> { Set(TargetPlatform.allCases) }

    private var runConfig: IntegrationTestRunner.RunConfig {
        .init(
            delay: actionDelay,
            stateSavePath: stateUrl.path
        )
    }

    private var runConfigWithCompletionMarker: IntegrationTestRunner.RunConfig {
        .init(
            delay: actionDelay,
            stateSavePath: stateUrl.path,
            completionMarkerPath: actionCompletedUrl.path
        )
    }

    override func setUp() async throws {
        try await super.setUp()
        guard TargetPlatform.configured != nil else { throw TargetAppError.noPlatform }
        try XCTSkipUnless(
            Self.platforms.contains(TargetPlatform.current),
            "\(Self.self) runs on \(Self.platforms.map(\.rawValue).sorted()), not \(TargetPlatform.current)")

        continueAfterFailure = true

        log = Logger(label: name)
        installUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("KSCrash")
            .appendingPathComponent(UUID().uuidString)
        deliveredReportsUrl = installUrl.appendingPathComponent("__TEST_REPORTS__")
        stateUrl = installUrl.appendingPathComponent("__test_state__.json")
        actionCompletedUrl = installUrl.appendingPathComponent("__test_action_completed__")

        try FileManager.default.createDirectory(at: deliveredReportsUrl, withIntermediateDirectories: true)
        log.info("KSCrash install path: \(installUrl.path)")

        app = try TargetApp()
    }

    override func tearDown() async throws {
        try await super.tearDown()

        app?.terminate()

        // A test skipped in setUp never got an install directory.
        guard let installUrl else { return }
        if let files = try? FileManager.default.subpathsOfDirectory(atPath: installUrl.path) {
            log.info("Remaining KSCrash files:")
            for file in files {
                log.info("\t\(file)")
            }
            attach(files.sorted().joined(separator: "\n"), named: "Remaining KSCrash files")
            // Every run's KSCrash console log, which says what the app did when a test fails.
            for file in files.sorted() where file.hasSuffix("/Data/ConsoleLog.txt") {
                logFile(name: file, path: installUrl.appendingPathComponent(file).path)
            }
        }

        try? FileManager.default.removeItem(at: installUrl)
    }

    /// Attachments are kept in the result bundle only when the test fails (their default
    /// lifetime), which is what CI uploads; printed output is lost to xcodebuild's formatters.
    func attach(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        add(attachment)
    }

    func logData(name: String, data: Data) {
        let str = String(data: data, encoding: .utf8) ?? "<no \(name)>"
        attach(str, named: name)
        log.info(
            "\n\nvvvvvvvvvvvvvvvvvvvv \(name) vvvvvvvvvvvvvvvvvvvv\n\(str)\n^^^^^^^^^^^^^^^^^^^^ \(name) ^^^^^^^^^^^^^^^^^^^^"
        )
    }

    func logFile(name: String, path: String) {
        if FileManager.default.fileExists(atPath: path) {
            do {
                let str = try String(contentsOfFile: path, encoding: .utf8)
                attach(str, named: name)
                log.info(
                    "\n\nvvvvvvvvvvvvvvvvvvvv \(name) vvvvvvvvvvvvvvvvvvvv\n\(str)\n^^^^^^^^^^^^^^^^^^^^ \(name) ^^^^^^^^^^^^^^^^^^^^"
                )
            } catch {
                log.info("Could not load \(name) from \(path): \(error)")
            }
        }
    }

    func launchAppAndRunScript() {
        // A launch returns before the app has run anything, and tests read the state file
        // straight after it. The script writes that file right after installing KSCrash, so
        // a fresh one is the sign the launch has got that far; the old one is removed first
        // so it cannot be mistaken for it. A launch that dies before writing it just runs out
        // the timeout.
        try? FileManager.default.removeItem(at: stateUrl)
        app.launch()
        let deadline = Date().addingTimeInterval(appLaunchTimeout)
        while !FileManager.default.fileExists(atPath: stateUrl.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    func waitForCrash() {
        XCTAssert(app.wait(for: .notRunning, timeout: actionDelay + appCrashTimeout), "App crash is expected")
        logFile(name: "Data/ConsoleLog.txt", path: installUrl.path.appending("/Data/ConsoleLog.txt"))
    }

    private func waitForFile(at url: URL, timeout: TimeInterval) throws {
        enum Error: Swift.Error {
            case fileNotFound
        }

        let fileExpectation = XCTNSPredicateExpectation(
            predicate: .init { _, _ in FileManager.default.fileExists(atPath: url.path) },
            object: nil
        )
        wait(for: [fileExpectation], timeout: timeout)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Error.fileNotFound
        }
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

        let reportsUrl = try reportsDirectoryUrl()
        let reportUrl = try FileManager.default
            .contentsOfDirectory(atPath: reportsUrl.path)
            .first
            .flatMap { reportsUrl.appendingPathComponent($0) }
        guard let reportUrl else { throw LocalError.reportNotFound }
        return reportUrl
    }

    func readRawCrashReportData() throws -> Data {
        let reportsDirUrl = try reportsDirectoryUrl()
        let reportUrl = try waitForFile(in: reportsDirUrl, timeout: actionDelay + reportTimeout)
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

    func readCrashReport() throws -> Report {
        let reportData = try readRawCrashReportData()
        let report = try JSONDecoder().decode(Report.self, from: reportData)
        return report
    }

    func decodeCrashReport(reportData: Data) throws -> Report {
        return try JSONDecoder().decode(Report.self, from: reportData)
    }

    func hasCrashReport() throws -> Bool {
        let reportsDirUrl = try reportsDirectoryUrl()
        let files = try? FileManager.default.contentsOfDirectory(atPath: reportsDirUrl.path)
        return (files ?? []).isEmpty == false
    }

    func readDeliveredReportData() throws -> Data {
        let url = try waitForFile(in: deliveredReportsUrl, timeout: actionDelay + reportTimeout)
        return try Data(contentsOf: url)
    }

    func launchAndInstall(installOverride: ((inout InstallConfig) throws -> Void)? = nil) throws {
        var installConfig = InstallConfig(namespace: "IntegrationTests", basePath: installUrl.path)
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
        var installConfig = InstallConfig(namespace: "IntegrationTests", basePath: installUrl.path)
        try installOverride?(&installConfig)
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            crash: .init(triggerId: crashId),
            install: installConfig,
            config: runConfig
        )

        launchAppAndRunScript()
        waitForCrash()
    }

    func launchAndRunTrigger(
        _ triggerId: CrashTriggerId, installOverride: ((inout InstallConfig) throws -> Void)? = nil
    )
        throws
    {
        var installConfig = InstallConfig(namespace: "IntegrationTests", basePath: installUrl.path)
        try installOverride?(&installConfig)
        try? FileManager.default.removeItem(at: actionCompletedUrl)
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            crash: .init(triggerId: triggerId),
            install: installConfig,
            config: runConfigWithCompletionMarker
        )

        launchAppAndRunScript()
        try waitForFile(at: actionCompletedUrl, timeout: appLaunchTimeout + actionDelay + appCrashTimeout)
    }

    func launchAndMakeUserReport(
        userException: UserReportConfig.UserException? = nil,
        nsException: UserReportConfig.NSExceptionReport? = nil,
        installOverride: ((inout InstallConfig) throws -> Void)? = nil
    ) throws {
        var installConfig = InstallConfig(namespace: "IntegrationTests", basePath: installUrl.path)
        try installOverride?(&installConfig)
        try? FileManager.default.removeItem(at: actionCompletedUrl)
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            userReport: .init(userException: userException, nsException: nsException),
            install: installConfig,
            config: runConfigWithCompletionMarker
        )

        launchAppAndRunScript()
        // The app keeps running, so its report is still being written, then rewritten by
        // finalization, when the file first appears. A user report writes and finalizes before
        // returning, and the script marks completion after it returns.
        try waitForFile(at: actionCompletedUrl, timeout: actionDelay + reportTimeout)
    }

    func launchAndSigkill(
        env: [String: String] = [:],
        installOverride: ((inout InstallConfig) throws -> Void)? = nil
    ) throws {
        for (key, value) in env {
            app.launchEnvironment[key] = value
        }
        try launchAndCrash(.other_sigkill, installOverride: installOverride)
        // Clear override env vars so the next launch reads real system/resource values.
        for key in env.keys {
            app.launchEnvironment.removeValue(forKey: key)
        }
    }

    /// Relaunch the app, deliver the pending reports through the Swift send,
    /// and return the delivered report decoded from the dump directory.
    func launchAndReportCrash() throws -> Report {
        try decodeCrashReport(reportData: launchAndReportCrashRaw())
    }

    func launchAndReportCrashRaw(
        installOverride: ((inout InstallConfig) throws -> Void)? = nil
    ) throws -> Data {
        var installConfig = InstallConfig(namespace: "IntegrationTests", basePath: installUrl.path)
        try installOverride?(&installConfig)
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            report: .init(directoryPath: deliveredReportsUrl.path),
            install: installConfig,
            config: runConfig
        )

        launchAppAndRunScript()
        return try readDeliveredReportData()
    }

    func readState() throws -> KSCrashState {
        let data = try Data(contentsOf: stateUrl)
        let state = try JSONDecoder().decode(KSCrashState.self, from: data)
        return state
    }

    /// The install's reports directory, read from the state file the app
    /// writes at install time; the harness never re-derives the layout.
    func reportsDirectoryUrl() throws -> URL {
        enum LocalError: Error {
            case reportsPathNotInState
        }
        guard let path = try readState().reportsPath else { throw LocalError.reportsPathNotInState }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The install's runs directory, read from the same state file.
    func runsDirectoryUrl() throws -> URL {
        enum LocalError: Error {
            case runsPathNotInState
        }
        guard let path = try readState().runsPath else { throw LocalError.runsPathNotInState }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func terminate() throws {
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: self.appTerminateTimeout)
    }
}
