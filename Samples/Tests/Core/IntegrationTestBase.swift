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
    private var attachedAppDiagnostics = false

    private(set) var installUrl: URL!
    private(set) var deliveredReportsUrl: URL!
    private(set) var stateUrl: URL!
    private(set) var actionCompletedUrl: URL!

    var appLaunchTimeout: TimeInterval = 10.0
    var appTerminateTimeout: TimeInterval = 5.0
    var appCrashTimeout: TimeInterval = 10.0

    /// How long a report may take once the script's `actionDelay` has passed. The waits start
    /// at launch, so they add the delay: the launch returns long before the script acts.
    var reportTimeout: TimeInterval = 5.0

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
        // The whole folder the app left, reports and sidecars included, since a failure's cause is
        // often in what was written rather than in what the test read. Zipped only for a failed
        // test, after the app is terminated so nothing is still writing.
        if testRun?.hasSucceeded == false {
            let folder = XCTAttachment(compressedContentsOfDirectory: installUrl)
            folder.name = "KSCrash folder"
            add(folder)
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
        let exited = app.wait(for: .notRunning, timeout: actionDelay + appCrashTimeout)
        XCTAssert(exited, "App crash is expected")
        if !exited {
            attachAppDiagnostics()
        }
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
            attachAppDiagnostics()
            throw Error.fileNotFound
        }
    }

    /// A report read off disk: its file name, its bytes, and the report they decode to. A file
    /// that does not decode yet is still being written.
    private struct ReportFile {
        let name: String
        let data: Data?
        let report: Report?

        /// Enough to tell why a test did or did not pick a report: what it is, which run it
        /// came from, and whether it was finalized.
        var summary: String {
            guard let report else { return "\(name): unreadable" }
            let error = report.crash.error
            let signal = error.signal.map { " signal \($0.signal)," } ?? ""
            return "\(name): monitor \(report.report.monitorId ?? "?"), type \(error.type.rawValue),\(signal)"
                + " run \(report.report.runId?.description ?? "?"), finalized \(report.report.finalized ?? false)"
        }
    }

    private func reportFiles(in dir: URL) -> [ReportFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { name in
            // A store keeps its staging folder beside the reports.
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path, isDirectory: &isDirectory)
            return !name.hasPrefix(".") && !isDirectory.boolValue
        }.sorted().map { name in
            let data = try? Data(contentsOf: dir.appendingPathComponent(name))
            let report = data.flatMap { try? JSONDecoder().decode(Report.self, from: $0) }
            return ReportFile(name: name, data: data, report: report)
        }
    }

    /// Whether `report` is the one a test asked for: `isReport` says so, and once a run is
    /// recorded it comes from that run, since a report another run left behind can match
    /// everything else a test names.
    private func isRequested(_ report: Report, _ isReport: (Report) -> Bool) -> Bool {
        if let expectedRunID, report.report.runId != expectedRunID {
            return false
        }
        return isReport(report)
    }

    /// Waits for the report `isReport` picks out and returns its bytes.
    ///
    /// Exactly one report may match: two would be the same event reported twice. Every other
    /// report in the folder belongs to some other monitor and is not looked at.
    private func waitForReport(
        in dir: URL, timeout: TimeInterval, where isReport: @escaping (Report) -> Bool
    ) throws -> Data {
        enum Error: Swift.Error, CustomStringConvertible {
            case reportNotFound([String])
            case tooManyReports([String])

            var description: String {
                switch self {
                case .reportNotFound(let all): return "The report never appeared. Reports: \(all)"
                case .tooManyReports(let all): return "More than one report matched. Reports: \(all)"
                }
            }
        }

        let matching = { [unowned self] in
            self.reportFiles(in: dir).filter { file in file.report.map { self.isRequested($0, isReport) } == true }
        }
        let reportExpectation = XCTNSPredicateExpectation(
            predicate: .init { _, _ in !matching().isEmpty },
            object: nil
        )
        wait(for: [reportExpectation], timeout: timeout)

        let found = matching()
        if found.count == 1, let data = found[0].data {
            return data
        }
        let listing = ["Expected run: \(expectedRunID?.description ?? "any")"] + reportFiles(in: dir).map(\.summary)
        attachAppDiagnostics()
        attach(listing.joined(separator: "\n"), named: "Reports found")
        throw found.isEmpty ? Error.reportNotFound(listing) : Error.tooManyReports(listing)
    }

    /// A wait that runs out says only that the file never came. Records what the app was doing
    /// instead, once per test, while teardown has not yet ended it.
    private func attachAppDiagnostics() {
        guard !attachedAppDiagnostics, let app else { return }
        attachedAppDiagnostics = true
        for (name, text) in app.diagnostics() {
            attach(text, named: name)
        }
    }

    /// The bytes of the report `isReport` picks out, read straight from the store's folder.
    /// The store has not stitched it yet, so only what was written when it was recorded is
    /// there to match on.
    ///
    /// - Parameter timeout: how long to wait for it; by default the script's delay plus
    ///   `reportTimeout`.
    func readRawCrashReportData(
        timeout: TimeInterval? = nil, where isReport: @escaping (Report) -> Bool
    ) throws -> Data {
        try waitForReport(
            in: try reportsDirectoryUrl(), timeout: timeout ?? actionDelay + reportTimeout, where: isReport)
    }

    func readCrashReport(where isReport: @escaping (Report) -> Bool) throws -> Report {
        try decodeCrashReport(reportData: readRawCrashReportData(where: isReport))
    }

    func decodeCrashReport(reportData: Data) throws -> Report {
        return try JSONDecoder().decode(Report.self, from: reportData)
    }

    /// Whether the store holds a report `isReport` picks out. Checked once, without waiting:
    /// call it after whatever would have written the report has finished. A poll passes
    /// `attachingListing: false` and calls `attachReportListing()` once it is done, so the
    /// results carry one listing rather than one per check.
    func hasReport(attachingListing: Bool = true, where isReport: (Report) -> Bool) throws -> Bool {
        let reports = reportFiles(in: try reportsDirectoryUrl())
        if attachingListing {
            attachReportListing(reports)
        }
        return reports.contains { file in file.report.map { isRequested($0, isReport) } == true }
    }

    /// Attaches what the store holds right now to the test's results.
    func attachReportListing() throws {
        attachReportListing(reportFiles(in: try reportsDirectoryUrl()))
    }

    private func attachReportListing(_ reports: [ReportFile]) {
        if !reports.isEmpty {
            attach(reports.map(\.summary).joined(separator: "\n"), named: "Reports found")
        }
    }

    /// The bytes of the delivered report `isReport` picks out, stitched as KSCrash delivers it.
    func readDeliveredReportData(where isReport: @escaping (Report) -> Bool) throws -> Data {
        try waitForReport(in: deliveredReportsUrl, timeout: actionDelay + reportTimeout, where: isReport)
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
        try recordExpectedRunID()
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
        try recordExpectedRunID()
    }

    func launchAndSigkill(
        env: [String: String] = [:],
        installOverride: ((inout InstallConfig) throws -> Void)? = nil
    ) throws {
        for (key, value) in env {
            app.launchEnvironment[key] = value
        }
        // Hangs are off: a loaded simulator can hang at launch, and a hang still going at
        // the kill makes the run a hang, outranking whatever reason the test is about.
        try launchAndCrash(.other_sigkill) { config in
            config.isWatchdogEnabled = false
            try installOverride?(&config)
        }
        // Clear override env vars so the next launch reads real system/resource values.
        for key in env.keys {
            app.launchEnvironment.removeValue(forKey: key)
        }
    }

    /// The id of the run whose report the test is about to read back.
    private(set) var expectedRunID: RunSummary.ID?

    /// Records the id of the run just launched. Everything read back afterwards
    /// is checked against it, so a report left over from an earlier case cannot
    /// pass for this one's. The app writes its state at install, before the
    /// crash or the user report it was launched to make.
    private func recordExpectedRunID() throws {
        try waitForFile(at: stateUrl, timeout: appLaunchTimeout)
        expectedRunID = try readState().runID
    }

    /// Relaunch the app, deliver the pending reports through the Swift send,
    /// and return the delivered report decoded from the dump directory.
    func launchAndReportCrash(where isReport: @escaping (Report) -> Bool) throws -> Report {
        let report = try decodeCrashReport(reportData: launchAndReportCrashRaw(where: isReport))
        assertReportIsFromExpectedRun(report)
        return report
    }

    /// Ties a delivered report to the run that produced it.
    ///
    /// Every assertion a test makes about a report is worthless if the report
    /// came from a different run: the content is plausible, the test is green,
    /// and nothing was checked. A missing id is that same blind spot, so it
    /// fails here rather than passing unchecked.
    func assertReportIsFromExpectedRun(
        _ report: Report, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let expectedRunID else {
            XCTFail("no run id was recorded for the run under test", file: file, line: line)
            return
        }
        XCTAssertEqual(
            report.report.runId, expectedRunID,
            "the delivered report is not from the run under test", file: file, line: line)
    }

    func launchAndReportCrashRaw(
        where isReport: @escaping (Report) -> Bool,
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
        return try readDeliveredReportData(where: isReport)
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
