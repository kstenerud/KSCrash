//
//  UnsafeCrashTimeCallbacks.swift
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

import KSCrashRecording
import KSCrashRecordingCore

/// The C monitor context handed to `willWriteReport`.
public typealias MonitorContext = KSCrash_MonitorContext

/// Runs inside the crash handler: other threads are suspended and the process
/// is about to die. Nothing here may allocate, lock, or touch the Swift or
/// Objective-C runtimes; `plan` says what is safe for the event being handled.
public struct UnsafeCrashTimeCallbacks: Sendable {
    /// Before a report is written; the plan may be changed, including to skip the report.
    public typealias WillWriteReport =
        @convention(c) (
            UnsafeMutablePointer<ExceptionHandlingPlan>, UnsafePointer<MonitorContext>
        ) -> Void
    /// While the report is written; the writer adds to the report's `user` section.
    public typealias IsWritingReport =
        @convention(c) (
            UnsafePointer<ExceptionHandlingPlan>, UnsafePointer<ReportWriter>
        ) -> Void
    /// After the report is written; the second argument is the report's id.
    public typealias DidWriteReport =
        @convention(c) (UnsafePointer<ExceptionHandlingPlan>, UnsafePointer<CChar>) -> Void

    public var willWriteReport: WillWriteReport?
    public var isWritingReport: IsWritingReport?
    public var didWriteReport: DidWriteReport?

    public init(
        willWriteReport: WillWriteReport? = nil,
        isWritingReport: IsWritingReport? = nil,
        didWriteReport: DidWriteReport? = nil
    ) {
        self.willWriteReport = willWriteReport
        self.isWritingReport = isWritingReport
        self.didWriteReport = didWriteReport
    }
}
