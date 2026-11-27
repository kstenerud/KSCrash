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
import KSCrashRecording
import KSCrashReportModel
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

        let state = try readState()
        XCTAssertTrue(state.crashedLastLaunch)
        XCTAssertEqual(state.terminationReason, .crash)
    }

    func testNSExceptionSubclass() throws {
        try launchAndCrash(.nsException_nsExceptionSubclass)

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .nsexception)
        XCTAssertEqual(rawReport.crash.error.reason, "Subclass Test")
        XCTAssertEqual(rawReport.crash.error.nsexception?.name, "TestNSExceptionSubclass")
        XCTAssertNil(rawReport.crash.error.cppException)
        XCTAssertNotNil(rawReport.crash.lastExceptionBacktrace)

        let appleReport = try launchAndReportCrash()
        XCTAssertTrue(appleReport.contains("TestNSExceptionSubclass"))
        XCTAssertTrue(appleReport.contains("Subclass Test"))
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

        let state = try readState()
        XCTAssertTrue(state.crashedLastLaunch)
        XCTAssertEqual(state.terminationReason, .crash)
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

            let state = try readState()
            XCTAssertTrue(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .crash)
        }

        /// Regression test for https://github.com/kstenerud/KSCrash/issues/810
        /// mach.subcode was always 0 due to a 32-bit/64-bit struct mismatch in the
        /// Mach exception handler. Verify the fault address survives into the report.
        func testBadAccessSubcodePreserved() throws {
            try launchAndCrash(.mach_badAccessDeadbeef)

            let rawReport = try readCrashReport()
            try rawReport.validate()
            XCTAssertEqual(rawReport.crash.error.type, .mach)

            let mach = rawReport.crash.error.mach
            XCTAssertNotNil(mach)
            XCTAssertEqual(
                mach?.subcode, 0xDEAD_BEEF,
                "mach.subcode should contain the fault address (0xDEADBEEF)")
        }
    }

#endif

final class CppTests: IntegrationTestBase {
    func testRuntimeException() throws {
        try launchAndCrash(.cpp_runtimeException)

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .cppException)
        XCTAssertEqual(rawReport.crash.error.reason, "C++ exception")

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

