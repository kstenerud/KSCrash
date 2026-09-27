//
//  Store+TakeIn.swift
//
//  Created by Alexander Cohen on 2026-09-26.
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
import os

/// Serializes take-ins per store directory. Every send builds its own `Store`,
/// so the gate is keyed by the directory rather than held by the value. A send
/// that arrives while another is taking in waits its turn and then takes in its
/// own sources, which may differ from the other send's.
actor TakeInGate {
    static let shared = TakeInGate()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var busy: Set<String> = []
    private var waiting: [String: [Waiter]] = [:]

    /// Returns once the caller holds `key`, or false when its task was
    /// cancelled while waiting, in which case it does not hold the key.
    func enter(_ key: String) async -> Bool {
        guard busy.contains(key) else {
            busy.insert(key)
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Already cancelled: the handler below ran before this was
                // queued and found nothing to remove.
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiting[key, default: []].append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.withdraw(id, from: key) }
        }
    }

    /// Hands the key to the next waiter, which then holds it, or frees it.
    func leave(_ key: String) {
        guard var queue = waiting[key], !queue.isEmpty else {
            busy.remove(key)
            return
        }
        let next = queue.removeFirst()
        waiting[key] = queue.isEmpty ? nil : queue
        next.continuation.resume(returning: true)
    }

    private func withdraw(_ id: UUID, from key: String) {
        guard var queue = waiting[key], let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let waiter = queue.remove(at: index)
        waiting[key] = queue.isEmpty ? nil : queue
        waiter.continuation.resume(returning: false)
    }
}

extension Store {
    /// Takes the reports waiting in `sources` into the store, one at a time,
    /// before the listing, then prunes the store to its cap. A reader's report
    /// is finished `.taken` only once the store holds it durably, so a crash in
    /// between leaves the reader's copy, and the next send's id check answers
    /// `.taken` rather than storing a second copy while the store holds it.
    func takeIn(from sources: [any ReportSource], claims: SendClaims<Report.ID>) async {
        guard !sources.isEmpty else { return }
        let gateKey = reportsDirectory?.standardizedFileURL.path ?? "store:\(runsDirectory.path)"
        guard await TakeInGate.shared.enter(gateKey) else {
            os_log(.info, "The send was cancelled while waiting to take reports in")
            return
        }
        await takeInHoldingGate(from: sources, claims: claims)
        await TakeInGate.shared.leave(gateKey)
    }

    private func takeInHoldingGate(from sources: [any ReportSource], claims: SendClaims<Report.ID>) async {
        // Reports held in memory are staged in a directory of this take-in's
        // own, outside the store, so the store's directory only ever holds whole
        // reports. One a crash leaves here is in the temporary directory, which
        // the system clears.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KSCrashTakeIn-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            // Reports held in memory cannot be staged; each is retried later.
            Self.log("Could not create the staging directory", staging, error)
        }
        defer { Self.remove(staging, reason: "the staging directory") }

