//
//  IntegrationTests.swift
//
//  Created by Nikolay Volosatov on 2024-07-21.
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
import SampleUI

final class NSExceptionTests: IntegrationTestBase {
    func testGenericException() throws {
        try launchAndCrash(.nsException_genericNSException)

        let rawReport = try readPartialCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash?.error?.reason, "Test")

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains("reason: 'Test'"))
    }
}

#if os(iOS)

final class MachTests: IntegrationTestBase {
    func testBadAccess() throws {
        try launchAndCrash(.mach_badAccess)

        let rawReport = try readPartialCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash?.error?.type, "mach")

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains("SIGSEGV"))
    }
}

#endif

final class CppTests: IntegrationTestBase {
    func testRuntimeException() throws {
        try launchAndCrash(.cpp_runtimeException)

        let rawReport = try readPartialCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash?.error?.type, "cpp_exception")

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains("C++ exception"))
    }
}

extension PartialCrashReport {
    func validate() throws {
        let crashedThread = self.crash?.threads?.first(where: { $0.crashed })
        XCTAssertNotNil(crashedThread)
        XCTAssertGreaterThan(crashedThread?.backtrace.contents.count ?? 0, 0)
    }
}
