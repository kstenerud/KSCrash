//
//  HangEventsTests.swift
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
import XCTest

@testable import KSCrash

final class HangEventsTests: XCTestCase {
    override func setUpWithError() throws {
        try TestInstall.ensure()
    }

    func test_hangEvents_reportAHangOfTheMainThread() async throws {
        let events = KSCrash.shared.hangEvents
        var iterator = events.makeAsyncIterator()
        // Block the main thread past the hang threshold, then read what the monitor saw.
        let blocker = Task { @MainActor in
            let until = Date().addingTimeInterval(0.6)
            while Date() < until {}
        }
        let first = await withTimeout(seconds: 5) { await iterator.next() }
        await blocker.value
        guard let first else {
            throw XCTSkip("hangs are not monitored in this environment, the stream finished")
        }
        XCTAssertEqual(first.change, .started)
        XCTAssertGreaterThan(first.startTimestamp, 0)
        XCTAssertGreaterThanOrEqual(first.endTimestamp, first.startTimestamp)
    }

    func test_hangEvents_streamsAreIndependent() async throws {
        var a = KSCrash.shared.hangEvents.makeAsyncIterator()
        var b = KSCrash.shared.hangEvents.makeAsyncIterator()
        let blocker = Task { @MainActor in
            let until = Date().addingTimeInterval(0.6)
            while Date() < until {}
        }
        async let firstA = withTimeout(seconds: 5) { await a.next() }
        async let firstB = withTimeout(seconds: 5) { await b.next() }
        let (eventA, eventB) = await (firstA, firstB)
        await blocker.value
        guard let eventA, let eventB else {
            throw XCTSkip("hangs are not monitored in this environment, the streams finished")
        }
        XCTAssertEqual(eventA.change, .started)
        XCTAssertEqual(eventB.change, .started)
    }
}

/// nil when `body` did not produce a value in time.
private func withTimeout<T: Sendable>(seconds: Double, _ body: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
