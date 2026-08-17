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
import KSCrashSwiftCore
import os

/// The run-summary send: one call processes the pending runs, newest first,
/// through the pipeline, and returns per-run outcomes. Payloads exist one at a
/// time, inside the per-run loop, and are never accumulated.
enum RunSummarySend {

    // Pinned off the caller's actor wherever the attribute exists (Swift 6.2+);
    // older toolchains run nonisolated async functions off-actor by default, so
    // the guarantee holds under every supported compiler.
    #if hasAttribute(concurrent)
        @concurrent
    #endif
    static func send(
        store: Store?,
        pipeline: [AnyPipelineStage<RunSummary>],
        includesDeliveredPayloads: Bool,
        maxRunCount: Int,
        only selection: Set<String>? = nil,
        claims: SendClaims = .runSummaries
    ) async throws -> SendResult<RunSummary> {
        // A send with no stages can only mean a misconfigured caller, so it
        // throws regardless of install state instead of quietly purging.
        guard !pipeline.isEmpty else {
            throw SendError.emptyPipeline
        }

        // Not installed (no resolved locations): an empty result rather than
        // an error, matching the previous send's behavior.
        guard let store else {
            return SendResult(items: [])
        }

        // Retention is a send-path concern; pruning before the snapshot keeps
        // files that are about to be deleted out of it.
        store.pruneRunSummaries(keepingNewest: maxRunCount)

        var runs = try store.snapshot().runs
        if let selection {
            // Unselected runs are not this send's items: untouched on disk and
            // absent from the result, exactly like runs claimed by a
            // concurrent send.
            runs = runs.filter { selection.contains($0.runID) }
        }
        // However the send ends past this point (exhausted, cancelled, or a
        // crash of a stage's task), sweep once: the reclaim is reference-aware
        // and idempotent, so it is safe on every exit path.
        defer { store.reclaimOrphans() }

        var items: [SendResult<RunSummary>.Item] = []
        for run in runs {
            // Between runs is the clean stopping point: no run is ever half
            // processed, and everything not yet sent stays for next time.
            if Task.isCancelled {
                break
            }
            // Claiming is what lets concurrent sends partition the pending
            // work instead of duplicating it: a run another send holds is not
            // this send's item and is not reported by it.
            guard claims.claim(run.runID) else {
                continue
            }
            defer { claims.release(run.runID) }

            let start = DispatchTime.now()

            // A nil read filters two kinds of non-items: artifact-only runs
            // (nothing left to send), and stale snapshot entries, since
            // another send can have delivered and deleted a run between our
            // snapshot and our claim. Under the claim, deletes are ours
            // alone, so the check is race-free.
            guard let summary = store.summary(of: run) else {
                continue
            }

            let outcome: SendResult<RunSummary>.Outcome
            switch await runPipeline(summary, through: pipeline) {
            case .delivered(let final):
                removeSummary(of: run, from: store)
                outcome = .delivered(includesDeliveredPayloads ? final : nil)
            case .discarded:
                removeSummary(of: run, from: store)
                outcome = .discarded
            case .kept(let error):
                outcome = .kept(error)
            }
            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            items.append(
                SendResult.Item(
                    id: run.runID,
                    outcome: outcome,
                    duration: TimeInterval(elapsedNs) / 1_000_000_000
                ))
        }
        return SendResult(items: items)
    }

    // A failed delete is logged, not thrown: the summary was already
    // processed, and the file will be re-sent or pruned later, which is the
    // retry-safe direction.
    private static func removeSummary(of run: Run, from store: Store) {
        do {
            try store.removeSummary(of: run)
        } catch {
            os_log(.error, "Failed to delete run summary files for run %{public}@", run.runID)
        }
    }
}

/// The runs currently being processed by any send, so concurrent sends
/// partition the pending work: claiming is first-wins, and a claim is held
/// only while its run is being processed.
final class SendClaims: Sendable {
    static let runSummaries = SendClaims()
    static let reports = SendClaims()

    private let claimed = UnfairLock(Set<String>())

    func claim(_ id: String) -> Bool {
        claimed.withLock { $0.insert(id).inserted }
    }

    func release(_ id: String) {
        claimed.withLock { _ = $0.remove(id) }
    }
}
