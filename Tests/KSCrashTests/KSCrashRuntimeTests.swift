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
        let reportsDirectory = try TestInstall.configuration.locations.reports
        let before = Set(try Store.listReportIDs(in: reportsDirectory))
        KSCrash.shared.reportException(
            "PluginFields", reason: nil, language: nil, lineOfCode: nil, stackTrace: nil,
            logAllThreads: false, terminateProgram: false)
        let added = Set(try Store.listReportIDs(in: reportsDirectory)).subtracting(before)
        let id = try XCTUnwrap(added.first)
        let store = try XCTUnwrap(KSCrash.makeStore())
        let report = try XCTUnwrap(store.report(id))
        // The shared install registers the DiscSpace and BootTime plugins.
        XCTAssertNotNil(report.system?.storage)
        XCTAssertNotNil(report.system?.freeStorage)
        XCTAssertNotNil(report.system?.bootTime)
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
        let reportsDirectory = try TestInstall.configuration.locations.reports
        let before = try Store.listReportIDs(in: reportsDirectory)
        KSCrash.shared.reportException(
            "TestException", reason: "on purpose", language: "swift", lineOfCode: nil,
            stackTrace: ["frame one", "frame two"], logAllThreads: false, terminateProgram: false)
        let after = try Store.listReportIDs(in: reportsDirectory)
        XCTAssertEqual(after.count, before.count + 1)
    }
}
