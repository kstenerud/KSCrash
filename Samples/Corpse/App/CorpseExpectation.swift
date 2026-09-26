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
/// A corpse report is always typed `mach`: the extension sees the process the
/// way the kernel delivered its death. An uncaught Objective-C or C++ exception
/// ends in abort(), so it arrives as EXC_CRASH with SIGABRT, like abort() itself.
/// The Mach exception and the signal are what tell the kinds apart.
struct CorpseExpectation {
    let triggerID: String
    let machException: Int32
    let signal: Int32
    /// Seconds to wait for the app to die before the test calls it a failure.
    let deadline: TimeInterval
    /// Whether the trigger crashes a thread other than the main one, so that
    /// subject-thread selection is exercised rather than assumed.
    var crashesOffMainThread = false

    func matches(_ report: Report) -> Bool {
        report.crash.error.type == .mach
            && report.crash.error.mach?.exception == UInt64(machException)
            && report.crash.error.signal?.signal == UInt64(signal)
    }

    /// Reused from the sample's trigger library wherever the existing trigger
    /// already produces a real, system-delivered termination.
    static let reusingExistingTriggers: [CorpseExpectation] = [
        .init(
            triggerID: CrashTriggerId.mach_badAccess.rawValue, machException: EXC_BAD_ACCESS, signal: SIGSEGV,
            deadline: 20),
        .init(
            triggerID: CrashTriggerId.signal_abort.rawValue, machException: EXC_CRASH, signal: SIGABRT, deadline: 20
        ),
        .init(
            triggerID: CrashTriggerId.nsException_genericNSException.rawValue, machException: EXC_CRASH,
            signal: SIGABRT, deadline: 20),
        .init(
            triggerID: CrashTriggerId.cpp_runtimeExceptionBackgroundThread.rawValue, machException: EXC_CRASH,
            signal: SIGABRT, deadline: 20, crashesOffMainThread: true),
    ]
}
