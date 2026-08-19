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

/// A complete run summary fixture; only the identity and times vary.
func makeSummary(runID: String, startedAtMs: Int64 = 1_000, endedAtMs: Int64 = 2_000) -> RunSummary {
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
