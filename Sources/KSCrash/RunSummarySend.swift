//
//  RunSummarySend.swift
//
//  Created by Alexander Cohen on 2026-08-10.
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
import KSCrashReportModel

/// The run-summary send: the pending runs, newest first, through the
/// pipeline, with per-run outcomes. The loop itself is `SendDriver`'s; this
/// is what a run summary is to it.
enum RunSummarySend {
    static let claims = SendClaims<String>()

    static func send(
        store: Store?,
        pipeline: [AnyPipelineStage<RunSummary>],
        maxRunCount: Int,
        only selection: Set<String>? = nil,
        claims: SendClaims<String> = RunSummarySend.claims
    ) async throws -> SendResult<RunSummary> {
        try await SendDriver.send(
            store: store,
            kind: SendKind(
                label: "run summary",
                list: { try $0.snapshotRuns() },
                id: { $0.runID },
                // nil covers artifact-only runs (nothing left to send) as
                // well as stale entries and unreadable shared files.
                read: { $0.summary(of: $1) },
                remove: { try $0.removeSummary(of: $1) }
            ),
            pipeline: pipeline,
            maxRunCount: maxRunCount,
            only: selection,
            claims: claims
        )
    }
}
