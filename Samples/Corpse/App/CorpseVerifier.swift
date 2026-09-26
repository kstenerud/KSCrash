//
//  CorpseVerifier.swift
//
//  Created by Alexander Cohen on 2026-09-19.
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
import KSCrash
import KSCrashReportModel

/// Captures every report the send pipeline carries, so the verdict is built from
/// the payload a real backend would have received rather than from a file read
/// off disk. A report that reads fine on disk and reaches a stage malformed is
/// exactly the failure this test exists to catch, and only a stage sees that.
///
/// It returns the payload unchanged, so the driver records `delivered` and the
/// file is removed, which is itself asserted: a corpse report that can never be
/// delivered is retried forever with no backoff.
private struct CapturingStage: PipelineStage {
    let captured: Captured

    final class Captured: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Report] = []

        func append(_ report: Report) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(report)
        }

        var reports: [Report] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    func process(_ payload: Report) async throws -> Report? {
        captured.append(payload)
        return payload
    }
}

/// What the UI test reads back. Everything is a string because it crosses to the
/// test through the UI, and a failure has to explain itself from the label alone:
/// nobody can attach to the device this ran on.
struct CorpseVerdict {
    var passed: Bool
    var summary: String
    var detail: String
}

enum CorpseVerifier {

    /// Drains the extension's area, sends, and reports what arrived.
    ///
    /// The app's own install is a normal one; only `corpseAreas` at send time
    /// points at the shared area the extension wrote into. That is the documented
    /// integration, and doing it any other way here would test something users
    /// would not be doing.
    /// - Parameter expectedRun: the run id the test watched die. Reports from any
    ///   other run are ignored rather than accepted, because a leftover from an
    ///   earlier case would otherwise satisfy every assertion below.
    static func run(expecting expectation: CorpseExpectation, fromRun expectedRun: String?) async
        -> CorpseVerdict
    {
        let captured = CapturingStage.Captured()
        var send = SendConfiguration()
        send.reportPipeline = [AnyPipelineStage(CapturingStage(captured: captured))]
        send.corpseAreas = [CorpseArea.configuration]

        // Identity first: pick the report belonging to the run the test killed,
        // never merely the first one that happens to be lying around.
        func isFromExpectedRun(_ report: Report) -> Bool {
            guard let expectedRun else { return true }
            return report.report.runId?.description == expectedRun
        }

        // The extension runs on the system's schedule, in its own process, so its
        // report can land after the app is back. Send until the expected run's
        // report has arrived or the window closes, rather than once: a single
        // send reads a slow extension as a missing report.
        var items: [SendResult<Report>.Item] = []
        let window = Date().addingTimeInterval(30)
        repeat {
            do {
                items += try await KSCrash.shared.sendReports(with: send).items
            } catch {
                return CorpseVerdict(
                    passed: false, summary: "send-failed", detail: "sendReports threw: \(error)")
            }
            if captured.reports.contains(where: isFromExpectedRun) {
                break
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        } while Date() < window

        let reports = captured.reports
        let fromExpectedRun = reports.filter(isFromExpectedRun)
        guard let report = fromExpectedRun.first(where: { expectation.matches($0) }) ?? fromExpectedRun.first
        else {
            return CorpseVerdict(
                passed: false, summary: "no-report",
                detail: """
                    nothing arrived for run \(expectedRun ?? "any") / \(expectation.triggerID).
                    reports seen: \(reports.count), runs: \(reports.map { $0.report.runId?.description ?? "nil" })
                    sent items: \(items.count)
                    """)
        }

        var failures: [String] = []

        // The whole point of the path: the report describes the process that
        // died, produced by a process that did not.
        if !expectation.matches(report) {
            let error = report.crash.error
            failures.append(
                "classified as \(error.type) \(error.mach?.exceptionName ?? "no mach exception")"
                    + " \(error.signal?.name ?? "no signal"), expected mach exception"
                    + " \(expectation.machException) signal \(expectation.signal)")
        }
        // The identity that had to cross a process boundary: the extension reads
        // it out of the corpse's __ks_runid section, so a mismatch means the
        // report is not the crashed run's.
        switch (report.report.runId?.description, expectedRun) {
        case (nil, _):
            failures.append("no run id: the crashed run's identity did not survive the corpse")
        case (let actual?, let expected?) where actual != expected:
            failures.append("run id \(actual) is not the run that crashed (\(expected))")
        default:
            break
        }
        if report.crash.threads?.isEmpty ?? true {
            failures.append("no threads: the corpse port produced no thread state")
        }
        // A report marks its crashed thread inside `threads`; `crash.crashedThread`
        // is written only for a recrash, so it is absent here by design.
        if let crashed = report.crash.threads?.first(where: \.crashed) {
            // Index 0 is the main thread, the first one the corpse's task lists.
            if expectation.crashesOffMainThread && crashed.index == 0 {
                failures.append("the main thread is named as crashed, but the trigger crashes a background thread")
            }
        } else {
            failures.append("no crashed thread named")
        }
        if report.binaryImages?.isEmpty ?? true {
            failures.append("no binary images")
        }
        // Written only by a capture from a corpse, so its absence means this
        // report came from somewhere else entirely.
        if report.corpse == nil {
            failures.append("no corpse section: this was not an out-of-process capture")
        }

        // Delivered means the driver removed it. Anything else leaves the report
        // on disk to be retried forever.
        let delivered = items.filter {
            if case .delivered = $0.outcome { return true }
            return false
        }
        if delivered.isEmpty {
            failures.append("nothing was delivered; outcomes: \(items.map { "\($0.outcome)" })")
        }

        return CorpseVerdict(
            passed: failures.isEmpty,
            summary: failures.isEmpty ? "pass" : "fail",
            detail: failures.isEmpty
                ? "\(expectation.triggerID): \(reports.count) report(s), run \(report.report.runId?.description ?? "?")"
                : failures.joined(separator: " | "))
    }
}
