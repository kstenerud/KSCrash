//
//  SendConfiguration.swift
//
//  Created by Alexander Cohen on 2026-08-08.
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

import KSCrashReportModel

/// Configuration for a send.
public struct SendConfiguration: Sendable {
    /// The stages a run summary passes through, in order. An EMPTY pipeline
    /// is a purge: every pending summary trivially reaches the end, so it is
    /// deleted from disk and reported as delivered without any consumer
    /// receiving it. Add a stage before sending if you want the data.
    public var runSummaryPipeline: [AnyPipelineStage<RunSummary>]

    /// Whether delivered items carry their final payload in the result.
    /// Defaults to false, so a send never accumulates payloads in memory.
    public var includesDeliveredPayloads: Bool

    public init(
        runSummaryPipeline: [AnyPipelineStage<RunSummary>] = [],
        includesDeliveredPayloads: Bool = false
    ) {
        self.runSummaryPipeline = runSummaryPipeline
        self.includesDeliveredPayloads = includesDeliveredPayloads
    }
}
