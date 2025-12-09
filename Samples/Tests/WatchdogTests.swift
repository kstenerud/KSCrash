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

            let rawReport = try readPartialCrashReport()

            // Verify hang info is present in the crash report
            let hangInfo = rawReport.crash?.error?.hang
            XCTAssertNotNil(hangInfo, "Hang info should be present in crash report")
            XCTAssertNotNil(hangInfo?.hang_start_nanos, "Hang start timestamp should be present")
            XCTAssertNotNil(hangInfo?.hang_end_nanos, "Hang end timestamp should be present")

            // Verify the hang duration is reasonable (at least 1 second, since we sleep for 4s before SIGKILL)
            if let startNanos = hangInfo?.hang_start_nanos,
                let endNanos = hangInfo?.hang_end_nanos
            {
                let durationSeconds = Double(endNanos - startNanos) / 1_000_000_000.0
                XCTAssertGreaterThan(durationSeconds, 1.0, "Hang duration should be at least 1 second")
            }

            // Verify we got a SIGKILL
            XCTAssertEqual(rawReport.crash?.error?.signal?.signal, 9, "Should be SIGKILL (signal 9)")
        }
    }

#endif
