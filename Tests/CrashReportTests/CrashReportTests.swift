//
//  CrashReportTests.swift
//
//  Created by Alexander Cohen on 2024-12-09.
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

import CrashReport
import XCTest

final class CrashReportTests: XCTestCase {
    func testCrashErrorTypeRawValues() {
        XCTAssertEqual(CrashErrorType.mach.rawValue, "mach")
        XCTAssertEqual(CrashErrorType.signal.rawValue, "signal")
        XCTAssertEqual(CrashErrorType.nsexception.rawValue, "nsexception")
        XCTAssertEqual(CrashErrorType.cppException.rawValue, "cpp_exception")
        XCTAssertEqual(CrashErrorType.deadlock.rawValue, "deadlock")
        XCTAssertEqual(CrashErrorType.user.rawValue, "user")
        XCTAssertEqual(CrashErrorType.memoryTermination.rawValue, "memory_termination")
    }

    func testCrashErrorTypeUnknown() {
        let unknown = CrashErrorType(rawValue: "some_future_type")
        XCTAssertEqual(unknown.rawValue, "some_future_type")
    }

    func testReportTypeRawValues() {
        XCTAssertEqual(ReportType.standard.rawValue, "standard")
        XCTAssertEqual(ReportType.minimal.rawValue, "minimal")
        XCTAssertEqual(ReportType.custom.rawValue, "custom")
    }

    func testBuildTypeRawValues() {
        XCTAssertEqual(BuildType.debug.rawValue, "debug")
        XCTAssertEqual(BuildType.release.rawValue, "release")
    }
}
