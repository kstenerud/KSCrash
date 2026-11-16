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
        let reportData = try launchAndReportCrashRaw { config in
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

        let rawReport = try readCrashReport()

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

    /// Whether `report` is the finalized report of the hang the test triggered. A loaded
    /// simulator can also hang at launch, and that report is real, so the test tells its own
    /// apart by length as well: the trigger blocks the main thread for two seconds, a launch
    /// hang for well under one.
    nonisolated private static func isTriggeredHang(_ report: [String: Any], duringStartup: Bool) -> Bool {
        guard (report["report"] as? [String: Any])?["finalized"] as? Bool == true,
            let hang = ((report["crash"] as? [String: Any])?["error"] as? [String: Any])?["hang"]
                as? [String: Any],
            hang["during_startup"] as? Bool == duringStartup,
            let start = (hang["hang_start_nanos"] as? NSNumber)?.uint64Value,
            let end = (hang["hang_end_nanos"] as? NSNumber)?.uint64Value
        else { return false }
        return end > start && end - start > 1_500_000_000
    }

    func testExceptionDuringHangReportsExceptionNotHang() throws {
        // Trigger a hang, then throw an exception while hung.
        // The fatal exception should be reported, not the hang.
        try launchAndCrash(.other_watchdogTimeoutWithException) { config in
            config.isWatchdogEnabled = true
        }

        // Re-launch and read through the report store so the sidecar stitch runs
        let reportData = try launchAndReportCrashRaw { config in
            config.isWatchdogEnabled = true
        }
        let rawReport = try JSONDecoder().decode(Report.self, from: reportData)

        // Verify we got an NSException, not a hang/signal
        XCTAssertEqual(rawReport.crash.error.type, .nsexception, "Should be an NSException crash")
        XCTAssertEqual(
            rawReport.crash.error.reason, "Exception during hang",
            "Should have the exception reason")

        // Hang context is present from the run sidecar, providing diagnostic
        // context that a hang was active when the exception fired.
        let hangInfo = rawReport.crash.error.hang
        XCTAssertNotNil(hangInfo, "Hang context should be present from the run sidecar")
        XCTAssertNil(hangInfo?.hangRecovered, "Hang should not be marked as recovered")

        let state = try readState()
        XCTAssertTrue(state.previousRunWasAbnormal)
        XCTAssertEqual(state.terminationReason, .crash)
    }
}
