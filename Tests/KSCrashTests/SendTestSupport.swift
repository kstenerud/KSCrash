//
//  SendTestSupport.swift
//
//  Created by Alexander Cohen on 2026-08-18.
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

/// A thread-safe counter, for reclaim and stage-invocation counts.
final class Counter: Sendable {
    private let count = UnfairLock(0)
    var value: Int { count.withLock { $0 } }
    func increment() { count.withLock { $0 += 1 } }
}

/// A stage made of a closure.
struct ClosureStage<Payload: PipelineValue>: PipelineStage {
    let body: @Sendable (Payload) async throws -> Payload?

    init(_ body: @escaping @Sendable (Payload) async throws -> Payload?) {
        self.body = body
    }

    func process(_ payload: Payload) async throws -> Payload? {
        try await body(payload)
    }
}

struct StageError: Error {}

/// A stage that forwards every payload unchanged, for tests that need a
/// pipeline but no behavior.
func passThrough<Payload: PipelineValue>() -> AnyPipelineStage<Payload> {
    .init(ClosureStage { $0 })
}

/// Assert a result's ids per outcome, in processing order.
func assertOutcomes<Payload: SendPayload>(
    _ result: SendResult<Payload>,
    delivered: [Payload.ID] = [],
    discarded: [Payload.ID] = [],
    kept: [Payload.ID] = [],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(result.delivered, delivered, file: file, line: line)
    XCTAssertEqual(result.discarded, discarded, file: file, line: line)
    XCTAssertEqual(result.kept, kept, file: file, line: line)
}

/// A run id for a readable test tag: a tag that already is a UUID is used as
/// is, anything else maps to one deterministic UUID per tag.
func testRunID(_ tag: String) -> RunSummary.ID {
    if let id = RunSummary.ID(tag) { return id }
    var bytes = [UInt8](repeating: 0, count: 16)
    for (index, byte) in tag.utf8.enumerated() {
        bytes[index % 16] ^= byte &+ UInt8(truncatingIfNeeded: index)
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    let uuid = UUID(
        uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    return RunSummary.ID(uuid: uuid)
}

/// A report id for a small test number: one deterministic UUID per value,
/// ordered like the numbers so name order matches numeric order.
func testReportID(_ value: Int) -> Report.ID {
    Report.ID(
        uuid: UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0,
                UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF)
            )))
}

/// A complete run summary fixture; only the identity and times vary.
func makeSummary(runID: String, startedAtMs: Int64 = 1_000, endedAtMs: Int64 = 2_000) -> RunSummary {
    RunSummary(
        schemaVersion: 1,
        sdkVersion: "test",
        id: testRunID(runID),
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

/// Write `summary` into `directory` under the writer's filename grammar
/// (zero-padded start nanoseconds plus the `.run` extension).
@discardableResult
func writeSummary(_ summary: RunSummary, startNs: UInt64, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(String(format: "%019llu.run", startNs))
    try JSONEncoder().encode(summary).write(to: url)
    return url
}

/// A path that exists but is not a directory, so enumerating it fails with
/// something other than "no such file": the store's unreadable-directory
/// case, made deterministic.
func makeUnreadableDirectory(at url: URL) throws {
    try Data().write(to: url)
}

/// A report source over a fixed list of reports. Each pass offers every
/// report not yet taken, once; `.taken` removes one, `.retryLater` keeps it
/// for the next pass. Records how each report was finished and the most
/// reports that were ever out at once (offered but not yet finished).
final class MemoryReportSource: ReportSource, Sendable {
    struct Failure: Error {}

    private struct State {
        var pending: [IncomingReport]
        var finished: [Report.ID: IncomingReport.Disposition] = [:]
        var outstanding = 0
        var maxOutstanding = 0
        var offers = 0
    }

    private let state: UnfairLock<State>
    private let failsOnNext: Bool

    init(_ reports: [IncomingReport], failsOnNext: Bool = false) {
        state = UnfairLock(State(pending: reports))
        self.failsOnNext = failsOnNext
    }

    /// The last disposition each report got, by id.
    var finished: [Report.ID: IncomingReport.Disposition] { state.withLock { $0.finished } }
    var pendingIDs: [Report.ID] { state.withLock { $0.pending.map(\.id) } }
    var maxOutstanding: Int { state.withLock { $0.maxOutstanding } }
    var offers: Int { state.withLock { $0.offers } }

    func makeReader() -> Reader { Reader(source: self) }

    struct Reader: ReportReader {
        let source: MemoryReportSource
        private var offeredThisPass: Set<Report.ID> = []

        init(source: MemoryReportSource) {
            self.source = source
        }

        mutating func next() async throws -> IncomingReport? {
            if source.failsOnNext { throw Failure() }
            let alreadyOffered = offeredThisPass
            let report: IncomingReport? = source.state.withLock { state in
                guard let report = state.pending.first(where: { !alreadyOffered.contains($0.id) }) else {
                    return nil
                }
                state.outstanding += 1
                state.maxOutstanding = max(state.maxOutstanding, state.outstanding)
                state.offers += 1
                return report
            }
            if let report {
                offeredThisPass.insert(report.id)
            }
            return report
        }

        mutating func finish(_ report: IncomingReport, as disposition: IncomingReport.Disposition) async {
            source.state.withLock { state in
                state.outstanding -= 1
                state.finished[report.id] = disposition
                if disposition == .taken {
                    state.pending.removeAll { $0.id == report.id }
                }
            }
        }
    }
}

/// A report source offering one report, whose reader stops inside `next()`
/// until the test releases it, so a test can hold a take-in open.
final class BlockingReportSource: ReportSource, Sendable {
    private struct State {
        var isReading = false
        var readingWaiter: CheckedContinuation<Void, Never>?
        var isReleased = false
        var releaseWaiter: CheckedContinuation<Void, Never>?
    }

    private let state = UnfairLock(State())
    private let report: IncomingReport

    init(_ report: IncomingReport) {
        self.report = report
    }

    /// Returns once a reader is inside `next()`.
    func waitUntilReading() async {
        await withCheckedContinuation { continuation in
            let isReading = state.withLock { state -> Bool in
                if state.isReading { return true }
                state.readingWaiter = continuation
                return false
            }
            if isReading { continuation.resume() }
        }
    }

    func release() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isReleased = true
            defer { state.releaseWaiter = nil }
            return state.releaseWaiter
        }
        waiter?.resume()
    }

    func makeReader() -> Reader { Reader(source: self) }

    struct Reader: ReportReader {
        let source: BlockingReportSource
        private var offered = false

        init(source: BlockingReportSource) {
            self.source = source
        }

        mutating func next() async throws -> IncomingReport? {
            guard !offered else { return nil }
            offered = true
            let readingWaiter = source.state.withLock { state -> CheckedContinuation<Void, Never>? in
                state.isReading = true
                defer { state.readingWaiter = nil }
                return state.readingWaiter
            }
            readingWaiter?.resume()
            await withCheckedContinuation { continuation in
                let isReleased = source.state.withLock { state -> Bool in
                    if state.isReleased { return true }
                    state.releaseWaiter = continuation
                    return false
                }
                if isReleased { continuation.resume() }
            }
            return source.report
        }

        mutating func finish(_ report: IncomingReport, as disposition: IncomingReport.Disposition) async {}
    }
}
