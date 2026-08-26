//
//  BacktraceTests.swift
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

final class BacktraceTests: XCTestCase {
    func test_capture_ofTheCurrentThread() throws {
        let backtrace = try XCTUnwrap(Backtrace.capture(thread: pthread_self(), maxFrames: 64))
        XCTAssertGreaterThan(backtrace.count, 0)
        XCTAssertEqual(backtrace.count, backtrace.addresses.count)
    }

    func test_capture_truncatesAtMaxFrames() throws {
        let backtrace = try XCTUnwrap(Backtrace.capture(thread: pthread_self(), maxFrames: 2))
        XCTAssertEqual(backtrace.count, 2)
        XCTAssertTrue(backtrace.isTruncated)
    }

    func test_capture_rejectsANonPositiveOrOversizedFrameBudget() {
        for maxFrames in [0, -1, Int.max] {
            XCTAssertNil(Backtrace.capture(thread: pthread_self(), maxFrames: maxFrames), "\(maxFrames)")
        }
    }

    func test_capture_ofTheCurrentMachThread() throws {
        let backtrace = try XCTUnwrap(Backtrace.capture(machThread: mach_thread_self(), maxFrames: 64))
        XCTAssertGreaterThan(backtrace.count, 0)
    }

    func test_symbolicate_namesAKnownFunction() throws {
        // Addresses are return addresses: the lookup backs up one instruction, so
        // a function's entry resolves to its predecessor and an address inside it to itself.
        let entry = UInt(bitPattern: dlsym(dlopen(nil, RTLD_NOW), "dispatch_async"))
        let inside = entry + 4
        let info = try XCTUnwrap(Backtrace.symbolicate(inside))
        // libdispatch exports aliases at the same address, so the address is the proof, not the name.
        XCTAssertEqual(info.symbolAddress, entry)
        XCTAssertNotNil(info.symbolName)
        XCTAssertEqual(info.returnAddress, inside)
        // Not pinned to libdispatch: a sanitizer runtime interposes the symbol and dlsym returns its copy.
        XCTAssertNotNil(info.imageName)
        XCTAssertNotNil(info.imageUUID)
        XCTAssertEqual(Backtrace.quickSymbolicate(inside)?.symbolAddress, entry)
        XCTAssertNil(Backtrace.symbolicate(0x1))
    }
}
