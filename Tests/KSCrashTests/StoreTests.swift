//
//  StoreTests.swift
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

import KSCrashRecording
import KSCrashRecordingCore
import KSCrashSwiftCore
import XCTest

@testable import KSCrash

final class StoreTests: XCTestCase {

    private var runsDirectory: URL!
    private var sidecarsDirectory: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StoreTests-\(UUID().uuidString)")
        runsDirectory = base.appendingPathComponent("Runs")
        sidecarsDirectory = base.appendingPathComponent("RunSidecars")
        try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sidecarsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: runsDirectory.deletingLastPathComponent())
    }

    // MARK: - Helpers

    private func makeStore(liveRunID: String? = nil) -> Store {
        Store(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: sidecarsDirectory,
            liveRunID: liveRunID
        )
    }

    private func snapshotRuns(liveRunID: String? = nil) throws -> [Run] {
        try makeStore(liveRunID: liveRunID).snapshotRuns()
    }

    private func summary(at index: Int = 0) throws -> RunSummary? {
        let store = makeStore()
        return try store.summary(of: store.snapshotRuns()[index])
    }

    @discardableResult
    private func writeSummary(_ summary: RunSummary, startNs: UInt64) throws -> URL {
        try KSCrashTests.writeSummary(summary, startNs: startNs, in: runsDirectory)
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
            &config, nil)
        XCTAssertNotNil(store)
        populate(store!)
        kskvs_destroy(store)
    }

    // MARK: - Snapshot

    func test_runs_missingDirectory_isEmpty() throws {
        try FileManager.default.removeItem(at: runsDirectory)
        XCTAssertEqual(try snapshotRuns().count, 0)
    }

    func test_runs_missingSidecarsDirectory_isEmptyNotAnError() throws {
        try writeSummary(makeSummary(runID: "NOSIDE"), startNs: 100)
        try FileManager.default.removeItem(at: sidecarsDirectory)
        let runs = try snapshotRuns()
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
        XCTAssertThrowsError(try snapshotRuns())
    }

    func test_runs_ordersNewestFirst() throws {
        try writeSummary(makeSummary(runID: "AAA"), startNs: 100)
        try writeSummary(makeSummary(runID: "BBB"), startNs: 300)
        try writeSummary(makeSummary(runID: "CCC"), startNs: 200)

        let runs = try snapshotRuns()
        XCTAssertEqual(runs.map(\.runID), ["BBB", "CCC", "AAA"])
    }

    func test_runs_corruptTimestampSaturatesNewest_insteadOfWrapping() throws {
        try writeSummary(makeSummary(runID: "HONEST"), startNs: 100)
        // Non-writer-named, so ordering falls back to the decoded timestamp;
        // Int64.max * 1e6 would wrap far below any honest key.
        try Data(#"{"run_id": "CORRUPT", "started_at_ms": 9223372036854775807}"#.utf8)
            .write(to: runsDirectory.appendingPathComponent("foreign.run"))

        let runs = try snapshotRuns()
        XCTAssertEqual(runs.map(\.runID), ["CORRUPT", "HONEST"])
    }

    func test_runs_groupsArtifactsByRunID() throws {
        let runID = "11111111-2222-3333-4444-555555555555"
        try writeSummary(makeSummary(runID: runID), startNs: 100)
        writeSessions(runID: runID, cuts: [(true, nil)])
        try writeUserInfo(runID: runID) { kskvs_setString($0, "k", "v") }

        let runs = try snapshotRuns()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].runID, runID)
        XCTAssertNotNil(runs[0].summaryFile)
        XCTAssertNotNil(runs[0].sessionsFile)
        XCTAssertNotNil(runs[0].sidecarDirectory)
    }

    func test_runs_includesArtifactOnlyRuns_afterSummaryRuns() throws {
        try writeSummary(makeSummary(runID: "WITHSUMMARY"), startNs: 100)
        writeSessions(runID: "ORPHAN", cuts: [(true, nil)])

        let runs = try snapshotRuns()
        XCTAssertEqual(runs.map(\.runID), ["WITHSUMMARY", "ORPHAN"])
        XCTAssertNil(try summary(at: 1))
    }

    func test_runs_excludesLiveRun_evenArtifactOnly() throws {
        try writeSummary(makeSummary(runID: "DEAD"), startNs: 100)
        try writeSummary(makeSummary(runID: "LIVE"), startNs: 200)
        writeSessions(runID: "LIVEORPHAN", cuts: [(true, nil)])

        XCTAssertEqual(try snapshotRuns(liveRunID: "LIVE").map(\.runID), ["DEAD", "LIVEORPHAN"])
        XCTAssertEqual(try snapshotRuns(liveRunID: "LIVEORPHAN").map(\.runID), ["LIVE", "DEAD"])
    }

    func test_runs_skipsCorruptAndRunIDLessSummaries() throws {
        try Data("not json".utf8).write(to: runsDirectory.appendingPathComponent("0000000000000000050.run"))
        try writeSummary(makeSummary(runID: ""), startNs: 100)
        try writeSummary(makeSummary(runID: "GOOD"), startNs: 200)

        let runs = try snapshotRuns()
        XCTAssertEqual(runs.map(\.runID), ["GOOD"])
        // Skipped files stay on disk for pruning.
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: runsDirectory.path).filter { $0.hasSuffix(".run") }
                .count, 3)
    }

    // MARK: - Prune

    func test_prune_deletesOldestBeyondCap() throws {
        for ns in [100, 200, 300, 400] as [UInt64] {
            try writeSummary(makeSummary(runID: "RUN\(ns)"), startNs: ns)
        }
        // Legacy unpadded filenames parse by value, so this is the oldest.
        try JSONEncoder().encode(makeSummary(runID: "LEGACY")).write(
            to: runsDirectory.appendingPathComponent("5.run"))
        try Data("x".utf8).write(to: runsDirectory.appendingPathComponent("notdigits.run"))

        let store = makeStore()
        store.pruneRunSummaries(keepingNewest: 2)

        XCTAssertEqual(try store.snapshotRuns().map(\.runID), ["RUN400", "RUN300"])
        let remaining = try FileManager.default.contentsOfDirectory(atPath: runsDirectory.path).sorted()
        // Oldest three writer-named files pruned; the non-writer-named file is untouched.
        XCTAssertEqual(remaining, ["0000000000000000300.run", "0000000000000000400.run", "notdigits.run"])
    }

    func test_prune_zeroCap_keepsEverything() throws {
        for ns in [100, 200, 300] as [UInt64] {
            try writeSummary(makeSummary(runID: "RUN\(ns)"), startNs: ns)
        }
        let store = makeStore()
        store.pruneRunSummaries(keepingNewest: 0)
        XCTAssertEqual(try store.snapshotRuns().count, 3)
    }

    // MARK: - Sessions merge

    func test_summary_mergesSessionRecords() throws {
        let runID = "MERGE"
        try writeSummary(makeSummary(runID: runID, endedAtMs: .max), startNs: 100)
        writeSessions(runID: runID, cuts: [(true, nil), (true, "alice"), (false, "alice")])

        let summary = try XCTUnwrap(summary())
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

        let record = try XCTUnwrap(summary()?.sessions.records.first)
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

        let records = try XCTUnwrap(summary()).sessions.records
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

        let records = try XCTUnwrap(summary()).sessions.records
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
        XCTAssertNil(try summary())

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: sessionsPath)
        let records = try XCTUnwrap(summary()).sessions.records
        XCTAssertEqual(records.map(\.userID), ["alice"])
    }

    func test_summary_withoutSessionsFile_keepsEmptyRecords() throws {
        try writeSummary(makeSummary(runID: "NOSESSIONS"), startNs: 100)
        let summary = try XCTUnwrap(summary())
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

        let metadata = try XCTUnwrap(summary()?.metadata)
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

        let stitched = try XCTUnwrap(summary()?.metadata?.value(forKey: "when", as: Date.self))
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
        let summary = try XCTUnwrap(summary())
        XCTAssertNil(summary.metadata)
    }

    func test_summary_metadata_nilWithoutSidecar() throws {
        try writeSummary(makeSummary(runID: "BARE"), startNs: 100)
        let summary = try XCTUnwrap(summary())
        XCTAssertNil(summary.metadata)
    }

    func test_summary_corruptUserInfoSidecar_deliversWithoutMetadata() throws {
        let runID = "TORNMETA"
        try writeSummary(makeSummary(runID: runID), startNs: 100)
        let directory = sidecarsDirectory.appendingPathComponent(runID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(KSCRS_USERINFO_RUN_SIDECAR_FILENAME)

        // A crash before the header write leaves a short file; no later read
        // can recover anything, so the summary still delivers.
        try Data([0x00, 0x01]).write(to: path)
        XCTAssertNil(try XCTUnwrap(summary()).metadata)

        // A crash after ftruncate but before the header write leaves a full
        // page of zeros (bad magic); same outcome.
        try Data(repeating: 0, count: 4096).write(to: path)
        XCTAssertNil(try XCTUnwrap(summary()).metadata)
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
        XCTAssertNil(try summary())

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        let metadata = try XCTUnwrap(summary()?.metadata)
        XCTAssertEqual(metadata.value(forKey: "k", as: String.self), "v")
    }

    // MARK: - Ownership

    func test_removeSummary_leavesSharedFilesAlone() throws {
        let runID = "OWNED"
        try writeSummary(makeSummary(runID: runID), startNs: 100)
        writeSessions(runID: runID, cuts: [(true, nil)])
        try writeUserInfo(runID: runID) { kskvs_setString($0, "k", "v") }

        let store = makeStore()
        let run = try store.snapshotRuns()[0]
        try store.removeSummary(of: run)

        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(run.summaryFile).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(run.sessionsFile).path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(run.sidecarDirectory).appendingPathComponent(KSCRS_USERINFO_RUN_SIDECAR_FILENAME)
                    .path))

        // The next snapshot sees the run as artifact-only.
        let after = try store.snapshotRuns()
        XCTAssertEqual(after.count, 1)
        XCTAssertNil(try store.summary(of: after[0]))
    }

    func test_reclaimOrphans_invokesInjectedReclaim() {
        let called = expectation(description: "reclaim")
        let store = Store(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: sidecarsDirectory,
            liveRunID: nil
        ) { called.fulfill() }
        store.reclaimOrphans()
        wait(for: [called], timeout: 1)
    }

    // MARK: - Reports

    private struct BridgeError: Error {}

    private func makeReportStore(
        _ reports: FakeReports, listFails: Bool = false, removeFails: Bool = false
    ) -> Store {
        Store(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: sidecarsDirectory,
            liveRunID: nil,
            reports: ReportBridge(
                list: {
                    if listFails { throw BridgeError() }
                    return reports.ids
                },
                read: { reports.data(for: $0) },
                runID: { _ in nil },
                remove: {
                    if removeFails { throw BridgeError() }
                    reports.remove($0)
                }
            )
        )
    }

    /// In-memory stand-in for the C report store.
    private final class FakeReports: Sendable {
        private let storage: UnfairLock<[ReportID: Data]>

        init(_ contents: [ReportID: Data]) {
            storage = UnfairLock(contents)
        }

        var ids: [ReportID] { storage.withLock { Array($0.keys) } }
        func data(for id: ReportID) -> Data? { storage.withLock { $0[id] } }
        func remove(_ id: ReportID) { storage.withLock { _ = $0.removeValue(forKey: id) } }
    }

    private func makeReportData(runID: String = "RUN") throws -> Data {
        try JSONEncoder().encode(
            Report(
                crash: .init(error: CrashError(type: .signal)),
                report: .init(id: "report-id", runId: runID)
            ))
    }

    func test_snapshotReportIDs_newestFirst() throws {
        let reports = FakeReports([3: Data(), 1: Data(), 2: Data()])
        XCTAssertEqual(try makeReportStore(reports).snapshotReportIDs(), [3, 2, 1])
    }

    func test_snapshotReportIDs_throwsWhenReportListFails() {
        XCTAssertThrowsError(try makeReportStore(FakeReports([:]), listFails: true).snapshotReportIDs())
    }

    func test_snapshotReportIDs_doesNotTouchTheRunsHalf() throws {
        try FileManager.default.removeItem(at: runsDirectory)
        try makeUnreadableDirectory(at: runsDirectory)
        let reports = FakeReports([1: Data()])
        XCTAssertEqual(try makeReportStore(reports).snapshotReportIDs(), [1])
    }

    func test_snapshotRuns_doesNotTouchTheReportsHalf() throws {
        try writeSummary(makeSummary(runID: "RUN"), startNs: 100)
        let store = makeReportStore(FakeReports([:]), listFails: true)
        XCTAssertEqual(try store.snapshotRuns().map(\.runID), ["RUN"])
    }

    func test_report_decodesStitchedData() throws {
        let reports = FakeReports([7: try makeReportData(runID: "SEVEN")])
        let report = try XCTUnwrap(makeReportStore(reports).report(7))
        XCTAssertEqual(report.report.runId, "SEVEN")
    }

    func test_report_nilWhenMissing_throwsWhenUndecodable() throws {
        let reports = FakeReports([5: Data("not json".utf8)])
        let store = makeReportStore(reports)
        XCTAssertNil(try store.report(6))
        XCTAssertThrowsError(try store.report(5)) { error in
            XCTAssertTrue(error is DecodingError, "\(error)")
        }
    }

    func test_report_propagatesTheBridgeReadError() throws {
        struct NotAReport: Error {}
        let store = Store(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: sidecarsDirectory,
            liveRunID: nil,
            reports: ReportBridge(
                list: { [5] }, read: { _ in throw NotAReport() }, runID: { _ in nil }, remove: { _ in })
        )
        XCTAssertThrowsError(try store.report(5)) { error in
            XCTAssertTrue(error is NotAReport, "\(error)")
        }
    }

    // MARK: - Production bridge (C-backed report store)

    /// The production read must tell "not a report" (the C store read the file
    /// but found no JSON object) from "cannot read right now": the first is
    /// thrown, the second is nil.
    func test_productionBridge_throwsForANonReportFile_nilForAMissingOne() throws {
        let reportsDirectory = runsDirectory.deletingLastPathComponent().appendingPathComponent("Reports")
        let configuration = CrashReportStoreConfiguration()
        configuration.reportsPath = reportsDirectory.path
        configuration.appName = "App"
        let reportStore = try CrashReportStore(configuration: configuration)
        let store = Store(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: sidecarsDirectory,
            liveRunID: nil,
            reportStore: reportStore
        )

        // Named like the C store names them: <app>-report-<16 hex digits>.json.
        func reportURL(_ id: ReportID) -> URL {
            reportsDirectory.appendingPathComponent(String(format: "App-report-%016llx.json", id))
        }
        try makeReportData(runID: "REAL").write(to: reportURL(1))
        try Data("[1,2]".utf8).write(to: reportURL(2))
        try Data().write(to: reportURL(3))

        XCTAssertEqual(try store.snapshotReportIDs(), [3, 2, 1])
        XCTAssertEqual(try store.report(1)?.report.runId, "REAL")
        for id in [ReportID(2), 3] {
            XCTAssertThrowsError(try store.report(id), "report \(id)") { error in
                XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile, "\(error)")
            }
        }
        XCTAssertNil(try store.report(4))
        XCTAssertEqual(try store.snapshotReportIDs(), [3, 2, 1], "nothing is deleted by a read")
    }

    func test_removeReport_removesAndPropagatesFailure() throws {
        let reports = FakeReports([9: try makeReportData()])
        try makeReportStore(reports).removeReport(9)
        XCTAssertNil(reports.data(for: 9))

        XCTAssertThrowsError(try makeReportStore(reports, removeFails: true).removeReport(9))
    }
}
