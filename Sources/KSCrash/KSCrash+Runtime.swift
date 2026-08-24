//
//  KSCrash+Runtime.swift
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
import KSCrashRecording
import KSCrashReportModel

extension KSCrash {
    /// This run's id; nil before install.
    public var runID: RunSummary.ID? {
        RunSummary.ID(String(cString: kscrash_getRunID()))
    }

    /// The previous run's id; nil on a first launch or before install.
    public var previousRunID: RunSummary.ID? {
        RunSummary.ID(String(cString: kscrash_getLastRunID()))
    }

    /// The id of the open session; nil before one is recorded.
    public var sessionID: String? {
        kscrash_getSessionID().map { String(cString: $0) }
    }

    /// Why the previous run ended. `.none` before install.
    public var previousTerminationReason: TerminationReason {
        TerminationReason(
            rawValue: String(cString: kstermination_reasonToString(kscrash_getPreviousTerminationReason())))
    }

    /// Record the active user; nil clears it. A session boundary: reports and
    /// run summaries attribute what follows to this user.
    public func setUserID(_ userID: String?) {
        metadata[KSCRASH_USERID_KEY] = userID
        kscrash_notifyUserChanged(userID)
    }

    /// Report a custom exception, as user-reported crash reports do.
    /// `stackTrace` frames are recorded as given; `terminateProgram` ends the
    /// process after the report is written, as a crash would.
    public func reportException(
        _ name: String, reason: String?, language: String?, lineOfCode: String?, stackTrace: [String]?,
        logAllThreads: Bool, terminateProgram: Bool
    ) {
        let frames = stackTrace.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        kscrash_reportUserException(name, reason, language, lineOfCode, frames, logAllThreads, terminateProgram)
    }

    /// Report an NSException as if the NSException monitor had caught it.
    /// Needs `.nsExceptions` in the installed monitors.
    public func reportException(_ exception: NSException, logAllThreads: Bool) {
        kscrash_reportNSException(exception, logAllThreads)
    }
}
