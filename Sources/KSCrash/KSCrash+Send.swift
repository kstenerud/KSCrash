//
//  KSCrash+Send.swift
//
//  Created by Alexander Cohen on 2026-08-09.
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
    /// Send the pending run summaries through
    /// `configuration.runSummaryPipeline`, one at a time, newest run first,
    /// and return the per-run outcomes. Summaries are only ever handed to
    /// stages one at a time; the result carries payloads only when
    /// `configuration.includesDeliveredPayloads` is set. Concurrent sends
    /// partition the pending runs between them. Throws only when the run
    /// store cannot be read; cancellation stops between runs and returns the
    /// outcomes so far. Before `install`, the result is empty.
    public func sendRunSummaries(with configuration: SendConfiguration) async throws -> SendResult<RunSummary> {
        try await RunSummarySend.send(
            store: Self.runDataStore(reportStore: reportStore),
            pipeline: configuration.runSummaryPipeline,
            includesDeliveredPayloads: configuration.includesDeliveredPayloads
        )
    }

    /// Like `sendRunSummaries(with:)`, but only for the runs whose ids are in
    /// `ids`. Every other pending run is untouched and absent from the result.
    /// Unknown ids match nothing; an empty `ids` sends nothing.
    public func sendRunSummaries(
        with configuration: SendConfiguration,
        only ids: [String]
    ) async throws -> SendResult<RunSummary> {
        try await RunSummarySend.send(
            store: Self.runDataStore(reportStore: reportStore),
            pipeline: configuration.runSummaryPipeline,
            includesDeliveredPayloads: configuration.includesDeliveredPayloads,
            only: Set(ids)
        )
    }

    // Built fresh per send on purpose: the store is a stateless value snapshot
    // of install-time configuration (paths resolve to NULL before install, so
    // early sends correctly see no store), and cross-send coordination lives
    // in SendClaims, not here. Nothing is gained by caching it.
    private static func runDataStore(reportStore: CrashReportStore?) -> RunDataStore? {
        // The resolved paths can be non-NULL while an install is still in
        // flight or after one failed partway; a nonnil reportStore is what
        // marks a completed install, and it also carries the reclaim. Without
        // it there is no store, and the send stays empty as documented.
        guard let reportStore,
            let runsPath = kscrash_getRunSummariesPath(),
            let sidecarsPath = kscrash_getRunSidecarsPath()
        else {
            return nil
        }
        let liveRunID = String(cString: kscrash_getRunID())
        return RunDataStore(
            runsDirectory: URL(fileURLWithPath: String(cString: runsPath), isDirectory: true),
            runSidecarsDirectory: URL(fileURLWithPath: String(cString: sidecarsPath), isDirectory: true),
            maxRunCount: Int(kscrash_getMaxRunSummaryCount()),
            liveRunID: liveRunID.isEmpty ? nil : liveRunID,
            reclaim: { reportStore.reclaimOrphanedRunData() }
        )
    }
}
