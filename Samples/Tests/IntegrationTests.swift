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

import CrashTriggers
import IntegrationTestsHelper
import KSCrashDemangleFilter
import Report
import SampleUI
import XCTest

final class NSExceptionTests: IntegrationTestBase {
    func testGenericException() throws {
        try launchAndCrash(.nsException_genericNSException)

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.reason, "Test")

        // Exception backtrace should be in last_exception_backtrace, not the crashed thread
        let exceptionBt = rawReport.crash.lastExceptionBacktrace
        XCTAssertNotNil(exceptionBt, "NSException crash should have last_exception_backtrace")
        XCTAssertGreaterThan(
            exceptionBt?.contents.count ?? 0, 0, "last_exception_backtrace should have frames")

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains("reason: 'Test'"))
        XCTAssertTrue(
            appleReport.contains("Last Exception Backtrace:"),
            "Apple format should contain 'Last Exception Backtrace:' section")
    }

    func testDontRecordAllThreads() throws {
        try launchAndCrash(
            .nsException_genericNSException,
            installOverride: { (configuration: inout InstallConfig) in
                configuration.shouldRecordAllThreads = false
            })

        let rawData = try readRawCrashReportData()
        print(String(data: rawData, encoding: .utf8) ?? "<failed to read raw data>")
        let rawReport = try decodeCrashReport(reportData: rawData)
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .nsexception)
        XCTAssertEqual(rawReport.crash.error.reason, "Test")
        XCTAssertEqual(rawReport.crash.threads?.count, 1)

        let exceptionBt = rawReport.crash.lastExceptionBacktrace
        XCTAssertNotNil(exceptionBt, "NSException crash should have last_exception_backtrace")
        XCTAssertGreaterThan(
            exceptionBt?.contents.count ?? 0, 0, "last_exception_backtrace should have frames")

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains("reason: 'Test'"))
        XCTAssertTrue(
            appleReport.contains("Last Exception Backtrace:"),
            "Apple format should contain 'Last Exception Backtrace:' section")
    }
}

#if os(iOS)

    final class MachTests: IntegrationTestBase {
        func testBadAccess() throws {
            try launchAndCrash(.mach_badAccess)

            let rawReport = try readCrashReport()
            try rawReport.validate()
            XCTAssertEqual(rawReport.crash.error.type, .mach)
            XCTAssertNil(
                rawReport.crash.lastExceptionBacktrace,
                "Mach crash should not have last_exception_backtrace")

            let appleReport = try launchAndReportCrash()
            XCTAssertTrue(appleReport.contains("SIGSEGV"))
            XCTAssertFalse(
                appleReport.contains("Last Exception Backtrace:"),
                "Apple format should not contain 'Last Exception Backtrace:' for mach crashes")
        }
    }

#endif

final class CppTests: IntegrationTestBase {
    func testRuntimeException() throws {
        try launchAndCrash(.cpp_runtimeException)

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .cppException)

        // Exception backtrace should be in last_exception_backtrace
        let exceptionBt = rawReport.crash.lastExceptionBacktrace
        XCTAssertNotNil(exceptionBt, "C++ exception crash should have last_exception_backtrace")
        let topSymbol = exceptionBt?.contents
            .compactMap(\.symbolName).first
            .flatMap(CrashReportFilterDemangle.demangledCppSymbol)
        XCTAssertEqual(topSymbol, "sample_namespace::Report::crash()")

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains("C++ exception"))
        XCTAssertTrue(
            appleReport.contains("Last Exception Backtrace:"),
            "Apple format should contain 'Last Exception Backtrace:' section")
    }

    func testRuntimeExceptionBackgroundThread() throws {
        try launchAndCrash(
            .cpp_runtimeExceptionBackgroundThread,
            installOverride: { (configuration: inout InstallConfig) in
                configuration.isCxaThrowEnabled = false
            })

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .cppException)

        // Even without __cxa_throw, the terminate handler captures an approximate exception backtrace
        let exceptionBt = rawReport.crash.lastExceptionBacktrace
        XCTAssertNotNil(exceptionBt, "C++ exception crash should have last_exception_backtrace")
        let topSymbol = exceptionBt?.contents
            .compactMap(\.symbolName).first
            .flatMap(CrashReportFilterDemangle.demangledCppSymbol)
        XCTAssertEqual(topSymbol, "sample_namespace::Report::crash()")

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains("C++ exception"))
        XCTAssertTrue(
            appleReport.contains("Last Exception Backtrace:"),
            "Apple format should contain 'Last Exception Backtrace:' section")
    }
}

