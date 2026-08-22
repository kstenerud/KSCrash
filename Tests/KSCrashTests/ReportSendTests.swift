//
//  ReportSendTests.swift
//
//  Created by Alexander Cohen on 2026-08-15.
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

import KSCrashSwiftCore
import XCTest

@testable import KSCrash

final class ReportSendTests: XCTestCase {

    private var reportsDirectory: URL!
    private let reclaimCount = Counter()

    override func setUpWithError() throws {
        reportsDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReportSendTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: reportsDirectory)
    }

    // MARK: - Helpers

    /// Real files, so delete semantics are exercised, keyed like the C store
    /// would key them: one file per report ID.
    private func writeReport(id: ReportID, runID: String = "DEAD") throws {
        let report = Report(
            crash: .init(error: CrashError(type: .signal)),
            report: .init(id: "report-\(id)", runId: testRunID(runID))
        )
        try JSONEncoder().encode(report).write(to: reportURL(id))
    }

    private func reportURL(_ id: ReportID) -> URL {
        reportsDirectory.appendingPathComponent("\(id).json")
    }

    private var reportFileCount: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: reportsDirectory.path))?
            .filter { $0.hasSuffix(".json") }.count ?? -1
    }

    private var runsDirectory: URL { reportsDirectory.appendingPathComponent("Runs") }

    private func makeStore(
        liveRunID: RunSummary.ID? = testRunID("LIVE"), listFails: Bool = false, undecodable: Set<ReportID> = [],
        peekBlind: Bool = false
    ) -> Store {
        let directory = reportsDirectory!
        let counter = reclaimCount
        return Store(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: directory.appendingPathComponent("RunSidecars"),
            liveRunID: liveRunID,
            reports: ReportBridge(
                list: {
                    if listFails { throw StageError() }
                    return try FileManager.default.contentsOfDirectory(atPath: directory.path)
                        .filter { $0.hasSuffix(".json") }
                        .compactMap { ReportID(($0 as NSString).deletingPathExtension) }
                },
                read: {
                    if undecodable.contains($0) { throw CocoaError(.fileReadCorruptFile) }
                    return try? Data(contentsOf: directory.appendingPathComponent("\($0).json"))
                },
                runID: { id in
                    guard !peekBlind,
                        let data = try? Data(contentsOf: directory.appendingPathComponent("\(id).json")),
                        let report = try? JSONDecoder().decode(Report.self, from: data)
                    else { return nil }
                    return report.report.runId
                },
                remove: { try FileManager.default.removeItem(at: directory.appendingPathComponent("\($0).json")) }
            ),
            reclaim: { counter.increment() }
        )
    }

    private func send(
        pipeline: [AnyPipelineStage<Report>] = [.init(ClosureStage { $0 })],
        only selection: Set<ReportID>? = nil,
        liveRunID: RunSummary.ID? = testRunID("LIVE"),
        listFails: Bool = false,
        undecodable: Set<ReportID> = [],
        peekBlind: Bool = false,
        claims: SendClaims<ReportID> = SendClaims()
    ) async throws -> SendResult<Report> {
        try await ReportSend.send(
            store: makeStore(
                liveRunID: liveRunID, listFails: listFails, undecodable: undecodable, peekBlind: peekBlind),
            pipeline: pipeline,
            only: selection,
            claims: claims)
    }

    // MARK: - Tests

    func test_send_deliversNewestFirst_andDeletes() async throws {
        try writeReport(id: 1)
        try writeReport(id: 2)

        let seen = UnfairLock([String]())
        let stage = ClosureStage<Report> { report in
            seen.withLock { $0.append(report.report.id) }
            return report
        }

        let result = try await send(pipeline: [.init(stage)])
        assertOutcomes(result, delivered: [2, 1])
        XCTAssertEqual(seen.withLock { $0 }, ["report-2", "report-1"])
        XCTAssertEqual(reportFileCount, 0)
        XCTAssertGreaterThan(reclaimCount.value, 0)
    }

    func test_send_discardedIsDeletedAndNeverSentAgain() async throws {
        try writeReport(id: 1)
        let result = try await send(pipeline: [.init(ClosureStage<Report> { _ in nil })])
        assertOutcomes(result, discarded: [1])
        XCTAssertEqual(reportFileCount, 0)
    }

    func test_send_stageThrow_keepsOnDisk() async throws {
        try writeReport(id: 1)
        let result = try await send(pipeline: [.init(ClosureStage<Report> { _ in throw StageError() })])
        assertOutcomes(result, kept: [1])
        XCTAssertEqual(reportFileCount, 1)
    }

    func test_send_emptyPipeline_throwsAndTouchesNothing() async throws {
        try writeReport(id: 1)
        try writeReport(id: 2)
        do {
            _ = try await send(pipeline: [])
            XCTFail("expected SendError.emptyPipeline")
        } catch let error as SendError {
            XCTAssertEqual(error, .emptyPipeline)
        }
        XCTAssertEqual(reportFileCount, 2)
        XCTAssertEqual(reclaimCount.value, 0)
    }

    func test_send_claimedReport_isNotAnItemAndUntouched() async throws {
        try writeReport(id: 1)
        try writeReport(id: 2)

        let claims = SendClaims<ReportID>()
        XCTAssertTrue(claims.claim(1))
        let result = try await send(claims: claims)
        assertOutcomes(result, delivered: [2])
        XCTAssertEqual(reportFileCount, 1)
    }

    func test_send_cancellation_stopsBetweenItems() async throws {
        for id: ReportID in 1...4 {
            try writeReport(id: id)
        }

        let stage = ClosureStage<Report> { report in
            withUnsafeCurrentTask { $0?.cancel() }
            return report
        }

        let sendTask = Task { try await send(pipeline: [.init(stage)]) }
        let result = try await sendTask.value
        // The first (newest) report processes, then the loop sees the
        // cancellation and returns what it has.
        assertOutcomes(result, delivered: [4])
        XCTAssertEqual(reportFileCount, 3)
    }

    func test_send_undecodableReport_isKeptWithTheDecodeError_andStays() async throws {
        try writeReport(id: 1)
        try Data("not json".utf8).write(to: reportURL(2))

        let result = try await send()
        assertOutcomes(result, delivered: [1], kept: [2])
        let kept = try XCTUnwrap(result.items.first { $0.id == 2 })
        guard case .kept(let error) = kept.outcome else {
            return XCTFail("expected a kept outcome, got \(kept.outcome)")
        }
        XCTAssertTrue(error is DecodingError, "\(error)")
        XCTAssertEqual(reportFileCount, 1)
    }

    /// The store's own "read, but not a report" answer (a throwing bridge read)
    /// is the same kept outcome as a typed decode failure.
    func test_send_reportTheStoreCannotDecode_isKeptWithTheStoreError_andStays() async throws {
        try writeReport(id: 1)
        try writeReport(id: 2)

        let result = try await send(undecodable: [2])
        assertOutcomes(result, delivered: [1], kept: [2])
        let kept = try XCTUnwrap(result.items.first { $0.id == 2 })
        guard case .kept(let error) = kept.outcome else {
            return XCTFail("expected a kept outcome, got \(kept.outcome)")
        }
        XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile, "\(error)")
        XCTAssertEqual(reportFileCount, 1)
    }

    func test_send_reportGoneAfterListing_isNotAnItem() async throws {
        try writeReport(id: 1)
        try writeReport(id: 2)

        // Report 2 (newest) goes first; its stage deletes report 1's file, so
        // report 1 is a stale listing entry by the time it is read.
        let url = reportURL(1)
        let stage = ClosureStage<Report> { report in
            try FileManager.default.removeItem(at: url)
            return report
        }

        let result = try await send(pipeline: [.init(stage)])
        assertOutcomes(result, delivered: [2])
        XCTAssertEqual(reportFileCount, 0)
    }

    func test_send_currentRunReport_skippedInBulk_sentWhenNamed() async throws {
        try writeReport(id: 1, runID: "DEAD")
        try writeReport(id: 2, runID: "LIVE")

        let bulk = try await send()
        assertOutcomes(bulk, delivered: [1])
        XCTAssertEqual(reportFileCount, 1)

        let named = try await send(only: [2])
        assertOutcomes(named, delivered: [2])
        XCTAssertEqual(reportFileCount, 0)
    }

    /// A report torn at peek time (no readable run id yet) can finish
    /// writing before the full read: the decoded run is the authoritative
    /// check, so the live-run report is still skipped, not delivered.
    func test_send_currentRunReport_skippedInBulk_evenWhenThePeekIsBlind() async throws {
        try writeReport(id: 1, runID: "LIVE")

        let result = try await send(peekBlind: true)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(reportFileCount, 1)
    }

    func test_send_only_unknownIDsMatchNothing_emptySendsNothing() async throws {
        try writeReport(id: 1)

        let unknown = try await send(only: [42])
        XCTAssertTrue(unknown.items.isEmpty)

        let empty = try await send(only: [])
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertEqual(reportFileCount, 1)
    }

    func test_send_deleteFailure_stillDelivered() async throws {
        try writeReport(id: 1)
        let store = makeStore()
        // Remove the file mid-flight through a stage, so the driver's delete
        // fails after a successful pipeline pass.
        let url = reportURL(1)
        let stage = ClosureStage<Report> { report in
            try FileManager.default.removeItem(at: url)
            return report
        }
        let result = try await ReportSend.send(
            store: store, pipeline: [.init(ClosureStage<Report> { $0 }), .init(stage)],
            claims: SendClaims())
        assertOutcomes(result, delivered: [1])
    }

    func test_send_storeListFailure_throws() async {
        do {
            _ = try await send(listFails: true)
            XCTFail("expected a throw")
        } catch {}
    }

    func test_send_unreadableRunsDirectory_stillDeliversReports() async throws {
        // The report send depends on the Reports directory only: damage to
        // the runs half must not block crash-report delivery.
        try makeUnreadableDirectory(at: runsDirectory)
        try writeReport(id: 1)

        let result = try await send()
        assertOutcomes(result, delivered: [1])
        XCTAssertEqual(reportFileCount, 0)
    }

    func test_send_noStore_emptyResult() async throws {
        let result = try await ReportSend.send(
            store: nil, pipeline: [passThrough()], claims: SendClaims())
        XCTAssertTrue(result.items.isEmpty)
    }
}
