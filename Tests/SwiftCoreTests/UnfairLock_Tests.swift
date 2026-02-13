//
//  UnfairLock_Tests.swift
//
//  Created by Alexander Cohen on 2026-02-05.
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

#if SWIFT_PACKAGE
    import SwiftCore
#endif

final class UnfairLockTests: XCTestCase {

    // MARK: - Generic (boxed value) API

    func testBoxedValueInit() {
        let lock = UnfairLock(42)
        let value = lock.withLock { $0 }
        XCTAssertEqual(value, 42)
    }

    func testBoxedValueMutation() {
        let lock = UnfairLock(0)
        lock.withLock { $0 = 99 }
        let value = lock.withLock { $0 }
        XCTAssertEqual(value, 99)
    }

    func testBoxedValueReturnsDerivedValue() {
        let lock = UnfairLock("hello")
        let count = lock.withLock { $0.count }
        XCTAssertEqual(count, 5)
    }

    func testBoxedStructMutation() {
        struct State {
            var a: Int = 0
            var b: String = ""
        }

        let lock = UnfairLock(State())
        lock.withLock {
            $0.a = 10
            $0.b = "done"
        }
        let state = lock.withLock { $0 }
        XCTAssertEqual(state.a, 10)
        XCTAssertEqual(state.b, "done")
    }

    func testBoxedValueConcurrentAccess() {
        let lock = UnfairLock(0)
        let iterations = 1000
        let threadCount = 10

        let group = DispatchGroup()
        let queue = DispatchQueue.global()

        for _ in 0..<threadCount {
            group.enter()
            queue.async {
                for _ in 0..<iterations {
                    lock.withLock { $0 += 1 }
                }
                group.leave()
            }
        }

        group.wait()
        let value = lock.withLock { $0 }
        XCTAssertEqual(value, iterations * threadCount)
    }

    // MARK: - Void convenience API

    func testVoidInit() {
        let lock = UnfairLock()
        var executed = false
        lock.withLock { executed = true }
        XCTAssertTrue(executed)
    }

    func testVoidWithLockReturnsValue() {
        let lock = UnfairLock()
        let result = lock.withLock { 42 }
        XCTAssertEqual(result, 42)
    }

    func testVoidConcurrentAccess() {
        let lock = UnfairLock()
        var counter = 0
        let iterations = 1000
        let threadCount = 10

        let group = DispatchGroup()
        let queue = DispatchQueue.global()

        for _ in 0..<threadCount {
            group.enter()
            queue.async {
                for _ in 0..<iterations {
                    lock.withLock { counter += 1 }
                }
                group.leave()
            }
        }

        group.wait()
        XCTAssertEqual(counter, iterations * threadCount)
    }
}
