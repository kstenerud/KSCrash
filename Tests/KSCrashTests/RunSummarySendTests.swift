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

    private final class Counter: Sendable {
        private let count = UnfairLock(0)
        var value: Int { count.withLock { $0 } }
        func increment() { count.withLock { $0 += 1 } }
    }

    private struct ClosureStage: PipelineStage {
        let body: @Sendable (RunSummary) async throws -> RunSummary?
        func process(_ payload: RunSummary) async throws -> RunSummary? {
            try await body(payload)
        }
    }

    private struct StageError: Error {}

    private func makeStore() -> Store {
        let counter = reclaimCount
        return Store(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: sidecarsDirectory,
            liveRunID: nil
        ) { counter.increment() }
    }

    private func send(
        pipeline: [AnyPipelineStage<RunSummary>] = [.init(ClosureStage { $0 })],
        includesDeliveredPayloads: Bool = false,
        claims: SendClaims = SendClaims()
    ) async throws -> SendResult<RunSummary> {
        try await RunSummarySend.send(
            store: makeStore(), pipeline: pipeline,
            includesDeliveredPayloads: includesDeliveredPayloads, maxRunCount: 50, claims: claims)
    }

    private func assertOutcomes(
        _ result: SendResult<RunSummary>,
        delivered: [String] = [],
        discarded: [String] = [],
        kept: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.delivered, delivered, file: file, line: line)
        XCTAssertEqual(result.discarded, discarded, file: file, line: line)
        XCTAssertEqual(result.kept, kept, file: file, line: line)
    }

    private func makeSummary(runID: String) -> RunSummary {
        RunSummary(
            schemaVersion: 1,
            sdkVersion: "test",
            runID: runID,
            deviceID: "device",
            startedAtMs: 1_000,
            endedAtMs: 2_000,
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

    private func writeSummary(runID: String, startNs: UInt64) throws {
        let url = runsDirectory.appendingPathComponent(String(format: "%019llu.run", startNs))
        try JSONEncoder().encode(makeSummary(runID: runID)).write(to: url)
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

    func test_notInstalled_returnsEmptyWithoutReclaim() async throws {
        let result = try await RunSummarySend.send(
            store: nil, pipeline: [.init(ClosureStage { $0 })],
            includesDeliveredPayloads: false, claims: SendClaims())
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
        let first = ClosureStage { summary in
            XCTAssertEqual(summary.runID, "ORIGINAL")
            return replaced
        }
        let second = ClosureStage { summary in
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

        let sampler = ClosureStage { summary in
            summary.runID == "DROPPED" ? nil : summary
        }

        let result = try await send(pipeline: [.init(sampler)])
        assertOutcomes(result, delivered: ["SENT"], discarded: ["DROPPED"])
        XCTAssertEqual(summaryFileCount, 0)
    }

    func test_stageThrow_keepsRunForRetry() async throws {
        try writeSummary(runID: "FAILING", startNs: 200)
        try writeSummary(runID: "FINE", startNs: 100)

        let flaky = ClosureStage { summary in
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

        let flaky = ClosureStage { _ in throw StageError() }
        let result = try await send(pipeline: [.init(flaky)])

        XCTAssertEqual(result.items.count, 1)
        guard case .kept(let error) = result.items[0].outcome else {
            return XCTFail("expected .kept, got \(result.items[0].outcome)")
        }
        XCTAssertTrue(error is StageError)
    }

    func test_deliveredPayload_nilByDefault() async throws {
        try writeSummary(runID: "PLAIN", startNs: 100)

        let result = try await send()
        guard case .delivered(let payload) = result.items[0].outcome else {
            return XCTFail("expected .delivered, got \(result.items[0].outcome)")
        }
        XCTAssertNil(payload)
        XCTAssertTrue(result.deliveredPayloads.isEmpty)
    }

    func test_deliveredPayload_isFinalWhenConfigured() async throws {
        try writeSummary(runID: "ORIGINAL", startNs: 100)

        let replaced = makeSummary(runID: "REPLACED")
        let rewriting = ClosureStage { _ in replaced }

        let result = try await send(pipeline: [.init(rewriting)], includesDeliveredPayloads: true)
        // The payload is the post-pipeline value; the item id stays the run's.
        XCTAssertEqual(result.items[0].id, "ORIGINAL")
        XCTAssertEqual(result.deliveredPayloads.map(\.runID), ["REPLACED"])
    }

    func test_durations_areNonNegative() async throws {
        try writeSummary(runID: "TIMED", startNs: 100)

        let slow = ClosureStage { summary in
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

        let claims = SendClaims()
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

        let claims = SendClaims()
        let counter = reclaimCount
        let runsDirectory = runsDirectory!
        let sidecarsDirectory = sidecarsDirectory!
        let reentrant = ClosureStage { summary in
            // A send started from inside a stage finds the outer send's run
            // claimed: empty result, no deadlock.
            let store = Store(
                runsDirectory: runsDirectory,
                runSidecarsDirectory: sidecarsDirectory,
                liveRunID: nil
            ) { counter.increment() }
            let inner = try await RunSummarySend.send(
                store: store, pipeline: [.init(ClosureStage { $0 })],
                includesDeliveredPayloads: false, claims: claims)
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

        let claims = SendClaims()
        let slow = ClosureStage { summary in
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
            store: makeStore(), pipeline: [.init(ClosureStage { $0 })],
            includesDeliveredPayloads: false,
            only: ["WANTED", "UNKNOWN"], claims: SendClaims())

        assertOutcomes(result, delivered: ["WANTED"])
        XCTAssertEqual(summaryFileCount, 1)
    }

    func test_only_emptySelection_sendsNothing() async throws {
        try writeSummary(runID: "PRESENT", startNs: 100)

        let result = try await RunSummarySend.send(
            store: makeStore(), pipeline: [.init(ClosureStage { $0 })],
            includesDeliveredPayloads: false,
            only: [], claims: SendClaims())

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(summaryFileCount, 1)
    }

    func test_only_retryingKeptIdsDeliversJustThose() async throws {
        try writeSummary(runID: "FLAKY", startNs: 200)
        try writeSummary(runID: "OK", startNs: 100)

        let failOnce = ClosureStage { summary in
            if summary.runID == "FLAKY" {
                throw StageError()
            }
            return summary
        }
        let first = try await send(pipeline: [.init(failOnce)])
        assertOutcomes(first, delivered: ["OK"], kept: ["FLAKY"])

        // The retry call site: resend exactly what the last send kept.
        let retry = try await RunSummarySend.send(
            store: makeStore(), pipeline: [.init(ClosureStage { $0 })],
            includesDeliveredPayloads: false,
            only: Set(first.kept), claims: SendClaims())
        assertOutcomes(retry, delivered: ["FLAKY"])
        XCTAssertEqual(summaryFileCount, 0)
    }

    // MARK: - Cancellation

    func test_cancellation_returnsPartialAndKeepsTheRest() async throws {
        try writeSummary(runID: "FIRST", startNs: 200)
        try writeSummary(runID: "SECOND", startNs: 100)

        let cancelling = ClosureStage { summary in
            withUnsafeCurrentTask { $0?.cancel() }
            return summary
        }

        let store = makeStore()
        let result = try await Task {
            try await RunSummarySend.send(
                store: store, pipeline: [.init(cancelling)],
                includesDeliveredPayloads: false, maxRunCount: 50, claims: SendClaims())
        }.value

        assertOutcomes(result, delivered: ["FIRST"])
        XCTAssertEqual(summaryFileCount, 1)
        XCTAssertEqual(reclaimCount.value, 1)
    }
}