        let state = try readState()
        XCTAssertTrue(state.crashedLastLaunch)
        XCTAssertEqual(state.terminationReason, .crash)
    }

    func testRuntimeExceptionWhileDyldLockHeld() throws {
        // Regression: the monitor unwinds to describe the exception, and the unwind can take the dyld read lock.
        // Doing that after the other threads are suspended deadlocked whenever one of them held the lock: no report,
        // and the process never exited. Only the simulator always takes the locked path, so only there is this test
        // guaranteed to catch the regression. On real devices, dyld usually answers lock-free, and this test
        // could pass either way (or at least we have not yet found a stable repro on real devices).
        try launchAndCrash(.cpp_runtimeExceptionDyldLock)

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .cppException)
        XCTAssertEqual(rawReport.crash.error.reason, "C++ exception")
    }

    func testObjectiveCObjectExceptionFallsBackToCPPMonitor() throws {
        // NSSetUncaughtExceptionHandler is only called for NSException objects, so arbitrary Objective-C object throws
        // should still be reported by the C++ monitor instead of being skipped as NSExceptions.
        try launchAndCrash(.cpp_objcObjectException)

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .cppException)
        XCTAssertNotNil(rawReport.crash.error.cppException?.name)
        XCTAssertNil(rawReport.crash.error.nsexception)
        XCTAssertNotNil(rawReport.crash.lastExceptionBacktrace)
    }

    func testObjectiveCObjectExceptionAfterCaughtCppUsesCurrentThrowSite() throws {
        // The C++ monitor must report the fatal Objective-C object's throw site, not the earlier C++ throw.
        try launchAndCrash(.cpp_objcObjectExceptionAfterCaughtCpp)

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .cppException)
        XCTAssertNil(rawReport.crash.error.nsexception)

        let exceptionBt = rawReport.crash.lastExceptionBacktrace
        XCTAssertNotNil(exceptionBt, "C++ exception crash should have last_exception_backtrace")
        XCTAssertGreaterThan(
            exceptionBt?.contents.count ?? 0, 0, "recomputed exception cursor should produce frames")

        // The backtrace must reach the @throw site near the top. The exact top frame is platform-dependent: on macOS
        // and devices it is the throw site itself, while on the simulator one extra objc_exception_throw frame can sit
        // above it (libobjc is not prebound there). Assert the throw site appears within the first few frames rather
        // than pinning the exact top, and that the earlier (already-handled) C++ throw site is not reused.
        let symbols = (exceptionBt?.contents ?? []).compactMap(\.symbolName)
        XCTAssertTrue(
            symbols.prefix(3).contains("+[KSCrashTriggersList trigger_cpp_objcObjectExceptionAfterCaughtCpp]"),
            "last_exception_backtrace must reach the @throw site near the top, got: \(symbols.prefix(3))")

        let demangled = symbols.compactMap(CrashReportFilterDemangle.demangledCppSymbol)
        XCTAssertFalse(
            demangled.contains("sample_namespace::Report::crash()"),
            "last_exception_backtrace must not reuse the earlier caught C++ exception")
    }

    func testRethrowPreservesOriginalThrowSite() throws {
        try launchAndCrash(.cpp_rethrowCaughtCpp)

        let raw = try readCrashReport()
        try raw.validate()
        XCTAssertEqual(raw.crash.error.type, .cppException)
        XCTAssertEqual(raw.crash.error.reason, "C++ exception")

        let threadSymbols = (try XCTUnwrap(raw.crashedThread?.backtrace)).contents.compactMap(\.symbolName)
        XCTAssertTrue(
            threadSymbols.contains("+[KSCrashTriggersList trigger_cpp_rethrowCaughtCpp]"),
            "Expected the crashed-thread backtrace to include the fatal rethrow site: \(threadSymbols)")

        let saved = (try XCTUnwrap(raw.crash.lastExceptionBacktrace)).contents.compactMap(\.symbolName)
        XCTAssertTrue(
            saved.contains(where: isCppCrashSymbol),
            "Expected the saved exception backtrace to include the original throw site: \(saved)")
    }

    func testRethrowOnBackgroundThreadPreservesOriginalThrowSite() throws {
        // The monitor is enabled on the main thread, so this checks that other threads record their throw sites.
        try launchAndCrash(.cpp_rethrowCaughtCppBackgroundThread)

        let raw = try readCrashReport()
        try raw.validate()
        XCTAssertEqual(raw.crash.error.type, .cppException)
        XCTAssertEqual(raw.crash.error.reason, "C++ exception")

        let crashed = (try XCTUnwrap(raw.crashedThread?.backtrace)).contents.compactMap(\.symbolName)
        XCTAssertTrue(
            crashed.contains("sampleRethrowOnBackgroundThread"),
            "Expected the crashed-thread backtrace to include the rethrow site: \(crashed)")

        let saved = (try XCTUnwrap(raw.crash.lastExceptionBacktrace)).contents.compactMap(\.symbolName)
        XCTAssertTrue(
            saved.contains(where: isCppCrashSymbol),
            "Expected the saved exception backtrace to include the original throw site: \(saved)")
    }

    func testRethrowOnWorkerPreservesThrowingThreadsOriginalSite() throws {
        try launchAndCrash(.cpp_rethrowOnWorker)

        let raw = try readCrashReport()
        try raw.validate()
        XCTAssertEqual(raw.crash.error.type, .cppException)
        XCTAssertEqual(raw.crash.error.reason, "C++ exception")

        let saved = (try XCTUnwrap(raw.crash.lastExceptionBacktrace)).contents.compactMap(\.symbolName)
        XCTAssertTrue(
            saved.contains(where: isCppCrashSymbol), "Missing original throw on the launching thread: \(saved)")

        let crashed = (try XCTUnwrap(raw.crashedThread?.backtrace)).contents.compactMap(\.symbolName)
        XCTAssertTrue(
            crashed.contains("sampleRethrowOnWorker"), "Missing rethrow site on the crashed worker: \(crashed)")
    }

    func testFinalExceptionPtrReleaseCallsDestructorOnWorker() throws {
        // The trigger only returns if the destructor ran once, on the worker, at final release.
        try launchAndRunTrigger(.cpp_releaseOnWorker)
    }

    func testUnhookedThrowAfterCaughtCppDoesNotReuseCaughtTrace() throws {
        try launchAndCrash(.cpp_unhookedAfterCaughtCpp)

        let raw = try readCrashReport()
        try raw.validate()
        XCTAssertEqual(raw.crash.error.type, .cppException)
        XCTAssertEqual(raw.crash.error.reason, "fatal unhooked throw")

        let symbols = (try XCTUnwrap(raw.crash.lastExceptionBacktrace)).contents.compactMap(\.symbolName)
        let thread = (try XCTUnwrap(raw.crashedThread?.backtrace)).contents.compactMap(\.symbolName)
        XCTAssertTrue(
            thread.contains("+[KSCrashTriggersList trigger_cpp_unhookedAfterCaughtCpp]"),
            "Expected the crashed-thread backtrace to include the fatal unhooked throw site: \(thread)")
        XCTAssertFalse(
            symbols.contains(where: isCppCrashSymbol),
            "Expected the saved exception backtrace to exclude the earlier caught exception’s throw site: \(symbols)")
    }

    func testTerminateWithoutActiveExceptionAfterCaughtCppUsesTerminateContext() throws {
        // A bare std::terminate() has no active exception. Report the terminate context, not the earlier throw.
        try launchAndCrash(.cpp_terminateAfterCaughtCpp)

        let rawReport = try readCrashReport()
        try rawReport.validate()
        XCTAssertEqual(rawReport.crash.error.type, .cppException)

        let exceptionBt = rawReport.crash.lastExceptionBacktrace
        XCTAssertNotNil(exceptionBt, "C++ terminate crash should have last_exception_backtrace")
        XCTAssertGreaterThan(
            exceptionBt?.contents.count ?? 0, 0, "recomputed exception cursor should produce frames")

        let demangled = (exceptionBt?.contents ?? [])
            .compactMap(\.symbolName)
            .compactMap(CrashReportFilterDemangle.demangledCppSymbol)
        XCTAssertFalse(
            demangled.contains("sample_namespace::Report::crash()"),
            "last_exception_backtrace must not reuse the earlier caught C++ exception")
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

        let state = try readState()
        XCTAssertTrue(state.crashedLastLaunch)
        XCTAssertEqual(state.terminationReason, .crash)
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

            let state = try readState()
            XCTAssertTrue(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .crash)
        }

        func testIgnoredSIGPIPEDoesNotProduceCrashReport() throws {
            // KSCrash must not turn an application/runtime-ignored signal into a reported crash.
            try launchAndRunTrigger(.signal_sigpipe) { configuration in
                configuration.ignoreSIGPIPEBeforeInstall = true
            }

            XCTAssertNotEqual(app.state, .notRunning)
            XCTAssertFalse(try hasCrashReport())
        }

        func testTermination() throws {
            // SIGTERM is caught to record a clean exit but no crash report is written
            try launchAndInstall()
            try terminate()

            XCTAssertFalse(try hasCrashReport())

            // Relaunch to check state — previous run should be classified as clean
            try launchAndInstall()
            let state = try readState()
            XCTAssertFalse(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .clean)
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

            let state = try readState()
            XCTAssertTrue(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .crash)
        }
    }