        var held: Set<Report.ID>
        do {
            held = Set(try reports.list())
        } catch {
            // Without the listing there is no duplicate check, and the send's
            // own listing is about to fail the same way.
            os_log(
                .error, "Reports are not taken in: the store's reports could not be listed: %{public}@",
                String(describing: error))
            return
        }
        let heldBefore = held.count
        for source in sources {
            if Task.isCancelled { break }
            await takeIn(from: source, into: &held, staging: staging)
        }
        // Everything is taken in first and the cap applied after, so the store
        // keeps its newest reports whichever source they came from, and no
        // source is left holding a backlog nothing prunes.
        if held.count > heldBefore {
            prune(claims: claims)
        }
    }

    /// Deletes the oldest reports beyond the cap, skipping two kinds: one
    /// another send has claimed, since that send may be delivering it and a
    /// report it keeps must still be on disk, and one from the current run,
    /// which may still be updated (an unresolved hang, say). A skipped report
    /// is not made up for by deleting a newer one, which would trade fresher
    /// crash data for a cap the next prune reaches anyway; the store sits over
    /// its cap until then.
    private func prune(claims: SendClaims<Report.ID>) {
        guard maxReportCount > 0 else { return }
        let oldestFirst: [Report.ID]
        do {
            oldestFirst = try reports.list()
        } catch {
            os_log(
                .error, "The store could not be pruned: its reports could not be listed: %{public}@",
                String(describing: error))
            return
        }
        var victims: [Report.ID] = []
        for id in oldestFirst.prefix(max(0, oldestFirst.count - maxReportCount)) {
            guard claims.claim(id) else { continue }
            if let liveRunID, reports.runID(id) == liveRunID {
                claims.release(id)
                continue
            }
            victims.append(id)
        }
        // Held claimed until they are gone, so no send starts on one mid-delete.
        defer { victims.forEach(claims.release) }
        reports.delete(victims)
    }

    private func takeIn<Source: ReportSource>(from source: Source, into held: inout Set<Report.ID>, staging: URL) async
    {
        var reader = source.makeReader()
        while !Task.isCancelled {
            let incoming: IncomingReport?
            do {
                incoming = try await reader.next()
            } catch {
                os_log(
                    .error, "Report source %{public}@ could not be read; its reports are not taken in: %{public}@",
                    String(describing: source), String(describing: error))
                return
            }
            guard let incoming else { return }
            let disposition = place(incoming, held: held, staging: staging)
            if disposition == .taken {
                held.insert(incoming.id)
            } else {
                os_log(
                    .error, "Report %{public}@ from %{public}@ was not taken in; it is offered again on a later send",
                    incoming.id.description, String(describing: source))
            }
            await reader.finish(incoming, as: disposition)
        }
    }

    private func place(_ incoming: IncomingReport, held: Set<Report.ID>, staging: URL) -> IncomingReport.Disposition {
        // The store already has it: the reader's copy is redundant.
        if held.contains(incoming.id) {
            return .taken
        }
        let timestampNs = Self.nanoseconds(since1970: incoming.timestamp)
        switch incoming.content {
        case .file(let url):
            // A file another store already named for this id keeps its exact
            // name: the timestamp came through `Date`, which holds only about a
            // tenth of a microsecond, and rebuilding the name from it could
            // reorder reports written within that span.
            let name = url.lastPathComponent
            let exactNs =
                ReportFilename.reportID(in: name) == incoming.id
                ? ReportFilename.timestampNs(in: name) : nil
            return reports.takeIn(url, incoming.id, exactNs ?? timestampNs)
        case .data(let data):
            // Written whole outside the store, then moved in, so no listing
            // ever sees half a report.
            let stagedFile = staging.appendingPathComponent(UUID().uuidString)
            // Taken, the staged file was moved and is gone; otherwise it is
            // removed here so a failed attempt leaves nothing behind.
            defer { Self.remove(stagedFile, reason: "a staged report") }
            do {
                try Self.writeDurably(data, to: stagedFile)
            } catch {
                Self.log("Could not stage report \(incoming.id)", stagedFile, error)
                return .retryLater
            }
            return reports.takeIn(stagedFile, incoming.id, timestampNs)
        }
    }

    /// The instant as nanoseconds since 1970, saturating at both ends so a
    /// nonsense date orders first or last rather than trapping.
    static func nanoseconds(since1970 date: Date) -> UInt64 {
        let ns = date.timeIntervalSince1970 * 1_000_000_000
        guard ns > 0 else { return 0 }
        guard ns < Double(UInt64.max) else { return UInt64.max }
        return UInt64(ns.rounded())
    }

    private static func writeDurably(_ data: Data, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            // The write's failure is the one reported; a close failing after it adds nothing.
            try? handle.close()
            throw error
        }
        try handle.close()
    }

    /// Removes `url`, logging any failure except its already being gone.
    static func remove(_ url: URL, reason: String) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch  where !isNoSuchFile(error) {
            log("Could not remove \(reason)", url, error)
        } catch {}
    }

    static func isNoSuchFile(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError {
            return cocoa.code == .fileNoSuchFile || cocoa.code == .fileReadNoSuchFile
        }
        return (error as? POSIXError)?.code == .ENOENT
    }

    static func log(_ what: String, _ url: URL, _ error: Error) {
        os_log(.error, "%{public}@ at %{public}@: %{public}@", what, url.path, String(describing: error))
    }
}
