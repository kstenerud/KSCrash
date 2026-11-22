//
//  WatchdogTests.swift
//
//  Created by Alexander Cohen on 2025-12-08.
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

import IntegrationTestsHelper
import KSCrashRecording
import KSCrashReportModel
import XCTest

final class WatchdogTests: IntegrationTestBase {
    override class var platforms: Set<TargetPlatform> { Set(TargetPlatform.allCases).subtracting([.watchOS]) }

    override func setUp() async throws {
        try await super.setUp()
        appCrashTimeout = 10.0
    }

    func testWatchdogTimeoutTermination() throws {
        // Enable watchdog monitoring and trigger a simulated watchdog timeout
        try launchAndCrash(.other_watchdogTimeoutTermination) { config in
            config.isWatchdogEnabled = true
        }

        // Re-launch and read through the report store so the sidecar stitch runs
        let reportData = try launchAndReportCrashRaw(where: {
            $0.report.monitorId == "Watchdog" && $0.crash.error.signal?.signal == UInt64(SIGKILL)
        }) { config in
            config.isWatchdogEnabled = true
        }
        let rawReport = try JSONDecoder().decode(Report.self, from: reportData)

        // Verify hang info is present in the crash report
        let hangInfo = rawReport.crash.error.hang
        XCTAssertNotNil(hangInfo, "Hang info should be present in crash report")
        XCTAssertNotNil(hangInfo?.hangStartNanos, "Hang start timestamp should be present")
        XCTAssertNotNil(hangInfo?.hangEndNanos, "Hang end timestamp should be present")

        // Verify the hang duration is reasonable (at least 1 second, since we sleep for 4s before SIGKILL)
        if let hangInfo = hangInfo {
            let durationSeconds = Double(hangInfo.hangEndNanos - hangInfo.hangStartNanos) / 1_000_000_000.0
            XCTAssertGreaterThan(durationSeconds, 1.0, "Hang duration should be at least 1 second")

            // Transition states should be present
            XCTAssertNotNil(hangInfo.hangStartTransitionState, "Start transition state should be present")
            XCTAssertNotNil(hangInfo.hangEndTransitionState, "End transition state should be present")
        }

        // Verify we got a SIGKILL
        XCTAssertEqual(rawReport.crash.error.signal?.signal, 9, "Should be SIGKILL (signal 9)")

        let state = try readState()
        XCTAssertTrue(state.previousRunWasAbnormal)
        XCTAssertEqual(state.terminationReason, .hang)
    }

    func testWatchdogTimeoutHasThreads() throws {
        // Enable watchdog monitoring and trigger a simulated watchdog timeout
        try launchAndCrash(.other_watchdogTimeoutTermination) { config in
            config.isWatchdogEnabled = true
        }

        let rawReport = try readCrashReport {
            $0.report.monitorId == "Watchdog" && $0.crash.error.signal?.signal == UInt64(SIGKILL)
        }

        // Verify threads are present in the crash report
        let threads = rawReport.crash.threads
        XCTAssertNotNil(threads, "Threads should be present in crash report")
        XCTAssertGreaterThan(threads?.count ?? 0, 0, "Should have at least one thread")

        // Find the crashed/main thread
        let crashedThread = threads?.first(where: { $0.crashed })
        XCTAssertNotNil(crashedThread, "Should have a crashed thread")

        // Verify the crashed thread has a backtrace with frames
        let backtrace = crashedThread?.backtrace
        XCTAssertNotNil(backtrace, "Crashed thread should have a backtrace")
        XCTAssertGreaterThan(
            backtrace?.contents.count ?? 0, 0, "Backtrace should have at least one frame")
    }

    func testAppHangFinalizedMidRun() throws {
        // Trigger a temporary hang that recovers. The watchdog detects
        // the hang, writes a report, and when the main thread resumes
        // finalization stitches the report in-place during the same launch.
        var installConfig = InstallConfig(namespace: "IntegrationTests", basePath: installUrl.path)
        installConfig.isWatchdogEnabled = true
        installConfig.isHangReportingEnabled = true
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            crash: .init(triggerId: .other_appHang),
            install: installConfig,
            config: .init(delay: actionDelay, stateSavePath: stateUrl.path)
        )
        launchAppAndRunScript()

