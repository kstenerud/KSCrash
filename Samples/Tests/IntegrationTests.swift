//
//  IntegrationTests.swift
//
//  Created by Nikolay Volosatov on 2024-07-21.
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

final class IntegrationTests: XCTestCase {

    var installUrl: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        installUrl = FileManager.default.temporaryDirectory
            .appending(component: "KSCrash")
            .appending(component: UUID().uuidString)
        try! FileManager.default.createDirectory(at: installUrl, withIntermediateDirectories: true)
        print(installUrl.path())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: installUrl)
    }

    func testExample() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KSCrashInstallPath"] = installUrl.path()
        app.launch()

        app.buttons[AccessibilityIdentifiers.InstallView.installButton].tap()
        app.buttons[AccessibilityIdentifiers.MainView.crashButton].tap()
        app.buttons[AccessibilityIdentifiers.CrashView.nsexceptionButton].tap()

        let expectation = XCTNSPredicateExpectation(predicate: .init { _, _ in app.state == .notRunning }, object: nil)
        wait(for: [expectation], timeout: 2.0)

        XCTAssertEqual(app.state, .notRunning)
        let reportsUrl = installUrl.appending(component: "Reports")
        let reportPath = try! FileManager.default
            .contentsOfDirectory(atPath: reportsUrl.path())
            .first
            .flatMap { reportsUrl.appending(component:$0).path() }
        XCTAssertNotNil(reportPath)
        print(reportPath!)
        let report = try? JSONSerialization.jsonObject(with: Data(contentsOf: .init(filePath: reportPath!)))
        XCTAssertNotNil(report)
        var parsedReason: String?
        if let report = report as? [String:Any],
           let crash = report["crash"] as? [String:Any],
           let error = crash["error"] as? [String:Any],
           let reason = error["reason"] as? String {
            parsedReason = reason
        }
        XCTAssertEqual(parsedReason, "Test")

        app.launchEnvironment["KSCrashInstallPath"] = installUrl.path()
        app.launch()

        app.buttons[AccessibilityIdentifiers.InstallView.installButton].tap()
        app.buttons[AccessibilityIdentifiers.MainView.reportButton].tap()
        app.buttons[AccessibilityIdentifiers.ReportView.consoleButton].tap()

        app.terminate()
    }
}
