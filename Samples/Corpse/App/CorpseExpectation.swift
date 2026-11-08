//
//  CorpseExpectation.swift
//
//  Created by Alexander Cohen on 2026-09-19.
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
import Darwin
import Foundation
import KSCrashReportModel

/// One termination kind: how to die, and what the delivered report should say.
///
/// The pairing is the test. A segfault that arrives as an abort is a worse
/// failure than no report at all, because it would silently misattribute every
/// crash of that kind in the field.
///
/// Every case here must be a termination the *system* delivers. Anything the app
/// does to itself, a self-sent SIGKILL above all, never reaches the extension,
/// because the extension exists only because the OS decided to kill us.
///
/// The extension sees the process the way the kernel delivered its death, so
/// every corpse report carries a Mach exception and a signal. An uncaught
/// Objective-C or C++ exception ends in abort(), so it arrives as EXC_CRASH with
/// SIGABRT, like abort() itself; the report is then typed by the exception the
/// runtime libraries left in their `__crash_info` messages, as an in-process
/// report of that crash would be.
struct CorpseExpectation {
    let triggerID: String
    let errorType: CrashErrorType
    let machException: Int32
    let signal: Int32
    /// Whether the trigger crashes a thread other than the main one, so that
    /// subject-thread selection is exercised rather than assumed.
    var crashesOffMainThread = false
    /// The exception's name and reason, for a trigger that dies of one.
    var exceptionName: String? = nil
    var reason: String? = nil
    /// Whether the report must carry the exception's throw stack.
    var expectsThrowStack = false
    /// An image whose `__crash_info` message the report must carry: the image's
    /// path suffix and text the message contains.
    var crashInfo: (imageSuffix: String, contains: String)? = nil

    func matches(_ report: Report) -> Bool {
        report.crash.error.type == errorType
            && report.crash.error.mach?.exception == UInt64(machException)
            && report.crash.error.signal?.signal == UInt64(signal)
    }

    /// What the report is missing of the exception and crash info this
    /// trigger leaves behind; empty when it carries all of it.
    func contentFailures(_ report: Report) -> [String] {
        var failures: [String] = []
        let error = report.crash.error
        if let exceptionName {
            let actual = errorType == .cppException ? error.cppException?.name : error.nsexception?.name
            if actual != exceptionName {
                failures.append("exception name \(actual ?? "nil"), expected \(exceptionName)")
            }
        }
        if let reason, error.reason != reason {
            failures.append("reason \(error.reason ?? "nil"), expected \(reason)")
        }
        if expectsThrowStack && (report.crash.lastExceptionBacktrace?.contents.isEmpty ?? true) {
            failures.append("no last_exception_backtrace")
        }
        if let crashInfo {
            let message = report.binaryImages?.first { $0.name.hasSuffix(crashInfo.imageSuffix) }?.crashInfoMessage
            if message?.contains(crashInfo.contains) != true {
                failures.append(
                    "\(crashInfo.imageSuffix) crash_info_message is \(message.map { "\"\($0)\"" } ?? "nil"),"
                        + " expected it to contain \"\(crashInfo.contains)\"")
            }
        }
        return failures
    }

    /// Reused from the sample's trigger library wherever the existing trigger
    /// already produces a real, system-delivered termination.
    static let reusingExistingTriggers: [CorpseExpectation] = [
        .init(
            triggerID: CrashTriggerId.mach_badAccess.rawValue, errorType: .mach, machException: EXC_BAD_ACCESS,
            signal: SIGSEGV),
        .init(
            triggerID: CrashTriggerId.signal_abort.rawValue, errorType: .mach, machException: EXC_CRASH,
            signal: SIGABRT, crashInfo: (imageSuffix: "/libsystem_c.dylib", contains: "abort() called")),
        .init(
            triggerID: CrashTriggerId.nsException_genericNSException.rawValue, errorType: .nsexception,
            machException: EXC_CRASH, signal: SIGABRT, exceptionName: "NSGenericException", reason: "Test",
            expectsThrowStack: true),
        .init(
            triggerID: CrashTriggerId.cpp_runtimeExceptionBackgroundThread.rawValue, errorType: .cppException,
            machException: EXC_CRASH, signal: SIGABRT, crashesOffMainThread: true,
            exceptionName: "std::runtime_error", reason: "C++ exception"),
    ]
}
