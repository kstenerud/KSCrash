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

    @concurrent static func send(
        store: RunDataStore?,
        pipeline: [AnyPipelineStage<RunSummary>],
        includesDeliveredPayloads: Bool,
        only selection: Set<String>? = nil,
        claims: SendClaims = .runSummaries
    ) async throws -> SendResult<RunSummary> {
        // Not installed (no resolved locations): an empty result rather than
        // an error, matching the previous send's behavior.
        guard let store else {
            return SendResult(items: [])
        }

        var runs = try store.runs()
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

            // The on-disk check filters two kinds of non-items: artifact-only
            // runs (nothing left to send), and stale snapshot entries, since
            // another send can have delivered and deleted a run between our
            // snapshot and our claim while the snapshot's decoded summary
            // outlives the file. Under the claim, deletes are ours alone, so
            // the check is race-free.
            guard run.hasSummaryOnDisk, let summary = run.summary() else {
                continue
            }

            let outcome: SendResult<RunSummary>.Outcome
            switch await process(summary, pipeline: pipeline) {
            case .delivered(let final):
                removeSummary(of: run)
                outcome = .delivered(includesDeliveredPayloads ? final : nil)
            case .discarded:
                removeSummary(of: run)
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

    private enum ProcessOutcome {
        case delivered(RunSummary)
        case discarded
        case kept(any Error)
    }

    /// One summary through the pipeline. Per-item failures are deliberately
    /// silent (`.kept`) so one failing summary cannot end the send.
    private static func process(
        _ summary: RunSummary, pipeline: [AnyPipelineStage<RunSummary>]
    ) async -> ProcessOutcome {
        var summary = summary
        for stage in pipeline {
            do {
                guard let processed = try await stage.process(summary) else {
                    return .discarded
                }
                summary = processed
            } catch {
                return .kept(error)
            }
        }
        return .delivered(summary)
    }

    // A failed delete is logged, not thrown: the summary was already
    // processed, and the file will be re-sent or pruned later, which is the
    // retry-safe direction.
    private static func removeSummary(of run: RunStore) {
        do {
            try run.removeSummary()
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

    private let claimed = UnfairLock(Set<String>())

    func claim(_ id: String) -> Bool {
        claimed.withLock { $0.insert(id).inserted }
    }

    func release(_ id: String) {
        claimed.withLock { _ = $0.remove(id) }
    }
}