#if !os(watchOS)

    final class SignalTests: IntegrationTestBase {
        func testAbort() throws {
            try launchAndCrash(.signal_abort)

            let rawReport = try readCrashReport()
            try rawReport.validate()
            XCTAssertEqual(rawReport.crash.error.type, .signal)
            XCTAssertEqual(rawReport.crash.error.signal?.name, "SIGABRT")
            XCTAssertNil(
                rawReport.crash.lastExceptionBacktrace,
                "Signal crash should not have last_exception_backtrace")

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

            let rawReport = try readCrashReport()
            try rawReport.validate()
            XCTAssertEqual(rawReport.crash.error.signal?.name, "SIGTERM")

            let appleReport = try launchAndReportCrash()
            print(appleReport)
            XCTAssertTrue(appleReport.contains("SIGTERM"))
        }
    }

#endif

#if !os(watchOS)
    final class OtherTests: IntegrationTestBase {
        func testManyThreads() throws {
            try launchAndCrash(.other_manyThreads)

            let rawReport = try readCrashReport()
            let crashedThread = rawReport.crashedThread
            XCTAssertNotNil(crashedThread)
            let expectedFrame = crashedThread?.backtrace?.contents.first(where: {
                $0.symbolName?.contains(KSCrashStacktraceCheckFuncName) ?? false
            })
            XCTAssertNotNil(expectedFrame)

            let threadStates = [
                "TH_STATE_RUNNING", "TH_STATE_STOPPED", "TH_STATE_WAITING",
                "TH_STATE_UNINTERRUPTIBLE", "TH_STATE_HALTED",
            ]
            for thread in rawReport.crash.threads ?? [] {
                let threadState = thread.state ?? ""
                XCTAssertTrue(threadStates.contains(threadState))
            }

            let appleReport = try launchAndReportCrash()
            XCTAssertTrue(appleReport.contains(KSCrashStacktraceCheckFuncName))
        }
    }
#endif

final class UserReportedTests: IntegrationTestBase {

    static let crashName = "Crash Name"
    static let crashReason = "Crash Reason"
    static let crashLanguage = "Crash Language"
    static let crashLineOfCode = "108"
    static let crashCustomStacktrace = ["func01", "func02", "func03"]

    func testUserReportedNSException() throws {
        try launchAndMakeUserReport(
            nsException: .init(
                name: Self.crashName,
                reason: Self.crashReason,
                userInfo: ["a": "b"],
                logAllThreads: true,
                addStacktrace: true
            ))

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .nsexception)
        XCTAssertEqual(rawReport.crash.error.reason, Self.crashReason)
        XCTAssertEqual(rawReport.crash.error.nsexception?.name, Self.crashName)
        XCTAssertTrue(rawReport.crash.error.nsexception?.userInfo?.contains("a = b") ?? false)
        XCTAssertGreaterThanOrEqual(rawReport.crash.threads?.count ?? 0, 2, "Expected to have at least 2 threads")

        // Exception backtrace should be in last_exception_backtrace
        let exceptionBt = rawReport.crash.lastExceptionBacktrace
        XCTAssertNotNil(exceptionBt, "User-reported NSException should have last_exception_backtrace")
        let backtraceFrame = exceptionBt?.contents.first(where: {
            $0.symbolName?.contains(KSCrashNSExceptionStacktraceFuncName) ?? false
        })
        XCTAssertNotNil(backtraceFrame, "last_exception_backtrace should have the specific symbol")