        // The report file appears as soon as the hang is detected (before
        // recovery), so wait for the finalized report of this hang.
        let reportData = try readRawCrashReportData(timeout: actionDelay + 20.0) { Self.isTriggeredHang($0) }
        let report = try decodeCrashReport(reportData: reportData)

        XCTAssertEqual(report.crash.error.type, .hang)
        XCTAssertEqual(report.crash.error.isFatal, false)
        XCTAssertNil(report.crash.error.signal, "Recovered hang should not have signal info")

        let hangInfo = report.crash.error.hang
        XCTAssertNotNil(hangInfo)
        XCTAssertEqual(hangInfo?.hangRecovered, true)
        XCTAssertNotNil(hangInfo?.hangStartNanos)
        XCTAssertNotNil(hangInfo?.hangEndNanos)

        if let hangInfo {
            let durationSeconds =
                Double(hangInfo.hangEndNanos - hangInfo.hangStartNanos) / 1_000_000_000.0
            XCTAssertGreaterThan(durationSeconds, 0.25, "Hang should exceed the watchdog threshold")

            // Transition states should be present
            XCTAssertNotNil(hangInfo.hangStartTransitionState, "Start transition state should be present")
            XCTAssertNotNil(hangInfo.hangEndTransitionState, "End transition state should be present")
        }
    }

    // macOS sets Active during +load (before any observer registers), so
    // there is no pre-Active startup phase for the suppression boundary to
    // detect. This test is only meaningful on iOS/tvOS where the app
    // transitions through Launching -> Active via UIKit notifications.
    func testStartupHangIsSuppressed() throws {
        try XCTSkipUnless(
            [.iOS, .tvOS].contains(TargetPlatform.current),
            "Only iOS and tvOS have a pre-Active startup phase for the suppression boundary")
        // Trigger a hang during app init (before UIApplicationDidBecomeActive).
        // The watchdog detects and writes a report, but since the hang started
        // before Active, the report should be deleted on recovery.
        var installConfig = InstallConfig(namespace: "IntegrationTests", basePath: installUrl.path)
        installConfig.isWatchdogEnabled = true
        installConfig.isHangReportingEnabled = true
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            crash: .init(triggerId: .other_appHang),
            install: installConfig,
            config: .init(delay: 0, stateSavePath: stateUrl.path, runEarly: true)
        )
        launchAppAndRunScript()

        // The report must appear and then go: a watchdog that never noticed the hang would
        // leave no report either. It exists for most of the two-second hang, so a tight poll
        // sees it.
        // A stall after launch on a loaded simulator is a real hang that hang reporting keeps,
        // finalized and short, so the test watches only for a report still in progress or
        // the finalized two-second trigger.
        let isStartupHangReport: (Report) -> Bool = {
            $0.report.monitorId == "Watchdog" && ($0.report.finalized != true || Self.isTriggeredHang($0))
        }
        let deadline = Date().addingTimeInterval(appLaunchTimeout)
        var sawReport = false
        while !sawReport, Date() < deadline {
            sawReport = try hasReport(attachingListing: false, where: isStartupHangReport)
            if !sawReport { Thread.sleep(forTimeInterval: 0.02) }
        }
        if !sawReport { try attachReportListing() }
        XCTAssertTrue(sawReport, "The watchdog never reported the startup hang")

        // A startup hang report is created during detection but deleted on recovery.
        let goneDeadline = Date().addingTimeInterval(10.0)
        while try hasReport(attachingListing: false, where: isStartupHangReport), Date() < goneDeadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(try hasReport(where: isStartupHangReport), "Startup hang should be suppressed")
    }

    func testANormalExitDuringAHangLeavesNoReportWhenHangReportingIsOff() throws {
        // A slow quit: the app exits normally while the main thread is still hung. With
        // hang reporting off the hang did not end the app, so it has no report of its own,
        // but the run still ended with a hang in progress.
        try launchAndCrash(.other_hangThenExit) { config in
            config.isWatchdogEnabled = true
            config.isHangReportingEnabled = false
        }
        XCTAssertFalse(try hasReport { $0.report.monitorId == "Watchdog" }, "The hang should have no report")

        try launchAndInstall { config in
            config.isWatchdogEnabled = true
        }
        let state = try readState()
        XCTAssertEqual(state.terminationReason, .hang)
        XCTAssertTrue(state.previousRunWasAbnormal)
    }

    func testAHangThatRecoversLeavesNoReportWhenHangReportingIsOff() throws {
        // With hang reporting off, a hang that recovers has no report of its own: the report
        // written while it was in progress is deleted when it ends, not finalized. The trigger
        // returns after the hang has ended, and the run loop has turned since.
        try launchAndRunTrigger(.other_appHang) { config in
            config.isWatchdogEnabled = true
            config.isHangReportingEnabled = false
        }
        XCTAssertFalse(try hasReport { Self.isTriggeredHang($0) }, "The recovered hang should have no report")
    }

    /// Whether `report` is the finalized report of the hang the test triggered. A loaded
    /// simulator can also hang at launch, and that report is real, so the test tells its own
    /// apart by length as well: the trigger blocks the main thread for two seconds, a launch
    /// hang for well under one.
    nonisolated private static func isTriggeredHang(_ report: Report) -> Bool {
        guard report.report.finalized == true, let hang = report.crash.error.hang else { return false }
        return hang.hangEndNanos > hang.hangStartNanos && hang.hangEndNanos - hang.hangStartNanos > 1_500_000_000
    }

    func testExceptionDuringHangReportsTheException() throws {
        // Trigger a hang, then throw an exception while hung. The exception is what ended
        // the run. With hang reporting off, the hang is not reported on its own, since it
        // did not end the app; the exception's report carries it.
        try launchAndCrash(.other_watchdogTimeoutWithException) { config in
            config.isWatchdogEnabled = true
        }
        XCTAssertFalse(try hasReport { $0.report.monitorId == "Watchdog" }, "The hang's own report should be gone")

        // Re-launch and read through the report store so the sidecar stitch runs
        let reportData = try launchAndReportCrashRaw(where: { $0.crash.error.type == .nsexception }) { config in
            config.isWatchdogEnabled = true
        }
        let rawReport = try JSONDecoder().decode(Report.self, from: reportData)

        XCTAssertEqual(rawReport.crash.error.type, .nsexception, "Should be an NSException crash")
        XCTAssertEqual(
            rawReport.crash.error.reason, "Exception during hang",
            "Should have the exception reason")

        // Hang context is present from the run sidecar: a hang was in progress when the
        // exception fired.
        let hangInfo = rawReport.crash.error.hang
        XCTAssertNotNil(hangInfo, "Hang context should be present from the run sidecar")
        XCTAssertEqual(hangInfo?.hangRecovered, false, "The hang was still in progress")

        let state = try readState()
        XCTAssertTrue(state.previousRunWasAbnormal)
        XCTAssertEqual(state.terminationReason, .crash)
    }

    func testExceptionDuringHangAlsoReportsTheHangWhenHangReportingIsOn() throws {
        // With hang reporting on, the hang the exception cut short is reported too: as a hang
        // still in progress, not as what ended the app.
        try launchAndCrash(.other_watchdogTimeoutWithException) { config in
            config.isWatchdogEnabled = true
            config.isHangReportingEnabled = true
        }

        let hangData = try launchAndReportCrashRaw(where: {
            $0.report.monitorId == "Watchdog" && $0.crash.error.hang?.hangRecovered == false
        }) { config in
            config.isWatchdogEnabled = true
            config.isHangReportingEnabled = true
        }
        let hangReport = try decodeCrashReport(reportData: hangData)
        XCTAssertEqual(hangReport.crash.error.type, .hang)
        XCTAssertEqual(hangReport.crash.error.isFatal, false, "The exception ended the run, not the hang")
        XCTAssertNil(hangReport.crash.error.signal)

        let exceptionData = try readDeliveredReportData { $0.crash.error.type == .nsexception }
        XCTAssertEqual(try decodeCrashReport(reportData: exceptionData).crash.error.hang?.hangRecovered, false)

        let state = try readState()
        XCTAssertEqual(state.terminationReason, .crash)
    }
}
