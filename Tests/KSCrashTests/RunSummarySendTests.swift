//
//  RunSummarySendTests.swift
//
//  Created by Alexander Cohen on 2026-08-10.
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

final class RunSummarySendTests: XCTestCase {

    private var runsDirectory: URL!
    private var sidecarsDirectory: URL!
    private let reclaimCount = Counter()

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RunSummarySendTests-\(UUID().uuidString)")
        runsDirectory = base.appendingPathComponent("Runs")
        sidecarsDirectory = base.appendingPathComponent("RunSidecars")
        try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sidecarsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: runsDirectory.deletingLastPathComponent())
    }

    // MARK: - Helpers

    /// `listFails` makes the report half's listing throw, standing in for an
    /// unreadable Reports directory.
    private func makeStore(listFails: Bool = false, maxRunCount: Int = 50) -> Store {
        let counter = reclaimCount
        return Store(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: sidecarsDirectory,
            liveRunID: nil,
            maxRunCount: maxRunCount,
            reports: ReportBridge(
                list: {
                    if listFails { throw StageError() }
                    return []
                },
                read: { _ in nil },
                runID: { _ in nil },
                remove: { _ in }
            ),
            reclaim: { counter.increment() }
        )
    }

    private func send(
        pipeline: [AnyPipelineStage<RunSummary>] = [.init(ClosureStage { $0 })],
        listFails: Bool = false,
        claims: SendClaims<String> = SendClaims()
    ) async throws -> SendResult<RunSummary> {
        try await RunSummarySend.send(
            store: makeStore(listFails: listFails), pipeline: pipeline, claims: claims)
    }

    private func writeSummary(runID: String, startNs: UInt64) throws {
        try KSCrashTests.writeSummary(makeSummary(runID: runID), startNs: startNs, in: runsDirectory)
    }

    private var summaryFileCount: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: runsDirectory.path))?
            .filter { $0.hasSuffix(".run") }.count ?? -1
    }

    // MARK: - Empty pipeline

    func test_emptyPipeline_throwsAndTouchesNothing() async throws {
        try writeSummary(runID: "OLD", startNs: 100)
        try writeSummary(runID: "NEW", startNs: 200)

        do {
            _ = try await send(pipeline: [])
            XCTFail("expected SendError.emptyPipeline")
        } catch let error as SendError {
            XCTAssertEqual(error, .emptyPipeline)
        }
        XCTAssertEqual(summaryFileCount, 2)
        XCTAssertEqual(reclaimCount.value, 0)
    }

    func test_emptyStore_returnsEmptyAndReclaims() async throws {
        let result = try await send()
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(reclaimCount.value, 1)
    }

    func test_unreadableReportsDirectory_stillDeliversSummaries() async throws {
        // The summary send depends on the Runs directory only: damage to
        // the reports half must not block run-summary delivery.
        try writeSummary(runID: "RUN", startNs: 100)

        let result = try await send(listFails: true)
        assertOutcomes(result, delivered: ["RUN"])
        XCTAssertEqual(summaryFileCount, 0)
    }

    /// A `.run` that still yields its identity but no longer decodes as the
    /// full model (a schema break across an upgrade) is a kept item carrying
    /// the decode error, not a silent skip; the file stays for a later SDK.
    func test_summaryThatFailsTheFullDecode_isKeptWithTheError_andStays() async throws {
        try writeSummary(runID: "OK", startNs: 100)
        try Data(#"{"run_id": "BROKEN", "started_at_ms": 1000}"#.utf8)
            .write(to: runsDirectory.appendingPathComponent(String(format: "%019llu.run", UInt64(200))))

        let result = try await send()

        assertOutcomes(result, delivered: ["OK"], kept: ["BROKEN"])
        let kept = try XCTUnwrap(result.items.first { $0.id == "BROKEN" })
        guard case .kept(let error) = kept.outcome else {
            return XCTFail("expected a kept outcome, got \(kept.outcome)")
        }
        XCTAssertTrue(error is DecodingError, "\(error)")
        XCTAssertEqual(summaryFileCount, 1)
    }

    /// A run_id alone must list: the strict model decode is the health gate,
    /// so a summary missing its timestamp is a kept item naming the missing
    /// field, never a silent skip.
    func test_summaryMissingItsTimestamp_isKeptWithTheError_andStays() async throws {
        try writeSummary(runID: "OK", startNs: 100)
        try Data(#"{"run_id": "BROKEN"}"#.utf8)
            .write(to: runsDirectory.appendingPathComponent(String(format: "%019llu.run", UInt64(200))))

        let result = try await send()

        assertOutcomes(result, delivered: ["OK"], kept: ["BROKEN"])
        let kept = try XCTUnwrap(result.items.first { $0.id == "BROKEN" })
        guard case .kept(let error) = kept.outcome else {
            return XCTFail("expected a kept outcome, got \(kept.outcome)")
        }
        XCTAssertTrue(error is DecodingError, "\(error)")
        XCTAssertEqual(summaryFileCount, 1)
    }

    /// A mistyped timestamp in a non-writer-named file costs the run its
    /// ordering, not its listing: it still surfaces as a kept item.
    func test_summaryWithAMistypedTimestamp_isKeptWithTheError_andStays() async throws {
        try Data(#"{"run_id": "BROKEN", "started_at_ms": "100"}"#.utf8)
            .write(to: runsDirectory.appendingPathComponent("foreign.run"))

        let result = try await send()

        assertOutcomes(result, kept: ["BROKEN"])
        XCTAssertEqual(summaryFileCount, 1)
    }

    /// A `.run` that does not even yield an identity cannot be keyed, so it
    /// is not an item: skipped, left on disk for pruning.
    func test_summaryWithoutAnIdentity_isNotAnItem() async throws {
        try writeSummary(runID: "OK", startNs: 100)
        try Data("not json".utf8)
            .write(to: runsDirectory.appendingPathComponent(String(format: "%019llu.run", UInt64(200))))

        let result = try await send()

        assertOutcomes(result, delivered: ["OK"])
        XCTAssertEqual(summaryFileCount, 1)
    }

    func test_notInstalled_returnsEmptyWithoutReclaim() async throws {
        let result = try await RunSummarySend.send(
            store: nil, pipeline: [passThrough()], claims: SendClaims())
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(reclaimCount.value, 0)
    }

    func test_artifactOnlyRuns_appearInNoList() async throws {
        // A run with only shared artifacts has nothing to send.
        try FileManager.default.createDirectory(
            at: sidecarsDirectory.appendingPathComponent("ORPHAN"), withIntermediateDirectories: true)

        let result = try await send()
        XCTAssertTrue(result.items.isEmpty)
    }

    // MARK: - Stage outcomes

    func test_stages_runInOrderAndOutputFlowsThrough() async throws {
        try writeSummary(runID: "ORIGINAL", startNs: 100)

        let replaced = makeSummary(runID: "REPLACED")
        let first = ClosureStage<RunSummary> { summary in
            XCTAssertEqual(summary.runID, "ORIGINAL")
            return replaced
        }
        let second = ClosureStage<RunSummary> { summary in
            XCTAssertEqual(summary.runID, "REPLACED")
            return summary
        }

        let result = try await send(pipeline: [.init(first), .init(second)])
        // Result ids are the on-disk run's, not the (possibly rewritten) payload's.
        XCTAssertEqual(result.delivered, ["ORIGINAL"])
        XCTAssertEqual(summaryFileCount, 0)
    }

    func test_stageNil_discardsWithoutRetry() async throws {
        try writeSummary(runID: "DROPPED", startNs: 100)
        try writeSummary(runID: "SENT", startNs: 200)

        let sampler = ClosureStage<RunSummary> { summary in
            summary.runID == "DROPPED" ? nil : summary
        }

        let result = try await send(pipeline: [.init(sampler)])
        assertOutcomes(result, delivered: ["SENT"], discarded: ["DROPPED"])
        XCTAssertEqual(summaryFileCount, 0)
    }

    func test_stageThrow_keepsRunForRetry() async throws {
        try writeSummary(runID: "FAILING", startNs: 200)
        try writeSummary(runID: "FINE", startNs: 100)

        let flaky = ClosureStage<RunSummary> { summary in
            if summary.runID == "FAILING" {
                throw StageError()
            }
            return summary
        }

        let result = try await send(pipeline: [.init(flaky)])
        assertOutcomes(result, delivered: ["FINE"], kept: ["FAILING"])
        XCTAssertEqual(summaryFileCount, 1)

        // The kept run is delivered by the next send.
        let retry = try await send()
        XCTAssertEqual(retry.delivered, ["FAILING"])
        XCTAssertEqual(summaryFileCount, 0)
    }

    func test_keptOutcome_carriesTheStageError() async throws {
        try writeSummary(runID: "FAILING", startNs: 100)

        let flaky = ClosureStage<RunSummary> { _ in throw StageError() }
        let result = try await send(pipeline: [.init(flaky)])

        XCTAssertEqual(result.items.count, 1)
        guard case .kept(let error) = result.items[0].outcome else {
            return XCTFail("expected .kept, got \(result.items[0].outcome)")
        }
        XCTAssertTrue(error is StageError)
    }

    func test_rewritingStage_laterStagesSeeTheRewrite_itemIdStaysTheRuns() async throws {
        try writeSummary(runID: "ORIGINAL", startNs: 100)

        let replaced = makeSummary(runID: "REPLACED")
        let rewriting = ClosureStage<RunSummary> { _ in replaced }
        let seen = UnfairLock([String]())
        let capturing = ClosureStage<RunSummary> { summary in
            seen.withLock { $0.append(summary.runID) }
            return summary
        }

        let result = try await send(pipeline: [.init(rewriting), .init(capturing)])
        // Payloads flow through the stages, never into the result: the item
        // id stays the run's, and the rewrite is what the next stage sees.
        assertOutcomes(result, delivered: ["ORIGINAL"])
        XCTAssertEqual(seen.withLock { $0 }, ["REPLACED"])
    }

    func test_durations_areNonNegative() async throws {
        try writeSummary(runID: "TIMED", startNs: 100)

        let slow = ClosureStage<RunSummary> { summary in
            try await Task.sleep(nanoseconds: 2_000_000)
            return summary
        }
        let result = try await send(pipeline: [.init(slow)])
        XCTAssertEqual(result.items.count, 1)
        XCTAssertGreaterThanOrEqual(result.items[0].duration, 0.002)
    }

    // MARK: - Claims

    func test_claimedRun_isSkippedAndLeftAlone() async throws {
        try writeSummary(runID: "HELD", startNs: 100)
        try writeSummary(runID: "FREE", startNs: 200)

        let claims = SendClaims<String>()
        XCTAssertTrue(claims.claim("HELD"))

        let result = try await send(claims: claims)
        assertOutcomes(result, delivered: ["FREE"])
        XCTAssertEqual(summaryFileCount, 1)

        claims.release("HELD")
        let second = try await send(claims: claims)
        XCTAssertEqual(second.delivered, ["HELD"])
    }

    func test_reentrantSendFromAStage_returnsEmptyWithoutDeadlock() async throws {
        try writeSummary(runID: "OUTER", startNs: 100)

        let claims = SendClaims<String>()
        let counter = reclaimCount
        let runsDirectory = runsDirectory!
        let sidecarsDirectory = sidecarsDirectory!
        let reentrant = ClosureStage<RunSummary> { summary in
            // A send started from inside a stage finds the outer send's run
            // claimed: empty result, no deadlock.
            let store = Store(
                runsDirectory: runsDirectory,
                runSidecarsDirectory: sidecarsDirectory,
                liveRunID: nil
            ) { counter.increment() }
            let inner = try await RunSummarySend.send(
                store: store, pipeline: [passThrough()], claims: claims)
            XCTAssertTrue(inner.items.isEmpty)
            return summary
        }

        let result = try await send(pipeline: [.init(reentrant)], claims: claims)
        XCTAssertEqual(result.delivered, ["OUTER"])
    }

    func test_concurrentSends_partitionWithoutDuplicates() async throws {
        let runIDs = (0..<6).map { "RUN\($0)" }
        for (index, runID) in runIDs.enumerated() {
            try writeSummary(runID: runID, startNs: UInt64(100 + index))
        }

        let claims = SendClaims<String>()
        let slow = ClosureStage<RunSummary> { summary in
            try await Task.sleep(nanoseconds: 5_000_000)
            return summary
        }

        async let first = send(pipeline: [.init(slow)], claims: claims)
        async let second = send(pipeline: [.init(slow)], claims: claims)
        let (a, b) = try await (first, second)

        // Between them every run is delivered exactly once.
        XCTAssertEqual((a.delivered + b.delivered).sorted(), runIDs.sorted())
        XCTAssertTrue(Set(a.delivered).isDisjoint(with: b.delivered))
        XCTAssertEqual(summaryFileCount, 0)
    }

    // MARK: - Selection

    func test_only_sendsSelectionAndLeavesTheRestUntouched() async throws {
        try writeSummary(runID: "WANTED", startNs: 100)
        try writeSummary(runID: "OTHER", startNs: 200)

        let result = try await RunSummarySend.send(
            store: makeStore(), pipeline: [passThrough()],
            only: ["WANTED", "UNKNOWN"], claims: SendClaims())

        assertOutcomes(result, delivered: ["WANTED"])
        XCTAssertEqual(summaryFileCount, 1)
    }

    func test_only_emptySelection_sendsNothing() async throws {
        try writeSummary(runID: "PRESENT", startNs: 100)

        let result = try await RunSummarySend.send(
            store: makeStore(), pipeline: [passThrough()],
            only: [], claims: SendClaims())

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(summaryFileCount, 1)
    }

    func test_only_retryingKeptIdsDeliversJustThose() async throws {
        try writeSummary(runID: "FLAKY", startNs: 200)
        try writeSummary(runID: "OK", startNs: 100)

        let failOnce = ClosureStage<RunSummary> { summary in
            if summary.runID == "FLAKY" {
                throw StageError()
            }
            return summary
        }
        let first = try await send(pipeline: [.init(failOnce)])
        assertOutcomes(first, delivered: ["OK"], kept: ["FLAKY"])

        // The retry call site: resend exactly what the last send kept.
        let retry = try await RunSummarySend.send(
            store: makeStore(), pipeline: [passThrough()],
            only: Set(first.kept), claims: SendClaims())
        assertOutcomes(retry, delivered: ["FLAKY"])
        XCTAssertEqual(summaryFileCount, 0)
    }

    // MARK: - Retention

    func test_bulkSend_prunesBeyondCapBeforeListing() async throws {
        try writeSummary(runID: "OLDEST", startNs: 100)
        try writeSummary(runID: "MID", startNs: 200)
        try writeSummary(runID: "NEW", startNs: 300)

        let result = try await RunSummarySend.send(
            store: makeStore(maxRunCount: 2), pipeline: [passThrough()], claims: SendClaims())

        // The beyond-cap run is pruned before the listing: not an item, file gone.
        assertOutcomes(result, delivered: ["NEW", "MID"])
        XCTAssertEqual(summaryFileCount, 0)
    }

    func test_only_neverPrunes_soANamedBeyondCapRunIsDelivered() async throws {
        try writeSummary(runID: "OLDEST", startNs: 100)
        try writeSummary(runID: "MID", startNs: 200)
        try writeSummary(runID: "NEW", startNs: 300)

        let result = try await RunSummarySend.send(
            store: makeStore(maxRunCount: 1), pipeline: [passThrough()],
            only: ["OLDEST"], claims: SendClaims())

        // A selective send touches only what it names: the beyond-cap named
        // run is delivered, and the unselected runs' files stay on disk.
        assertOutcomes(result, delivered: ["OLDEST"])
        XCTAssertEqual(summaryFileCount, 2)
    }

    // MARK: - Cancellation

    func test_cancellation_returnsPartialAndKeepsTheRest() async throws {
        try writeSummary(runID: "FIRST", startNs: 200)
        try writeSummary(runID: "SECOND", startNs: 100)

        let cancelling = ClosureStage<RunSummary> { summary in
            withUnsafeCurrentTask { $0?.cancel() }
            return summary
        }

        let store = makeStore()
        let result = try await Task {
            try await RunSummarySend.send(
                store: store, pipeline: [.init(cancelling)],
                claims: SendClaims())
        }.value

        assertOutcomes(result, delivered: ["FIRST"])
        XCTAssertEqual(summaryFileCount, 1)
        XCTAssertEqual(reclaimCount.value, 1)
    }
}
