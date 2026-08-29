//
//  KSCrashRuntimeTests.swift
//
//  Created by Alexander Cohen on 2026-08-22.
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

import Foundation
import KSCrashRecording
import KSCrashRecordingCore
import KSCrashReportModel
import XCTest

@testable import KSCrash

final class KSCrashRuntimeTests: XCTestCase {
    override func setUpWithError() throws {
        try TestInstall.ensure()
    }

    func test_runID_isThisRunsUUID() {
        XCTAssertEqual(KSCrash.shared.runID, RunSummary.ID(String(cString: kscrash_getRunID())))
    }

    func test_previousRunID_isNilOnAFirstLaunch() {
        // The test install's root is fresh, so there is no previous run.
        XCTAssertNil(KSCrash.shared.previousRunID)
    }

    func test_previousTerminationReason_isAReason() {
        let reason = KSCrash.shared.previousTerminationReason
        XCTAssertFalse(reason.isUnknown, "\(reason)")
        XCTAssertFalse(reason.isAbnormal, "a fresh root is a first launch: \(reason)")
    }

    func test_setUserID_cutsASession_andWritesTheUserKey() {
        KSCrash.shared.setUserID("alice")
        XCTAssertNotNil(KSCrash.shared.sessionID)
        XCTAssertEqual(KSCrash.shared.metadata[KSCRASH_USERID_KEY] as String?, "alice")
        KSCrash.shared.setUserID("bob")
        XCTAssertEqual(KSCrash.shared.metadata[KSCRASH_USERID_KEY] as String?, "bob")
        KSCrash.shared.setUserID(nil)
        XCTAssertNil(KSCrash.shared.metadata[KSCRASH_USERID_KEY] as String?)
    }

    func test_setUserID_overTheSessionLimit_truncatesOnACharacterBoundary() {
        let limit = Int(KSSESSION_MAX_USER_LENGTH) - 1
        KSCrash.shared.setUserID(String(repeating: "u", count: limit + 100))
        XCTAssertEqual(
            KSCrash.shared.metadata[KSCRASH_USERID_KEY] as String?, String(repeating: "u", count: limit))
        // A multi-byte character straddling the limit is dropped whole, so
        // the stored value stays valid UTF-8 and matches the session record.
        KSCrash.shared.setUserID(String(repeating: "a", count: limit - 1) + "🚗")
        XCTAssertEqual(
            KSCrash.shared.metadata[KSCRASH_USERID_KEY] as String?, String(repeating: "a", count: limit - 1))
        KSCrash.shared.setUserID(nil)
    }

    func test_registeredCMonitorPlugins_populateTheSystemFields() throws {
        let before = try Set(Store.listReportIDs(in: TestInstall.configuration.locations.reports))
        KSCrash.shared.reportException(
            "PluginFields", reason: nil, language: nil, lineOfCode: nil, stackTrace: nil,
            logAllThreads: false, terminateProgram: false)
        let report = try XCTUnwrap(addedUserReports(named: "PluginFields", notIn: before).first)
        // The shared install registers the DiscSpace and BootTime plugins.
        // boot_time is not asserted here: other suites in the aggregate
        // process re-point the System monitor's sidecar at their own files,
        // so the install's one-shot boot write is not reliably in the
        // stitched sidecar by the time this test reads a report. The chain
        // is covered piecewise: the plugin's recording hook in
        // SidecarMetadataMonitorPluginTests, the setter-to-sidecar write in
        // KSCrashMonitor_System_Tests, and the sidecar-to-field stitch in
        // KSCrashMonitor_SystemStitch_Tests.
        XCTAssertNotNil(report.system?.storage)
        XCTAssertNotNil(report.system?.freeStorage)
    }

    func test_didWriteReportCallback_firesWithTheReportID() throws {
        didWriteWitness = nil
        KSCrash.shared.reportException(
            "DidWriteWitness", reason: nil, language: nil, lineOfCode: nil, stackTrace: nil,
            logAllThreads: false, terminateProgram: false)
        let witness = try XCTUnwrap(didWriteWitness, "the did-write callback fired")
        XCTAssertNotNil(UUID(uuidString: witness), witness)
    }

    func test_reportException_writesAReport() throws {
        let before = try Set(Store.listReportIDs(in: TestInstall.configuration.locations.reports))
        KSCrash.shared.reportException(
            "TestException", reason: "on purpose", language: "swift", lineOfCode: nil,
            stackTrace: ["frame one", "frame two"], logAllThreads: false, terminateProgram: false)
        XCTAssertEqual(try addedUserReports(named: "TestException", notIn: before).count, 1)
    }

    /// The new user reports carrying `name`, picked out by content: the
    /// watchdog writes and deletes transient hang reports on its own thread
    /// whenever the main thread stalls past its threshold, so directory
    /// counts and arbitrary picks from the added set are not stable.
    private func addedUserReports(named name: String, notIn before: Set<Report.ID>) throws -> [Report] {
        let reportsDirectory = try TestInstall.configuration.locations.reports
        let store = try XCTUnwrap(KSCrash.makeStore())
        let added = Set(try Store.listReportIDs(in: reportsDirectory)).subtracting(before)
        return added.compactMap { try? store.report($0) }
            .filter { $0.crash.error.userReported?.name == name }
    }
}
