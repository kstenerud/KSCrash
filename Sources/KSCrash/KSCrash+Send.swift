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
    /// stages one at a time, and never held in the result. Concurrent sends
    /// partition the pending runs between them. Throws only when the run
    /// store cannot be read; cancellation stops between runs and returns the
    /// outcomes so far. Before `install`, the result is empty. An empty
    /// `runSummaryPipeline` throws `SendError.emptyPipeline`.
    public func sendRunSummaries(with configuration: SendConfiguration) async throws -> SendResult<RunSummary> {
        try await RunSummarySend.send(
            store: Self.makeStore(),
            pipeline: configuration.runSummaryPipeline
        )
    }

    /// Like `sendRunSummaries(with:)`, but only for the runs whose ids are in
    /// `ids`. Every other pending run is untouched and absent from the result.
    /// Unknown ids match nothing; an empty `ids` sends nothing.
    public func sendRunSummaries(
        with configuration: SendConfiguration,
        only ids: [RunSummary.ID]
    ) async throws -> SendResult<RunSummary> {
        try await RunSummarySend.send(
            store: Self.makeStore(),
            pipeline: configuration.runSummaryPipeline,
            only: Set(ids)
        )
    }

    /// Send the pending crash reports through `configuration.reportPipeline`,
    /// one at a time, newest report first, and return the per-report
    /// outcomes. Reports are only ever handed to stages one at a time, and
    /// never held in the result. Reports from the
    /// current run are skipped, they may still be updated; use
    /// `sendReports(with:only:)` to send one deliberately. A report that does
    /// not decode is reported as kept, carrying the decode error, and stays on
    /// disk. Concurrent sends partition the pending reports between them.
    /// Throws only when the report store cannot be read; cancellation stops
    /// between reports and returns the outcomes so far. Before `install`, the
    /// result is empty. An empty `reportPipeline` throws
    /// `SendError.emptyPipeline`.
    public func sendReports(with configuration: SendConfiguration) async throws -> SendResult<Report> {
        try await ReportSend.send(
            store: Self.makeStore(),
            pipeline: configuration.reportPipeline
        )
    }

    /// Like `sendReports(with:)`, but only for the reports whose ids are in
    /// `ids` (the ids a previous result reported), and current-run reports
    /// are sent rather than skipped: naming an id is a deliberate choice.
    /// Every other pending report is untouched and absent from the result.
    /// Unknown ids match nothing; an empty `ids` sends nothing.
    public func sendReports(
        with configuration: SendConfiguration,
        only ids: [Report.ID]
    ) async throws -> SendResult<Report> {
        try await ReportSend.send(
            store: Self.makeStore(),
            pipeline: configuration.reportPipeline,
            only: Set(ids)
        )
    }

    // Built fresh per send on purpose: the store is a stateless value snapshot
    // of install-time configuration (paths resolve to NULL before install, so
    // early sends correctly see no store), and cross-send coordination lives
    // in SendClaims, not here. Nothing is gained by caching it.
    static func makeStore() -> Store? {
        guard kscrash_isInstalled(),
            let reportsPath = kscrash_getReportsPath(),
            let runsPath = kscrash_getRunSummariesPath(),
            let sidecarsPath = kscrash_getRunSidecarsPath(),
            let storeConfig = kscrash_getReportStoreConfiguration()
        else {
            return nil
        }
        return Store(
            runsDirectory: URL(fileURLWithPath: String(cString: runsPath), isDirectory: true),
            runSidecarsDirectory: URL(fileURLWithPath: String(cString: sidecarsPath), isDirectory: true),
            reportsDirectory: URL(fileURLWithPath: String(cString: reportsPath), isDirectory: true),
            liveRunID: RunSummary.ID(String(cString: kscrash_getRunID())),
            maxRunCount: Int(kscrash_getMaxRunSummaryCount()),
            storeConfig: storeConfig
        )
    }
}
