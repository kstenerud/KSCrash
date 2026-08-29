//
//  SessionTests.swift
//
//  Created by Alexander Cohen on 2026-08-01.
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

import KSCrashRecording
import KSCrashReportModel
import XCTest

final class SessionTests: IntegrationTestBase {

    // A run that reaches the foreground records a session, and the crash report
    // for that run carries its last session id. session_id is added when the
    // store reads (stitches) the report for delivery, so the assertion runs
    // against the delivered report, not the raw on-disk one.
    func testDeliveredReportCarriesSessionID() throws {
        try launchAndCrash(.nsException_genericNSException)

        let deliveredData = try launchAndReportCrashRaw()
        let delivered = try decodeCrashReport(reportData: deliveredData)

        let sessionID = try XCTUnwrap(delivered.report.sessionId, "delivered report should carry a session_id")
        XCTAssertNotNil(UUID(uuidString: sessionID), "session_id should be a valid UUID, got \(sessionID)")
    }

    // The raw report written at crash time has no session id; it appears only
    // after the store stitches the report. This locks in the stitch-time
    // contract so the field can't silently start leaking into raw reports.
    func testRawReportHasNoSessionIDBeforeStitch() throws {
        try launchAndCrash(.nsException_genericNSException)

        let rawReport = try readCrashReport()
        XCTAssertNil(rawReport.report.sessionId, "session_id is a stitch-time field, absent from the raw report")
    }

    // A crashed run's summary is persisted on the next launch and records the
    // crash outcome.
    func testRunSummaryPersistedForCrashedRun() throws {
        try launchAndCrash(.nsException_genericNSException)  // run A crashes
        try launchAndInstall()  // run B installs and persists run A's summary

        let runsDir = try runsDirectoryUrl()
        let runFiles = try FileManager.default.contentsOfDirectory(atPath: runsDir.path).filter {
            $0.hasSuffix(".run")
        }
        XCTAssertEqual(runFiles.count, 1, "exactly one run summary should be persisted for the crashed run")

        let data = try Data(contentsOf: runsDir.appendingPathComponent(try XCTUnwrap(runFiles.first)))
        let summary = try JSONDecoder().decode(RunSummary.self, from: data)
        XCTAssertEqual(summary.outcome.terminationReason, .crash)
    }
}
