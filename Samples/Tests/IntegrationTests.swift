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
import CrashTriggers
import IntegrationTestsHelper

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

#if !os(watchOS)

final class SignalTests: IntegrationTestBase {
    func testAbort() throws {
        try launchAndCrash(.signal_abort)

        let rawReport = try readPartialCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash?.error?.type, "signal")
        XCTAssertEqual(rawReport.crash?.error?.signal?.name, "SIGABRT")

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains("SIGABRT"))
    }

    func testTermination() throws {
        // Default (termination monitoring disabled)
        try launchAndInstall()
        try terminate()

        XCTAssertFalse(try hasCrashReport())

        // With termination monitoring enabled
        try launchAndInstall { config in
            config.isSigTermMonitoringEnabled = true
        }
        try terminate()

        let rawReport = try readPartialCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash?.error?.signal?.name, "SIGTERM")

        let appleReport = try launchAndReportCrash()
        print(appleReport)
        XCTAssertTrue(appleReport.contains("SIGTERM"))
    }
}

#endif

final class OtherTests: IntegrationTestBase {
    func testManyThreads() throws {
        try launchAndCrash(.other_manyThreads)

        let rawReport = try readPartialCrashReport()
        let crashedThread = rawReport.crash?.threads?.first(where: { $0.crashed })
        XCTAssertNotNil(crashedThread)
        let expectedFrame = crashedThread?.backtrace.contents.first(where: {
            $0.symbol_name?.contains(KSCrashStacktraceCheckFuncName) ?? false
        })
        XCTAssertNotNil(expectedFrame)

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains(KSCrashStacktraceCheckFuncName))
    }

    func testUserReportedNSException() throws {
        try launchAndMakeUserReports([.nsException])

        let rawReport = try readPartialCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash?.error?.type, "nsexception")
        XCTAssertEqual(rawReport.crash?.error?.reason, UserReportConfig.crashReason)
        XCTAssertEqual(rawReport.crash?.error?.nsexception?.name, UserReportConfig.crashName)
        XCTAssertTrue(rawReport.crash?.error?.nsexception?.userInfo?.contains("a = b") ?? false)
        XCTAssertGreaterThanOrEqual(rawReport.crash?.threads?.count ?? 0, 2, "Expected to have at least 2 threads")
        let backtraceFrame = rawReport.crashedThread?.backtrace.contents.first(where: {
            $0.symbol_name?.contains(KSCrashNSExceptionStacktraceFuncName) ?? false
        })
        XCTAssertNotNil(backtraceFrame)

        // Should not terminate app
        XCTAssertEqual(app.state, .runningForeground)

        app.terminate()
        let appleReport = try launchAndReportCrash()
        print(appleReport)
        XCTAssertTrue(appleReport.contains(UserReportConfig.crashName))
        XCTAssertTrue(appleReport.contains(UserReportConfig.crashReason))
        XCTAssertTrue(appleReport.contains(KSCrashNSExceptionStacktraceFuncName))
    }

    func testUserReport() throws {
        try launchAndMakeUserReports([.userException])

        let rawReport = try readPartialCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash?.error?.type, "user")
        XCTAssertEqual(rawReport.crash?.error?.reason, UserReportConfig.crashReason)
        XCTAssertEqual(rawReport.crash?.error?.user_reported?.name, UserReportConfig.crashName)
        XCTAssertEqual(rawReport.crash?.error?.user_reported?.backtrace, UserReportConfig.crashCustomStacktrace)
        XCTAssertGreaterThanOrEqual(rawReport.crash?.threads?.count ?? 0, 2, "Expected to have at least 2 threads")

        // Should not terminate app
        XCTAssertEqual(app.state, .runningForeground)

        app.terminate()
        let appleReport = try launchAndReportCrash()
        print(appleReport)
        XCTAssertTrue(appleReport.contains(UserReportConfig.crashName))
        XCTAssertTrue(appleReport.contains(UserReportConfig.crashReason))
    }
}

extension PartialCrashReport {
    var crashedThread: Crash.Thread? {
        return self.crash?.threads?.first(where: { $0.crashed })
    }

    func validate() throws {
        let crashedThread = self.crashedThread
        XCTAssertNotNil(crashedThread)
        XCTAssertGreaterThan(crashedThread?.backtrace.contents.count ?? 0, 0)
    }
}