        XCTAssertEqual(app.state, .runningForeground, "Should not terminate app")
        app.terminate()

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains(Self.crashName))
        XCTAssertTrue(appleReport.contains(Self.crashReason))
        XCTAssertTrue(appleReport.contains(KSCrashNSExceptionStacktraceFuncName))
        XCTAssertTrue(
            appleReport.contains("Last Exception Backtrace:"),
            "Apple format should contain 'Last Exception Backtrace:' section")

        let state = try readState()
        XCTAssertFalse(state.crashedLastLaunch)
    }

    func testUserReportedNSException_WithoutStacktrace() throws {
        try launchAndMakeUserReport(
            nsException: .init(
                name: Self.crashName,
                reason: Self.crashReason,
                userInfo: nil,
                logAllThreads: true,
                addStacktrace: false  // <- Key difference
            ))

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .nsexception)
        XCTAssertEqual(rawReport.crash.error.reason, Self.crashReason)
        XCTAssertEqual(rawReport.crash.error.nsexception?.name, Self.crashName)
        XCTAssertGreaterThanOrEqual(rawReport.crash.threads?.count ?? 0, 2, "Expected to have at least 2 threads")

        // Exception backtrace (from callStackReturnAddresses) goes to last_exception_backtrace
        XCTAssertNotNil(
            rawReport.crash.lastExceptionBacktrace,
            "User-reported NSException should have last_exception_backtrace")

        // Handler backtrace (crashed thread) should have the reporting function on top
        let topSymbol = rawReport.crashedThread?.backtrace?.contents
            .compactMap(\.symbolName).first
            .flatMap(CrashReportFilterDemangle.demangledSwiftSymbol)
        XCTAssertEqual(
            topSymbol, "IntegrationTestsHelper.UserReportConfig.NSExceptionReport.report() -> ()",
            "Stacktrace should exclude all KSCrash symbols and have reporting function on top")

        XCTAssertEqual(app.state, .runningForeground, "Should not terminate app")
    }

    func testUserReport() throws {
        try launchAndMakeUserReport(
            userException: .init(
                name: Self.crashName,
                reason: Self.crashReason,
                language: Self.crashLanguage,
                lineOfCode: Self.crashLineOfCode,
                stacktrace: Self.crashCustomStacktrace,
                logAllThreads: true,
                terminateProgram: false
            ))

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .user)
        XCTAssertEqual(rawReport.crash.error.reason, Self.crashReason)
        XCTAssertEqual(rawReport.crash.error.userReported?.name, Self.crashName)
        XCTAssertEqual(rawReport.crash.error.userReported?.backtrace, Self.crashCustomStacktrace)
        XCTAssertGreaterThanOrEqual(rawReport.crash.threads?.count ?? 0, 2, "Expected to have at least 2 threads")
        let topSymbol = rawReport.crashedThread?.backtrace?.contents
            .compactMap(\.symbolName).first
            .flatMap(CrashReportFilterDemangle.demangledSwiftSymbol)
        XCTAssertEqual(
            topSymbol, "IntegrationTestsHelper.UserReportConfig.UserException.report() -> ()",
            "Stacktrace should exclude all KSCrash symbols and have reporting function on top")

        XCTAssertEqual(app.state, .runningForeground, "Should not terminate app")
        app.terminate()

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains(Self.crashName))
        XCTAssertTrue(appleReport.contains(Self.crashReason))

        let state = try readState()
        XCTAssertFalse(state.crashedLastLaunch)
    }
}

extension Report.CrashReport where UserData == Report.NoUserData {
    var crashedThread: Report.CrashReport<UserData>.Thread? {
        if let thread = self.crash.crashedThread {
            return thread
        }
        return self.crash.threads?.first(where: { $0.crashed })
    }

    func validate() throws {
        let thread = self.crashedThread
        XCTAssertNotNil(thread)
        XCTAssertGreaterThan(thread?.backtrace?.contents.count ?? 0, 0)
    }
}
