//
//  ReportSend.swift
//
//  Created by Alexander Cohen on 2026-08-15.
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

/// The report send: the pending reports, newest first, through the pipeline,
/// with per-report outcomes. The loop itself is `SendDriver`'s; this is what
/// a report is to it.
enum ReportSend {
    static let claims = SendClaims<ReportID>()

    static func send(
        store: Store?,
        pipeline: [AnyPipelineStage<Report>],
        only selection: Set<ReportID>? = nil,
        claims: SendClaims<ReportID> = ReportSend.claims
    ) async throws -> SendResult<Report> {
        try await SendDriver.send(
            store: store,
            kind: SendKind(
                label: "report",
                list: { try $0.snapshotReportIDs() },
                id: { $0 },
                read: { store, id in
                    // A current-run report may still be updated (an
                    // unresolved watchdog hang, for example), so the bulk
                    // send skips it; an id named explicitly in the selection
                    // is a deliberate choice and is always sent. The peek
                    // decides from the report file alone, so the common case
                    // never reads or stitches the live run.
                    if selection == nil, let live = store.liveRunID, store.runID(of: id) == live {
                        return nil
                    }
                    guard let report = try store.report(id) else {
                        return nil
                    }
                    // The decoded run is re-checked because a report torn at
                    // peek time (no readable run_id yet) can finish writing
                    // before the full read.
                    if selection == nil, let live = store.liveRunID, report.report.runId == live {
                        return nil
                    }
                    return report
                },
                remove: { try $0.removeReport($1) }
            ),
            pipeline: pipeline,
            only: selection,
            claims: claims
        )
    }
}
