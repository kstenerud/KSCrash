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
import Report
import XCTest

#if !os(watchOS)

    final class WatchdogTests: IntegrationTestBase {

        override func setUpWithError() throws {
            try super.setUpWithError()
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
            let rawReport = try JSONDecoder().decode(CrashReport<NoUserData>.self, from: reportData)

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
            XCTAssertTrue(state.crashedLastLaunch)
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
            var installConfig = InstallConfig(installPath: installUrl.path)
            installConfig.isWatchdogEnabled = true
            installConfig.isHangReportingEnabled = true
            app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
                crash: .init(triggerId: .other_appHang),
                install: installConfig,
                config: .init(delay: actionDelay, stateSavePath: stateUrl.path)
            )
            launchAppAndRunScript()

            // The report file appears as soon as the hang is detected (before
            // recovery), so wait specifically for the finalized flag.
            let reportsDirUrl = installUrl.appendingPathComponent("Reports")
            let finalizedExpectation = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    guard let files = try? FileManager.default.contentsOfDirectory(atPath: reportsDirUrl.path),
                        let fileName = files.first,
                        let data = try? Data(contentsOf: reportsDirUrl.appendingPathComponent(fileName)),
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let report = json["report"] as? [String: Any]
                    else { return false }
                    return report["finalized"] as? Bool == true
                },
                object: nil
            )
            wait(for: [finalizedExpectation], timeout: actionDelay + 20.0)

            let reportData = try readRawCrashReportData()
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
        #if os(iOS) || os(tvOS)
            func testStartupHangIsSuppressed() throws {
                // Trigger a hang during app init (before UIApplicationDidBecomeActive).
                // The watchdog detects and writes a report, but since the hang started
                // before Active, the report should be deleted on recovery.
                var installConfig = InstallConfig(installPath: installUrl.path)
                installConfig.isWatchdogEnabled = true
                installConfig.isHangReportingEnabled = true
                app.launchEnvironment[IntegrationTestRunner.envKey] = try IntegrationTestRunner.script(
                    crash: .init(triggerId: .other_appHang),
                    install: installConfig,
                    config: .init(delay: 0, stateSavePath: stateUrl.path, runEarly: true)
                )
                launchAppAndRunScript()

                // Wait for the hang to resolve and any reports to be cleaned up.
                // A startup hang report is created during detection but deleted on
                // recovery, so the Reports directory should end up empty.
                let reportsDirUrl = installUrl.appendingPathComponent("Reports")
                let emptyExpectation = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in
                        guard let files = try? FileManager.default.contentsOfDirectory(atPath: reportsDirUrl.path)
                        else { return true }
                        return files.isEmpty
                    },
                    object: nil
                )
                wait(for: [emptyExpectation], timeout: 10.0)

                let files = (try? FileManager.default.contentsOfDirectory(atPath: reportsDirUrl.path)) ?? []
                XCTAssertTrue(files.isEmpty, "Startup hang should be suppressed, but found reports: \(files)")
            }
        #endif

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
            let rawReport = try JSONDecoder().decode(CrashReport<NoUserData>.self, from: reportData)

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
            XCTAssertTrue(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .crash)
        }
    }

#endif
