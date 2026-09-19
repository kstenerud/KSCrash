//
//  Poller_Tests.swift
//
//  Created by Alexander Cohen on 2026-08-26.
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

import XCTest

@testable import KSCrashSwiftCore

final class Poller_Tests: XCTestCase {
    private let queue = DispatchQueue(label: "poller-tests")

    func test_invalidIntervals_yieldNoPoller() {
        for interval in [0, -1, .nan, .infinity, -.infinity] as [TimeInterval] {
            XCTAssertNil(Poller(every: interval, queue: queue) {}, "\(interval)")
        }
    }

    func test_validInterval_polls() throws {
        let fired = expectation(description: "handler fired")
        fired.assertForOverFulfill = false
        let poller = try XCTUnwrap(Poller(every: 0.05, queue: queue) { fired.fulfill() })
        poller.start()
        wait(for: [fired], timeout: 5)
        poller.stop()
    }

    func test_hugeInterval_isBoundedByTheTimersArithmetic() throws {
        // Scheduling converts the interval to Int64 nanoseconds. An interval
        // past that must surface as absence from the init, never as a trap
        // inside start().
        XCTAssertNil(Poller(every: .greatestFiniteMagnitude, queue: queue) {})
        XCTAssertNil(Poller(every: 1e12, queue: queue) {})
        let poller = try XCTUnwrap(Poller(every: 1e9, queue: queue) {})
        poller.start()
        poller.stop()
    }

    func test_minuteScaleInterval_isAccepted_withoutTrapping() {
        // 60s leeway nanoseconds overflow a 32-bit Int (arm64_32 watches);
        // the conversion must saturate, not trap.
        XCTAssertNotNil(Poller(every: 60, queue: queue) {})
    }
}
