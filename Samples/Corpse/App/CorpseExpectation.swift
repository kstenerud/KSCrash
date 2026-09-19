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
import Foundation
import KSCrashReportModel

/// One termination kind: how to die, and what the delivered report should say.
///
/// The pairing is the test. A segfault that arrives classified as a hang is a
/// worse failure than no report at all, because it would silently misattribute
/// every crash of that kind in the field.
///
/// Every case here must be a termination the *system* delivers. Anything the app
/// does to itself, a self-sent SIGKILL above all, never reaches the extension,
/// because the extension exists only because the OS decided to kill us.
struct CorpseExpectation {
    let triggerID: String
    let errorType: CrashErrorType
    /// Seconds to wait for the app to die before the test calls it a failure.
    let deadline: TimeInterval

    func matches(_ report: Report) -> Bool {
        report.crash.error.type == errorType
    }

    /// Reused from the sample's trigger library wherever the existing trigger
    /// already produces a real, system-delivered termination.
    static let reusingExistingTriggers: [CorpseExpectation] = [
        .init(triggerID: CrashTriggerId.mach_badAccess.rawValue, errorType: .mach, deadline: 20),
        .init(triggerID: CrashTriggerId.mach_busError.rawValue, errorType: .mach, deadline: 20),
        .init(
            triggerID: CrashTriggerId.mach_illegalInstruction.rawValue, errorType: .mach,
            deadline: 20),
        .init(triggerID: CrashTriggerId.signal_abort.rawValue, errorType: .signal, deadline: 20),
        .init(
            triggerID: CrashTriggerId.nsException_genericNSException.rawValue,
            errorType: .nsexception, deadline: 20),
        .init(
            triggerID: CrashTriggerId.cpp_runtimeException.rawValue, errorType: .cppException,
            deadline: 20),
        // Crashes off the main thread, so subject-thread selection is exercised
        // rather than assumed.
        .init(
            triggerID: CrashTriggerId.cpp_runtimeExceptionBackgroundThread.rawValue,
            errorType: .cppException, deadline: 20),
    ]
}
