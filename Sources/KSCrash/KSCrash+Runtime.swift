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
import KSCrashRecordingCore
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
        sessionRecorder.currentSessionID
    }

    /// Why the previous run ended. `.none` before install.
    public var previousTerminationReason: TerminationReason {
        TerminationReason(
            rawValue: String(cString: kstermination_reasonToString(kscrash_getPreviousTerminationReason())))
    }

    /// Record the active user; nil clears it. A session boundary: reports and
    /// run summaries attribute what follows to this user.
    ///
    /// No effect before install. An id longer than the session record's
    /// limit is truncated on a character boundary, so every artifact
    /// (reports, run summaries, sessions) carries the identical value.
    public func setUserID(_ userID: String?) {
        let userID = Self.truncatedUserID(userID)
        userIDLock.withLock { _ in
            metadata[KSCRASH_USERID_KEY] = userID
            sessionRecorder.observeUser(userID)
        }
    }

    /// The longest prefix that fits the session record's user field as valid
    /// UTF-8. Truncating here, before the sinks, is what keeps the metadata
    /// store (reject-over-limit) and the session writer (truncate-over-limit)
    /// in agreement.
    private static func truncatedUserID(_ userID: String?) -> String? {
        let maxBytes = Int(KSSESSION_MAX_USER_LENGTH) - 1
        guard let userID, userID.utf8.count > maxBytes else { return userID }
        var bytes = Data(userID.utf8.prefix(maxBytes))
        while !bytes.isEmpty, String(data: bytes, encoding: .utf8) == nil {
            bytes.removeLast()
        }
        return String(data: bytes, encoding: .utf8)
    }

    /// Report a custom exception, as user-reported crash reports do.
    /// `stackTrace` frames are recorded as given; `terminateProgram` ends the
    /// process after the report is written, as a crash would.
    // The monitor's stack capture counts this frame: @inline(never) keeps it
    // from dissolving into the caller, and the trailing thwart keeps the
    // report call out of tail position so optimized builds keep the frame.
    @inline(never)
    public func reportException(
        _ name: String, reason: String?, language: String?, lineOfCode: String?, stackTrace: [String]?,
        logAllThreads: Bool, terminateProgram: Bool
    ) {
        let frames = stackTrace.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        kscrash_reportUserException(name, reason, language, lineOfCode, frames, logAllThreads, terminateProgram)
        kscrash_thwartTailCallOptimisation()
    }

    /// Report an NSException as if the NSException monitor had caught it.
    /// Needs `.nsExceptions` in the installed monitors.
    // Frame-counted like the user-report wrapper above.
    @inline(never)
    public func reportException(_ exception: NSException, logAllThreads: Bool) {
        kscrash_reportNSException(exception, logAllThreads, 1)
        kscrash_thwartTailCallOptimisation()
    }
}
