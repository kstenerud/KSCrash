//
//  RunDataStoreTests.swift
//
//  Created by Alexander Cohen on 2026-08-09.
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

import KSCrashRecordingCore
import XCTest

@testable import KSCrash

final class RunDataStoreTests: XCTestCase {

    private var runsDirectory: URL!
    private var sidecarsDirectory: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RunDataStoreTests-\(UUID().uuidString)")
        runsDirectory = base.appendingPathComponent("Runs")
        sidecarsDirectory = base.appendingPathComponent("RunSidecars")
        try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sidecarsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: runsDirectory.deletingLastPathComponent())
    }

    // MARK: - Helpers

    private func makeStore(maxRunCount: Int = 50, liveRunID: String? = nil) -> RunDataStore {
        RunDataStore(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: sidecarsDirectory,
            maxRunCount: maxRunCount,
            liveRunID: liveRunID
        )
    }

    private func makeSummary(runID: String, startedAtMs: Int64 = 1_000, endedAtMs: Int64 = 2_000) -> RunSummary {
        RunSummary(
            schemaVersion: 1,
            sdkVersion: "test",
            runID: runID,
            deviceID: "device",
            startedAtMs: startedAtMs,
            endedAtMs: endedAtMs,
            isBeingDebugged: false,
            outcome: .init(terminationReason: .clean, userPerceptible: false),
            durations: .init(activeMs: 0, backgroundMs: 0),
            sessions: .init(records: []),
            app: .init(bundleID: "bundle", version: "1", shortVersion: "1", hostKind: .app),
            os: .init(name: "os", version: "1", build: "1"),
            device: .init(
                model: "model", modelFamily: "family", architecture: "arch",
                binaryArchitecture: "arch", isTranslated: false, isJailbroken: false)
        )
    }

    @discardableResult
    private func writeSummary(_ summary: RunSummary, startNs: UInt64) throws -> URL {
        let url = runsDirectory.appendingPathComponent(String(format: "%019llu.run", startNs))
        try JSONEncoder().encode(summary).write(to: url)
        return url
    }

    private func writeSessions(runID: String, cuts: [(perceptible: Bool, user: String?)]) {
        let writer = kssw_open(runsDirectory.appendingPathComponent("\(runID).sessions").path)
        for cut in cuts {
            kssw_update(writer, cut.perceptible, cut.user)
            usleep(2000)  // space session starts so start times strictly increase
        }
        kssw_close(writer)
    }

    private func writeUserInfo(runID: String, _ populate: (OpaquePointer) -> Void) throws {
        let directory = sidecarsDirectory.appendingPathComponent(runID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = KSKVSConfig(initialCapacity: 4096, maxKeyLength: 256, maxStringLength: 1024)
        let store = kskvs_create(
            directory.appendingPathComponent(KSCRS_USERINFO_RUN_SIDECAR_FILENAME).path, KSKVSModeReadWriteCreate,
            &config)
        XCTAssertNotNil(store)
        populate(store!)
        kskvs_destroy(store)
    }

    // MARK: - Snapshot

    func test_runs_missingDirectory_isEmpty() throws {
        try FileManager.default.removeItem(at: runsDirectory)
        XCTAssertEqual(try makeStore().runs().count, 0)
    }

    func test_runs_missingSidecarsDirectory_isEmptyNotAnError() throws {
        try writeSummary(makeSummary(runID: "NOSIDE"), startNs: 100)
        try FileManager.default.removeItem(at: sidecarsDirectory)
        let runs = try makeStore().runs()
        XCTAssertEqual(runs.count, 1)
        XCTAssertNil(runs[0].sidecarDirectory)
    }

    func test_runs_throwsWhenSidecarsDirectoryUnreadable() throws {
        try writeSummary(makeSummary(runID: "ANY"), startNs: 100)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: sidecarsDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sidecarsDirectory.path)
        }
        // Unreadable is a broken store, not "no sidecars": mistaking it for
        // absence would deliver pending summaries without their metadata and
        // let reclaim drop the still-present sidecars.
        XCTAssertThrowsError(try makeStore().runs())
    }

    func test_runs_ordersNewestFirst() throws {
        try writeSummary(makeSummary(runID: "AAA"), startNs: 100)
        try writeSummary(makeSummary(runID: "BBB"), startNs: 300)
        try writeSummary(makeSummary(runID: "CCC"), startNs: 200)

        let runs = try makeStore().runs()
        XCTAssertEqual(runs.map(\.runID), ["BBB", "CCC", "AAA"])
    }

    func test_runs_groupsArtifactsByRunID() throws {
        let runID = "11111111-2222-3333-4444-555555555555"
        try writeSummary(makeSummary(runID: runID), startNs: 100)
        writeSessions(runID: runID, cuts: [(true, nil)])
        try writeUserInfo(runID: runID) { kskvs_setString($0, "k", "v") }

        let runs = try makeStore().runs()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].runID, runID)
        XCTAssertEqual(runs[0].summaryFiles.count, 1)
        XCTAssertNotNil(runs[0].sessionsFile)
        XCTAssertNotNil(runs[0].sidecarDirectory)
    }

    func test_runs_includesArtifactOnlyRuns_afterSummaryRuns() throws {
        try writeSummary(makeSummary(runID: "WITHSUMMARY"), startNs: 100)
        writeSessions(runID: "ORPHAN", cuts: [(true, nil)])

        let runs = try makeStore().runs()
        XCTAssertEqual(runs.map(\.runID), ["WITHSUMMARY", "ORPHAN"])
        XCTAssertNil(runs[1].summary())
    }

    func test_runs_excludesLiveRun_evenArtifactOnly() throws {
        try writeSummary(makeSummary(runID: "DEAD"), startNs: 100)
        try writeSummary(makeSummary(runID: "LIVE"), startNs: 200)
        writeSessions(runID: "LIVEORPHAN", cuts: [(true, nil)])

        XCTAssertEqual(try makeStore(liveRunID: "LIVE").runs().map(\.runID), ["DEAD", "LIVEORPHAN"])
        XCTAssertEqual(try makeStore(liveRunID: "LIVEORPHAN").runs().map(\.runID), ["LIVE", "DEAD"])
    }

    func test_runs_skipsCorruptAndRunIDLessSummaries() throws {
        try Data("not json".utf8).write(to: runsDirectory.appendingPathComponent("0000000000000000050.run"))
        try writeSummary(makeSummary(runID: ""), startNs: 100)
        try writeSummary(makeSummary(runID: "GOOD"), startNs: 200)

        let runs = try makeStore().runs()
        XCTAssertEqual(runs.map(\.runID), ["GOOD"])
        // Skipped files stay on disk for pruning.
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: runsDirectory.path).filter { $0.hasSuffix(".run") }
                .count, 3)
    }

    func test_runs_duplicateRunID_oneStoreNewestSummary() throws {
        try writeSummary(makeSummary(runID: "DUP", startedAtMs: 1), startNs: 100)
        try writeSummary(makeSummary(runID: "DUP", startedAtMs: 2), startNs: 200)

        let runs = try makeStore().runs()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].summaryFiles.count, 2)
        XCTAssertEqual(runs[0].summary()?.startedAtMs, 2)

        try runs[0].removeSummary()
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: runsDirectory.path).filter { $0.hasSuffix(".run") }
                .count, 0)
    }

    // MARK: - Prune

    func test_runs_prunesOldestBeyondMaxRunCount() throws {
        for ns in [100, 200, 300, 400] as [UInt64] {
            try writeSummary(makeSummary(runID: "RUN\(ns)"), startNs: ns)
        }
        // Legacy unpadded filenames parse by value, so this is the oldest.
        try JSONEncoder().encode(makeSummary(runID: "LEGACY")).write(
            to: runsDirectory.appendingPathComponent("5.run"))
        try Data("x".utf8).write(to: runsDirectory.appendingPathComponent("notdigits.run"))

        let runs = try makeStore(maxRunCount: 2).runs()
        XCTAssertEqual(runs.map(\.runID), ["RUN400", "RUN300"])
        let remaining = try FileManager.default.contentsOfDirectory(atPath: runsDirectory.path).sorted()
        // Oldest three writer-named files pruned; the non-writer-named file is untouched.
        XCTAssertEqual(remaining, ["0000000000000000300.run", "0000000000000000400.run", "notdigits.run"])
    }

    func test_runs_pruneDisabled_keepsEverything() throws {
        for ns in [100, 200, 300] as [UInt64] {
            try writeSummary(makeSummary(runID: "RUN\(ns)"), startNs: ns)
        }
        XCTAssertEqual(try makeStore(maxRunCount: 0).runs().count, 3)
    }

    // MARK: - Sessions merge

    func test_summary_mergesSessionRecords() throws {
        let runID = "MERGE"
        try writeSummary(makeSummary(runID: runID, endedAtMs: .max), startNs: 100)
        writeSessions(runID: runID, cuts: [(true, nil), (true, "alice"), (false, "alice")])

        let summary = try XCTUnwrap(makeStore().runs()[0].summary())
        let records = summary.sessions.records
        XCTAssertEqual(records.count, 3)

        XCTAssertNil(records[0].userID)
        XCTAssertEqual(records[1].userID, "alice")
        XCTAssertEqual(records[2].userID, "alice")
        XCTAssertTrue(records[0].perceptible)
        XCTAssertTrue(records[1].perceptible)
        XCTAssertFalse(records[2].perceptible)

        // Each session ends where the next begins; the open final session's end
        // comes from the run's end, floored to its start.
        XCTAssertEqual(records[0].endedAtMs, records[1].startedAtMs)
        XCTAssertEqual(records[1].endedAtMs, records[2].startedAtMs)
        XCTAssertEqual(records[2].endedAtMs, .max)
    }

    func test_summary_finalSessionEnd_flooredToItsStart() throws {
        let runID = "FLOOR"
        // A run end far in the past: the floor keeps the end at the session start.
        try writeSummary(makeSummary(runID: runID, endedAtMs: 0), startNs: 100)
        writeSessions(runID: runID, cuts: [(true, nil)])

        let record = try XCTUnwrap(makeStore().runs()[0].summary()?.sessions.records.first)
        XCTAssertEqual(record.endedAtMs, record.startedAtMs)
    }

    func test_summary_skipsSessionRecordWithCorruptGUID() throws {
        let runID = "CORRUPTGUID"
        try writeSummary(makeSummary(runID: runID, endedAtMs: .max), startNs: 100)
        writeSessions(runID: runID, cuts: [(true, nil), (true, "alice")])

        // Append a raw entry whose guid is not valid UTF-8; its start must not
        // regress, so use a far-future monotonic value.
        let sessionsPath = runsDirectory.appendingPathComponent("\(runID).sessions").path
        var badGUID: [CChar] = [CChar(bitPattern: 0xC3), CChar(bitPattern: 0x28), 0]
        kssession_testcode_appendRawEntry(sessionsPath, UInt64.max / 2, true, &badGUID, "bob", false)

        let records = try XCTUnwrap(makeStore().runs()[0].summary()).sessions.records
        // The corrupt record is dropped; the valid ones survive, and the last
        // valid one's end still comes from its (corrupt) successor's start,
        // not from the run's end (which would be .max here).
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[1].userID, "alice")
        XCTAssertNotEqual(records[1].endedAtMs, .max)
    }

    func test_summary_sessionUserWithoutTerminator_isTruncatedNotRejected() throws {
        let runID = "NONULUSER"
        try writeSummary(makeSummary(runID: runID, endedAtMs: .max), startNs: 100)

        let sessionsPath = runsDirectory.appendingPathComponent("\(runID).sessions").path
        let writer = kssw_open(sessionsPath)
        kssw_update(writer, true, nil)
        kssw_close(writer)
        kssession_testcode_appendRawEntry(
            sessionsPath, UInt64.max / 2, true, "AAAA1111-2222-3333-4444-555555555555", nil, true)

        let records = try XCTUnwrap(makeStore().runs()[0].summary()).sessions.records
        XCTAssertEqual(records.count, 2)
        // 128 un-terminated bytes on disk; the reader's forced terminator caps
        // the user at 127 characters.
        XCTAssertEqual(records[1].userID, String(repeating: "A", count: 127))
    }

    func test_summary_unreadableSessionsFile_skipsTheRunInsteadOfShippingEmpty() throws {
        let runID = "UNREADABLE"
        try writeSummary(makeSummary(runID: runID), startNs: 100)
        writeSessions(runID: runID, cuts: [(true, "alice")])

        let sessionsPath = runsDirectory.appendingPathComponent("\(runID).sessions").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: sessionsPath)

        // Unreadable is unknown, not absent: delivering would ship empty
        // records and then destroy the intact file.
        XCTAssertNil(try makeStore().runs()[0].summary())

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: sessionsPath)
        let records = try XCTUnwrap(makeStore().runs()[0].summary()).sessions.records
        XCTAssertEqual(records.map(\.userID), ["alice"])
    }

    func test_summary_withoutSessionsFile_keepsEmptyRecords() throws {
        try writeSummary(makeSummary(runID: "NOSESSIONS"), startNs: 100)
        let summary = try XCTUnwrap(makeStore().runs()[0].summary())
        XCTAssertEqual(summary.sessions.records.count, 0)
    }

    // MARK: - Metadata stitch

    func test_summary_stitchesMetadataFromUserInfoSidecar() throws {
        let runID = "STITCH"
        try writeSummary(makeSummary(runID: runID), startNs: 100)
        try writeUserInfo(runID: runID) { store in
            kskvs_setString(store, "name", "alice")
            kskvs_setInt64(store, "count", -42)
            kskvs_setUInt64(store, "big", 42)
            kskvs_setDouble(store, "ratio", 0.5)
            kskvs_setBool(store, "flag", true)
            kskvs_setDate(store, "when", 1_700_000_000_000_000_000)
            kskvs_setString(store, "gone", "x")
            kskvs_removeValue(store, "gone")
        }

        let metadata = try XCTUnwrap(makeStore().runs()[0].summary()?.metadata)
        XCTAssertEqual(metadata.value(forKey: "name", as: String.self), "alice")
        XCTAssertEqual(metadata.value(forKey: "count", as: Int64.self), -42)
        XCTAssertEqual(metadata.value(forKey: "big", as: UInt64.self), 42)
        XCTAssertEqual(metadata.value(forKey: "ratio", as: Double.self), 0.5)
        XCTAssertEqual(metadata.value(forKey: "flag", as: Bool.self), true)
        XCTAssertEqual(
            try XCTUnwrap(metadata.value(forKey: "when", as: Date.self)).timeIntervalSince1970,
            1_700_000_000, accuracy: 0.001)
        XCTAssertFalse(metadata.contains("gone"))
    }

    func test_summary_metadata_dateMatchesUserInfoDateConversion() throws {
        let runID = "DATEMATCH"
        try writeSummary(makeSummary(runID: runID), startNs: 100)

        // Write with the exact conversion -[KSCrash setUserInfoDate:forKey:] uses.
        let original = Date(timeIntervalSince1970: 1_723_222_222.123456)
        let storedNs = UInt64(original.timeIntervalSince1970 * 1e9)
        try writeUserInfo(runID: runID) { kskvs_setDate($0, "when", storedNs) }

        let stitched = try XCTUnwrap(
            makeStore().runs()[0].summary()?.metadata?.value(forKey: "when", as: Date.self))
        // Identical to what the report userInfo stitch produces for the same key.
        XCTAssertEqual(stitched, Date(timeIntervalSince1970: Double(storedNs) / 1e9))
        XCTAssertEqual(stitched.timeIntervalSince1970, original.timeIntervalSince1970, accuracy: 1e-6)
    }

    func test_summary_metadata_nilWhenSidecarNetsEmpty() throws {
        let runID = "EMPTYBAG"
        try writeSummary(makeSummary(runID: runID), startNs: 100)
        try writeUserInfo(runID: runID) { store in
            kskvs_setString(store, "k", "v")
            kskvs_removeValue(store, "k")
        }
        let summary = try XCTUnwrap(makeStore().runs()[0].summary())
        XCTAssertNil(summary.metadata)
    }

    func test_summary_metadata_nilWithoutSidecar() throws {
        try writeSummary(makeSummary(runID: "BARE"), startNs: 100)
        let summary = try XCTUnwrap(makeStore().runs()[0].summary())
        XCTAssertNil(summary.metadata)
    }

    func test_summary_unreadableUserInfoSidecar_skipsTheRunInsteadOfDroppingMetadata() throws {
        let runID = "LOCKEDMETA"
        try writeSummary(makeSummary(runID: runID), startNs: 100)
        try writeUserInfo(runID: runID) { kskvs_setString($0, "k", "v") }

        let path = sidecarsDirectory.appendingPathComponent(runID)
            .appendingPathComponent(KSCRS_USERINFO_RUN_SIDECAR_FILENAME).path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)

        // Unreadable is unknown, not absent: delivering would ship the
        // summary without its metadata and then delete the intact `.run`.
        XCTAssertNil(try makeStore().runs()[0].summary())

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        let metadata = try XCTUnwrap(makeStore().runs()[0].summary()?.metadata)
        XCTAssertEqual(metadata.value(forKey: "k", as: String.self), "v")
    }

    // MARK: - Ownership

    func test_removeSummary_leavesSharedFilesAlone() throws {
        let runID = "OWNED"
        try writeSummary(makeSummary(runID: runID), startNs: 100)
        writeSessions(runID: runID, cuts: [(true, nil)])
        try writeUserInfo(runID: runID) { kskvs_setString($0, "k", "v") }

        let run = try makeStore().runs()[0]
        try run.removeSummary()

        XCTAssertFalse(FileManager.default.fileExists(atPath: run.summaryFiles[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(run.sessionsFile).path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(run.sidecarDirectory).appendingPathComponent(KSCRS_USERINFO_RUN_SIDECAR_FILENAME)
                    .path))

        // The next snapshot sees the run as artifact-only.
        let after = try makeStore().runs()
        XCTAssertEqual(after.count, 1)
        XCTAssertNil(after[0].summary())
    }

    func test_reclaimOrphans_invokesInjectedReclaim() {
        let called = expectation(description: "reclaim")
        let store = RunDataStore(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: sidecarsDirectory,
            maxRunCount: 1,
            liveRunID: nil
        ) { called.fulfill() }
        store.reclaimOrphans()
        wait(for: [called], timeout: 1)
    }
}
