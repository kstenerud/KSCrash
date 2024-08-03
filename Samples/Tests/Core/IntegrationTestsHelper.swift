//
//  IntegrationTestsHelper.swift
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
import Logging

class IntegrationTest: XCTestCase {

    private(set) var log: Logger!
    private(set) var app: XCUIApplication!

    private(set) var installUrl: URL!
    private(set) var appleReportUrl: URL!

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
        appleReportUrl = installUrl.appending(component: "report.txt")

        try FileManager.default.createDirectory(at: installUrl, withIntermediateDirectories: true)
        log.info("KSCrash install path: \(installUrl.path())")

        app = XCUIApplication()
        app.launchEnvironment["KSCrashInstallPath"] = installUrl.path()
        app.launchEnvironment["KSCrashReportToFile"] = appleReportUrl.path()
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

    func launchApp() {
        app.launch()
        XCTAssert(
            sampleButton(.installView(.installButton))
            .waitForExistence(timeout: appLaunchTimeout)
        )
    }

    func sampleButton(_ element: TestElementId) -> XCUIElement {
        app.buttons[element.accessibilityId]
    }

    func tapButtons(_ elements: [TestElementId]) {
        for element in elements {
            XCTAssert(sampleButton(element).waitForExistence(timeout: screenLoadingTimeout))
            sampleButton(element).tap()
        }
    }

    func waitForCrash() {
        XCTAssert(app.wait(for: .notRunning, timeout: appCrashTimeout), "App crash is expected")
    }

    func readRawCrashReportData() throws -> Data {
        enum Error: Swift.Error {
            case reportNotFound
        }

        let reportsUrl = installUrl.appending(component: "Reports")
        let reportPath = try FileManager.default
            .contentsOfDirectory(atPath: reportsUrl.path())
            .first
            .flatMap { reportsUrl.appending(component:$0).path() }
        guard let reportPath else { throw Error.reportNotFound }

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

    func readAppleReport() throws -> String {
        let path = appleReportUrl.path()
        let fileExpectation = XCTNSPredicateExpectation(
            predicate: .init { _, _ in FileManager.default.fileExists(atPath: path) },
            object: nil
        )
        wait(for: [fileExpectation], timeout: reportTimeout)

        let appleReport = try String(contentsOf: appleReportUrl)
        return appleReport
    }

    func launchAndCrash(_ crashViewElement: TestElementId.CrashViewElements) {
        launchApp()

        tapButtons([
            .installView(.installButton),
            .mainView(.crashButton),
            .crashView(crashViewElement),
        ])

        waitForCrash()
    }

    func launchAndReportCrash() throws -> String {
        launchApp()

        tapButtons([
            .installView(.installButton),
            .mainView(.reportButton),
            .reportingView(.logToFileButton),
        ])

        let report = try readAppleReport()
        return report
    }
}
