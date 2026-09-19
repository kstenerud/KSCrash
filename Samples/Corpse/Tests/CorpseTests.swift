//
//  CorpseTests.swift
//
//  Created by Alexander Cohen on 2026-09-19.
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

/// End-to-end coverage of the out-of-process path, on a real device.
///
/// Each test kills the app the way the system would, lets the OS hand the corpse
/// to the extension, relaunches, and reads the verdict the app publishes after
/// draining and sending. Nothing here can pass in a simulator: the framework the
/// extension links is absent from the simulator SDK, and a simulator never hands
/// anyone a corpse.
final class CorpseTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
            throw XCTSkip("the crash extension ships in the device SDK only")
        #endif
    }

    /// Kills the app with `trigger`, then relaunches and returns what the app
    /// made of the report that came back through its send pipeline.
    private func runCycle(trigger: String, deadline: TimeInterval) throws -> (
        status: String, detail: String
    ) {
        // No in-process monitors are armed here, deliberately: the host installs
        // with none, so any report that arrives can only have come from the
        // extension. That includes the hang monitor, whose own report would
        // compete with the corpse's. The OS watchdog that produces 0x8badf00d is
        // a different thing entirely and needs nothing from us.
        let app = XCUIApplication()
        app.launchArguments = ["--corpse-crash", trigger]
        app.launch()

        // Read which run is about to die before killing it. Everything after
        // this is checked against this id, so a leftover report from an earlier
        // case cannot masquerade as this one's.
        let runIDLabel = app.staticTexts["corpse.runid"]
        XCTAssertTrue(runIDLabel.waitForExistence(timeout: 30), "\(trigger): app never came up")
        let runID = runIDLabel.label
        // The app puts the install's own error in the detail label, so a setup
        // failure explains itself instead of looking like a missing report.
        XCTAssertNotEqual(
            runID, "no-run-id",
            "\(trigger): install produced no run id. \(app.staticTexts["corpse.detail"].label)")

        // Tapping rather than crashing on launch keeps the read above from
        // racing the process death.
        app.buttons["corpse.trigger"].tap()

        // The app is supposed to die. Waiting for "not running" is the assertion
        // that the termination actually happened, rather than the trigger being
        // a no-op on this OS version.
        let died = app.wait(for: .notRunning, timeout: deadline)
        XCTAssertTrue(died, "\(trigger): the app did not terminate, so no corpse was produced")

        // The system runs the extension after the app dies. It gets its own
        // process and its own schedule, so the report is not guaranteed to exist
        // the instant the app is gone.
        Thread.sleep(forTimeInterval: 5)

        let verifier = XCUIApplication()
        verifier.launchArguments = ["--corpse-verify", trigger, "--corpse-expect-run", runID]
        verifier.launch()

        let status = verifier.staticTexts["corpse.status"]
        XCTAssertTrue(
            status.waitForExistence(timeout: 60), "\(trigger): the app published no verdict")
        return (status.label, verifier.staticTexts["corpse.detail"].label)
    }

    func testMachBadAccessIsCapturedFromTheCorpse() throws {
        let result = try runCycle(trigger: "trigger-mach-badAccess", deadline: 20)
        XCTAssertEqual(result.status, "pass", result.detail)
    }

    func testSignalAbortIsCapturedFromTheCorpse() throws {
        let result = try runCycle(trigger: "trigger-signal-abort", deadline: 20)
        XCTAssertEqual(result.status, "pass", result.detail)
    }

    func testNSExceptionIsCapturedFromTheCorpse() throws {
        let result = try runCycle(trigger: "trigger-nsException-genericNSException", deadline: 20)
        XCTAssertEqual(result.status, "pass", result.detail)
    }

    func testBackgroundThreadCrashNamesTheRightThread() throws {
        let result = try runCycle(
            trigger: "trigger-cpp-runtimeExceptionBackgroundThread", deadline: 20)
        XCTAssertEqual(result.status, "pass", result.detail)
    }

    func testStackOverflowIsCapturedFromTheCorpse() throws {
        let result = try runCycle(trigger: "trigger-other-stackOverflow", deadline: 20)
        XCTAssertEqual(result.status, "pass", result.detail)
    }

    /// Real jetsam, not the simulator's fake: the trigger dirties every page it
    /// allocates, so the kernel kills the process for actual memory use. Slow by
    /// nature, since it has to exhaust the device.
    func testMemoryLimitKillIsCapturedFromTheCorpse() throws {
        let result = try runCycle(trigger: "trigger-memory-oom", deadline: 120)
        XCTAssertEqual(result.status, "pass", result.detail)
    }
}
