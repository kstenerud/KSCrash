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
        let reportData = try readRawCrashReportData(timeout: actionDelay + 20.0) {
            Self.isTriggeredHang($0, duringStartup: false)
        }
        let report = try decodeCrashReport(reportData: reportData)

        XCTAssertEqual(report.crash.error.type, .hang)
        XCTAssertEqual(report.crash.error.hang?.duringStartup, false)
        XCTAssertEqual(report.crash.error.hang?.hangStartTransitionState, .active)
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
    // there is no pre-Active startup phase to hang in. On iOS/tvOS the app
    // transitions through Launching -> Active via UIKit notifications.
    func testStartupHangIsReported() throws {
        try XCTSkipUnless(
            [.iOS, .tvOS].contains(TargetPlatform.current),
            "Only iOS and tvOS have a pre-Active startup phase")
        // Trigger a hang during app init (before UIApplicationDidBecomeActive).
        // A hang there is reported like any other, and says it started during
        // startup.
        var installConfig = InstallConfig(namespace: "IntegrationTests", basePath: installUrl.path)
        installConfig.isWatchdogEnabled = true
        installConfig.isHangReportingEnabled = true
        app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
            crash: .init(triggerId: .other_appHang),
            install: installConfig,
            config: .init(delay: 0, stateSavePath: stateUrl.path, runEarly: true)
        )
        launchAppAndRunScript()

        let reportData = try readRawCrashReportData(timeout: appLaunchTimeout + 20.0) {
            Self.isTriggeredHang($0, duringStartup: true)
        }
        let report = try decodeCrashReport(reportData: reportData)

        XCTAssertEqual(report.crash.error.type, .hang)
        XCTAssertEqual(report.crash.error.hang?.hangRecovered, true)
        XCTAssertEqual(report.crash.error.hang?.duringStartup, true)
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

    func testANormalExitDuringAHangReportsTheHangWhenHangReportingIsOn() throws {
        // The same slow quit with hang reporting on: the hang is reported as still in
        // progress, not as what ended the app, since the app exited on its own.
        try launchAndCrash(.other_hangThenExit) { config in
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
        XCTAssertEqual(hangReport.crash.error.isFatal, false, "The app exited on its own, not by a watchdog kill")
        XCTAssertNil(hangReport.crash.error.signal)

        let state = try readState()
        XCTAssertEqual(state.terminationReason, .hang)
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
    /// hang for well under one. A nil `duringStartup` matches a hang whenever it started.
    nonisolated private static func isTriggeredHang(_ report: Report, duringStartup: Bool? = nil) -> Bool {
        guard report.report.finalized == true, let hang = report.crash.error.hang,
            duringStartup == nil || hang.duringStartup == duringStartup
        else { return false }
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