#endif

#if targetEnvironment(simulator)

    final class MemoryTests: IntegrationTestBase {
        func testOOM() throws {
            app.launchEnvironment["KSCRASH_SIM_MEMORY_TERMINATION_ENABLED"] = "1"
            try launchAndCrash(.memory_oom)

            _ = try launchAndReportCrash()
            let state = try readState()
            XCTAssertTrue(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .memoryLimit)
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
        XCTAssertEqual(rawReport.report.finalized, true, "Non-fatal report should be finalized at runtime")

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
        XCTAssertEqual(state.terminationReason, .clean)
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
        XCTAssertEqual(rawReport.report.finalized, true, "Non-fatal report should be finalized at runtime")

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
        XCTAssertEqual(rawReport.report.finalized, true, "Non-fatal report should be finalized at runtime")
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
        XCTAssertEqual(state.terminationReason, .clean)
    }
}

extension KSCrashReportModel.CrashReport where UserData == KSCrashReportModel.NoUserData {
    var crashedThread: KSCrashReportModel.CrashReport<UserData>.Thread? {
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

/// sample_namespace::Report::crash(), in the mangled form the report carries.
private let cppCrashMangledSymbol = "_ZN16sample_namespace6Report5crashEv"

/// Whether `symbol` is sample_namespace::Report::crash(), whole or a part the optimizer
/// split off it: clang outlines the throw into `<symbol>.cold.1`, and that frame is still
/// the function's own code.
private func isCppCrashSymbol(_ symbol: String?) -> Bool {
    guard let symbol else { return false }
    return symbol == cppCrashMangledSymbol || symbol.hasPrefix(cppCrashMangledSymbol + ".cold.")
}
