//
//  MonitorsTests.swift
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

import KSCrashRecording
import XCTest

@testable import KSCrash

final class MonitorsTests: XCTestCase {
    func test_defaultIsEveryDetectorButZombies() {
        XCTAssertEqual(
            Monitors.default, [.machExceptions, .signals, .cppExceptions, .nsExceptions, .terminations, .hangs])
        XCTAssertFalse(Monitors.default.contains(.zombies))
        XCTAssertEqual(Monitors.all, Monitors.default.union(.zombies))
    }

    func test_mapsToTheCBits() {
        XCTAssertEqual(Monitors.hangs.cValue, .hang)
        XCTAssertEqual(Monitors.terminations.cValue, .termination)
        XCTAssertEqual(Monitors.zombies.cValue, .zombie)
        XCTAssertEqual(Monitors([]).cValue, [])
        XCTAssertEqual(Monitors.default.cValue, .default)
        XCTAssertEqual(Monitors.all.cValue, .all)
    }

    func test_setAlgebra() {
        let set: Monitors = [.default, .zombies]
        XCTAssertEqual(set, .all)
        XCTAssertEqual(set.subtracting(.zombies), .default)
    }
}
