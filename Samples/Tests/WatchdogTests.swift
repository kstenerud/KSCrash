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
            }

            // Verify we got a SIGKILL
            XCTAssertEqual(rawReport.crash.error.signal?.signal, 9, "Should be SIGKILL (signal 9)")
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

            // Verify hang info is NOT present - the fatal exception takes precedence
            let hangInfo = rawReport.crash.error.hang
            XCTAssertNil(hangInfo, "Hang info should NOT be present when a fatal exception occurred")
        }
    }

#endif
