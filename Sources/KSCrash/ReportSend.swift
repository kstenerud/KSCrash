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
import os

/// The report send: one call processes the pending reports, newest first,
/// through the pipeline, and returns per-report outcomes. Payloads exist one
/// at a time, inside the per-report loop, and are never accumulated.
enum ReportSend {

    // Pinned off the caller's actor wherever the attribute exists (Swift 6.2+);
    // older toolchains run nonisolated async functions off-actor by default, so
    // the guarantee holds under every supported compiler.
    #if hasAttribute(concurrent)
        @concurrent
    #endif
    static func send(
        store: Store?,
        pipeline: [AnyPipelineStage<Report>],
        includesDeliveredPayloads: Bool,
        maxRunCount: Int,
        only selection: Set<ReportID>? = nil,
        claims: SendClaims = .reports
    ) async throws -> SendResult<Report> {
        // Not installed (no resolved locations): an empty result rather than
        // an error, matching the summary send.
        guard let store else {
            return SendResult(items: [])
        }

        // Run-summary retention is enforced on every send path, so an app
        // that only ever sends reports still cannot grow `.run` files
        // without bound.
        store.pruneRunSummaries(keepingNewest: maxRunCount)

        var ids = try store.snapshot().reportIDs
        if let selection {
            // Unselected reports are not this send's items: untouched on disk
            // and absent from the result, exactly like reports claimed by a
            // concurrent send.
            ids = ids.filter { selection.contains($0) }
        }
        // However the send ends past this point (exhausted, cancelled, or a
        // crash of a stage's task), sweep once: the reclaim is reference-aware
        // and idempotent, so it is safe on every exit path.
        defer { store.reclaimOrphans() }

        var items: [SendResult<Report>.Item] = []
        for id in ids {
            // Between reports is the clean stopping point: no report is ever
            // half processed, and everything not yet sent stays for next time.
            if Task.isCancelled {
                break
            }
            // Claiming is what lets concurrent sends partition the pending
            // work instead of duplicating it: a report another send holds is
            // not this send's item and is not reported by it.
            guard claims.claim(String(id)) else {
                continue
            }
            defer { claims.release(String(id)) }

            let start = DispatchTime.now()

            // A nil read filters stale snapshot entries (another send can
            // have delivered and deleted a report between our snapshot and
            // our claim) and reports that cannot be read or decoded right
            // now, which stay on disk for the next send. Under the claim,
            // deletes are ours alone, so the check is race-free.
            guard let report = store.report(id) else {
                continue
            }

            // A current-run report may still be updated (an unresolved
            // watchdog hang, for example), so the bulk send skips it; an id
            // named explicitly in the selection is a deliberate choice and is
            // always sent.
            if selection == nil, let live = store.liveRunID, report.report.runId == live {
                continue
            }

            let outcome: SendResult<Report>.Outcome
            switch await runPipeline(report, through: pipeline) {
            case .delivered(let final):
                remove(id, from: store)
                outcome = .delivered(includesDeliveredPayloads ? final : nil)
            case .discarded:
                remove(id, from: store)
                outcome = .discarded
            case .kept(let error):
                outcome = .kept(error)
            }
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            items.append(
                SendResult.Item(
                    id: String(id),
                    outcome: outcome,
                    duration: TimeInterval(elapsedNs) / 1_000_000_000
                ))
        }
        return SendResult(items: items)
    }

    // A failed delete is logged, not thrown: the report was already
    // processed, and the file will be re-sent or pruned later, which is the
    // retry-safe direction.
    private static func remove(_ id: ReportID, from store: Store) {
        do {
            try store.removeReport(id)
        } catch {
            os_log(.error, "Failed to delete report %lld", id)
        }
    }
}
