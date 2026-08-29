//
//  Store.swift
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
import os

/// One past run's on-disk artifacts, captured at snapshot time. Pure data:
/// every operation on it lives on `Store`.
struct Run: Sendable {
    let runID: RunSummary.ID

    /// This run's `.run` file; nil when the run has no summary on disk.
    let summaryFile: URL?

    let sessionsFile: URL?
    let sidecarDirectory: URL?
}

/// The on-disk state of the install: past runs (summaries, sessions, run
/// sidecars) and pending crash reports. All reads and deletes live here;
/// the listings are inert values. The two halves are listed separately, so
/// a send depends only on the directories it delivers from. Artifact paths
/// are only ever taken from directory enumeration, never built from decoded
/// run IDs, so a corrupt `.run` cannot address files outside the store.
struct Store: Sendable {
    let runsDirectory: URL
    let runSidecarsDirectory: URL

    /// The current process run, excluded from every snapshot.
    let liveRunID: RunSummary.ID?

    /// The install-resolved `.run` retention cap the bulk sends enforce
    /// through `pruneRunSummaries(keepingNewest:)`.
    let maxRunCount: Int

    private let reports: ReportBridge
    private let reclaim: @Sendable () -> Void

    /// The production store: the report half and the reclaim go through
    /// the C-backed report store, the one owner of the Reports directory,
    /// via a resolved configuration that stays valid for the process.
    init(
        runsDirectory: URL,
        runSidecarsDirectory: URL,
        reportsDirectory: URL,
        liveRunID: RunSummary.ID?,
        maxRunCount: Int,
        storeConfig: UnsafePointer<KSCrashReportStoreCConfiguration>
    ) {
        let config = CStoreConfig(pointer: storeConfig)
        self.init(
            runsDirectory: runsDirectory,
            runSidecarsDirectory: runSidecarsDirectory,
            liveRunID: liveRunID,
            maxRunCount: maxRunCount,
            reports: ReportBridge(
                list: { try Store.listReportIDs(in: reportsDirectory) },
                read: { id in try config.read(id) },
                runID: { id in config.runID(of: id) },
                remove: { id in try config.remove(id) }
            ),
            reclaim: { kscrs_reclaimOrphanedRunData(config.pointer) }
        )
    }

    init(
        runsDirectory: URL,
        runSidecarsDirectory: URL,
        liveRunID: RunSummary.ID?,
        maxRunCount: Int = 0,
        reports: ReportBridge = .none,
        reclaim: @escaping @Sendable () -> Void = {}
    ) {
        self.runsDirectory = runsDirectory
        self.runSidecarsDirectory = runSidecarsDirectory
        self.liveRunID = liveRunID
        self.maxRunCount = maxRunCount
        self.reports = reports
        self.reclaim = reclaim
    }

    /// Every pending crash report, newest first. Throws when the Reports
    /// directory cannot be enumerated; the runs half is not touched.
    func snapshotReportIDs() throws -> [Report.ID] {
        // The listing is oldest first (the filenames carry the write time),
        // so newest first is its reverse.
        Array(try reports.list().reversed())
    }

    /// Every past run with data on disk, as inert values: all artifacts
    /// (`.run` decodes, `.sessions` filenames, sidecar subdirectories) grouped
    /// by runID. Runs with a summary come first, newest first; artifact-only
    /// runs follow. A pure read; callers that want retention enforced call
    /// `pruneRunSummaries(keepingNewest:)` first. An undecodable or
    /// runID-less `.run` is skipped; the send-end reclaim deletes it. Throws when
    /// the Runs or RunSidecars directory exists but cannot be read; the
    /// reports half is not touched.
    func snapshotRuns() throws -> [Run] {
        // One directory listing is the snapshot's point-in-time boundary:
        // everything below works off this list and never re-reads the
        // directory, so files appearing mid-send are simply not part of this
        // send. A missing directory means no run has ever recorded anything
        // (the install path creates it lazily), which is a normal empty result;
        // any other failure means the store itself is unusable and surfaces
        // to the caller.
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: runsDirectory.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }

        // A run's artifacts share nothing but the runID, so the snapshot is a
        // grouping problem: collect each artifact kind under its runID and
        // build one run value per key at the end.
        struct Group {
            var summary: (orderNs: UInt64, url: URL)?
            var sessionsFile: URL?
        }
        var groups: [RunSummary.ID: Group] = [:]
        let decoder = JSONDecoder()

        for name in entries {
            let url = runsDirectory.appendingPathComponent(name)
            switch (name as NSString).pathExtension.lowercased() {
            case KSCRS_RUN_SUMMARY_FILENAME_EXTENSION:
                // A `.run` file's grouping key (its runID) lives inside the
                // JSON, so each file is read here transiently, decoding only
                // the identity fields; the full summary is decoded per item
                // under the send's claim, so a send never holds more than one
                // summary regardless of backlog, and a summary the full model
                // cannot decode still lists, surfacing its decode error as a
                // kept item instead of vanishing. A file that does not even
                // yield an identity cannot be keyed or tied to its shared
                // artifacts, so it is skipped here, and the send-end reclaim
                // deletes it as garbage (an unreadable file aborts that pass
                // and is retried instead).
                guard let data = try? Data(contentsOf: url),
                    let identity = try? decoder.decode(RunIdentity.self, from: data)
                else {
                    os_log(.error, "Skipping unidentifiable run summary: %{public}@", name)
                    continue
                }
                // The writer names each file with the run's wall-clock start in
                // nanoseconds, which is the send-order key. Files not named by
                // the writer (tests, hand-made) fall back to the decoded start
                // time so they still order sensibly among the rest; a file
                // with neither sorts first, and its missing timestamp
                // surfaces through the strict decode as a kept item.
                // Capped so a corrupt timestamp saturates newest instead
                // of wrapping into a tiny sort key.
                let orderNs =
                    parsedRunFilenameNs(name)
                    ?? identity.startedAtMs.map { min(UInt64(clamping: $0), UInt64.max / 1_000_000) * 1_000_000 }
                    ?? 0
                // One summary per run: the writer's filename is deterministic
                // (the dead run's own start time), so a re-persist overwrites
                // rather than duplicates. If a stray extra file ever decodes
                // to the same runID (hand-made), the newest wins and the
                // other stays on disk; re-delivery is deduped by run id at
                // the backend, deliberately not here.
                var group = groups[identity.runID, default: Group()]
                if group.summary == nil || group.summary!.orderNs < orderNs {
                    group.summary = (orderNs, url)
                }
                groups[identity.runID] = group
            case KSCRS_SESSIONS_FILENAME_EXTENSION:
                // `.sessions` filenames are `<runID>.sessions`, so the name
                // alone keys the file; nothing needs to be read.
                // A name that is not a run id is not a run's file; the
                // reclaim owns whatever it is.
                if let runID = RunSummary.ID((name as NSString).deletingPathExtension) {
                    groups[runID, default: Group()].sessionsFile = url
                }
            default:
                break
            }
        }

        // Run sidecars live in a sibling directory as one `<runID>/` folder
        // per run. A run with only shared files (its summary already sent, its
        // `.sessions` or sidecars still held for an unsent crash report) still
        // gets a group: orphans are not a separate concept, they are runs
        // with nothing left to send, and reclaim needs to see them. The
        // directory listing is also the only source of these paths; nothing is
        // ever built from a decoded runID, so a corrupt `.run` cannot address
        // files outside the store.
        var sidecarDirectories: [RunSummary.ID: URL] = [:]
        let sidecarNames: [String]
        do {
            sidecarNames = try FileManager.default.contentsOfDirectory(atPath: runSidecarsDirectory.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // No run ever wrote a sidecar: a normal empty result. Any other
            // failure propagates, exactly like the Runs enumeration above;
            // mistaking it for absence would deliver pending summaries without
            // their metadata and let reclaim drop the still-present sidecars.
            sidecarNames = []
        }
        for name in sidecarNames {
            let url = runSidecarsDirectory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                isDirectory.boolValue, let runID = RunSummary.ID(name)
            {
                sidecarDirectories[runID] = url
                if groups[runID] == nil {
                    groups[runID] = Group()
                }
            }
        }

        // The live run is still writing its artifacts (its `.run` does not
        // even exist until the next launch persists it), so it is never a
        // send or reclaim candidate, whatever artifacts of it we saw.
        if let liveRunID {
            groups.removeValue(forKey: liveRunID)
        }

        // One run value per run. Runs with a summary go newest first, so the
        // freshest telemetry ships first and an interrupted send has already
        // delivered the most valuable summaries. Artifact-only runs have
        // nothing to send, so they go last, ordered by runID only to keep
        // snapshots deterministic.
        var withSummary: [(orderNs: UInt64, run: Run)] = []
        var artifactOnly: [Run] = []
        for (runID, group) in groups {
            let run = Run(
                runID: runID,
                summaryFile: group.summary?.url,
                sessionsFile: group.sessionsFile,
                sidecarDirectory: sidecarDirectories[runID]
            )
            if let summary = group.summary {
                withSummary.append((summary.orderNs, run))
            } else {
                artifactOnly.append(run)
            }
        }
        return withSummary.sorted { $0.orderNs > $1.orderNs }.map(\.run)
            + artifactOnly.sorted { $0.runID.description < $1.runID.description }
    }

    /// Remove shared run data nothing references any more.
    func reclaimOrphans() {
        reclaim()
    }

    /// Delete the oldest writer-named `.run` files beyond `max`; 0 or
    /// negative deletes nothing. Retention is deliberately a send-path
    /// concern (install only appends, keeping launch cheap): the send calls
    /// this before `snapshotRuns()`, so a listing never points at a pruned
    /// file.
    func pruneRunSummaries(keepingNewest max: Int) {
        guard max > 0,
            let entries = try? FileManager.default.contentsOfDirectory(atPath: runsDirectory.path)
        else {
            return
        }
        let parsed = entries.compactMap { name in
            parsedRunFilenameNs(name).map { (ns: $0, name: name) }
        }
        guard parsed.count > max else {
            return
        }
        for entry in parsed.sorted(by: { $0.ns < $1.ns }).prefix(parsed.count - max) {
            try? FileManager.default.removeItem(at: runsDirectory.appendingPathComponent(entry.name))
        }
    }
}

/// A `.run` file's identity: the fields the listing needs to key a run,
/// decodable even when the full summary no longer is. The timestamp is an
/// ordering fallback only, so anything that decodes a run_id lists; the
/// strict model decode is the health gate that surfaces a broken summary
/// as a kept item.
private struct RunIdentity: Decodable {
    let runID: RunSummary.ID
    let startedAtMs: Int64?

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case startedAtMs = "started_at_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runID = try container.decode(RunSummary.ID.self, forKey: .runID)
        // A mistyped timestamp reads as absent: it must not cost the run
        // its listing, only its ordering.
        startedAtMs = try? container.decodeIfPresent(Int64.self, forKey: .startedAtMs)
    }
}

extension Store {
    /// The report filename grammar. One parser, the C store's; this only
    /// converts its result.
    enum ReportFilename {
        /// The id in a report filename; nil for any other name.
        static func reportID(in name: String) -> Report.ID? {
            var id = [CChar](repeating: 0, count: Int(KSID_SIZE))
            guard kscrs_parseReportFilename(name, &id) else { return nil }
            return Report.ID(String(cString: id))
        }
    }

    /// The report ids in `directory`, oldest first, from the filenames alone:
    /// the digits are the write time and the id is the report's. Anything
    /// else is not a report. An absent directory is empty; an unreadable one
    /// throws.
    static func listReportIDs(in directory: URL) throws -> [Report.ID] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        return names.sorted().compactMap(ReportFilename.reportID(in:))
    }
}

/// The C store's resolved configuration, valid for the process. The pointer
/// is read-only shared state, which is what makes it safe to carry across
/// sends.
private struct CStoreConfig: @unchecked Sendable {
    let pointer: UnsafePointer<KSCrashReportStoreCConfiguration>

    /// The stitched report bytes; nil when unreadable now, throws when the
    /// file holds no JSON report (deterministic).
    func read(_ id: Report.ID) throws -> Data? {
        var status = KSCrashReportReadStatusOK
        guard let raw = kscrs_readReport(id.description, pointer, &status) else {
            if status == KSCrashReportReadStatusUndecodable {
                throw CocoaError(.fileReadCorruptFile)
            }
            return nil
        }
        defer { free(raw) }
        return Data(bytes: raw, count: strlen(raw))
    }

    func runID(of id: Report.ID) -> RunSummary.ID? {
        guard let raw = kscrs_copyReportRunID(id.description, pointer) else { return nil }
        defer { free(raw) }
        return RunSummary.ID(String(cString: raw))
    }

    func remove(_ id: Report.ID) throws {
        if !kscrs_deleteReportWithID(id.description, pointer) {
            throw CocoaError(
                .fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Report \(id) could not be deleted."])
        }
    }
}

/// The report half's backing calls. Internal plumbing: the production init
/// derives it from the C-backed report store, and only the test-seam init
/// takes one directly. Intermediary by design: it exists only while the
/// report store is C-backed; the production init fills it with the C calls.
struct ReportBridge: Sendable {
    /// All pending report IDs, oldest first, ordered by write time; the
    /// store's snapshot derives newest-first by reversal. Throws when the
    /// directory cannot be enumerated; an empty store is an empty array.
    let list: @Sendable () throws -> [Report.ID]

    /// One report's stitched JSON. nil when it cannot be read right now.
    /// Throws when the file was read but does not hold a JSON report; that is
    /// deterministic, so the send surfaces it instead of retrying forever.
    let read: @Sendable (Report.ID) throws -> Data?

    /// The run a report belongs to, from the report file alone: nothing is
    /// stitched and no run artifacts are touched. nil when the report cannot
    /// be read or records no run.
    let runID: @Sendable (Report.ID) -> RunSummary.ID?

    /// Delete one report. Throws when the report file could not be removed.
    let remove: @Sendable (Report.ID) throws -> Void

    /// A store with no report half (run-only tests).
    static let none = ReportBridge(list: { [] }, read: { _ in nil }, runID: { _ in nil }, remove: { _ in })
}

extension Store {
    /// The stitched report, decoded. nil when the item cannot be read right
    /// now (missing file, stale listing entry, or a read failure): skipped,
    /// kept on disk, retried by the next send. Throws when the report was
    /// read but does not decode, whether the C store found no JSON report in
    /// the file or the typed decode failed: that is deterministic, so the
    /// send surfaces it as a kept item instead of silently retrying it
    /// forever; the file stays on disk. Under a send's claim the stale check
    /// is race-free, because deletes only happen under the claim.
    func report(_ id: Report.ID) throws -> Report? {
        guard let data = try reports.read(id) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(Report.self, from: data)
        } catch {
            os_log(.error, "Undecodable report %{public}@: %{public}@", id.description, String(describing: error))
            throw error
        }
    }

    /// The run `id` belongs to, from the report file alone: nothing is
    /// stitched and no run artifacts are touched. nil when the report cannot
    /// be read or records no run.
    func runID(of id: Report.ID) -> RunSummary.ID? {
        reports.runID(id)
    }

    /// Delete one report (and, through the C store, its report sidecars).
    func removeReport(_ id: Report.ID) throws {
        try reports.remove(id)
    }
}

/// The start timestamp of a writer-named summary file; nil for any other
/// name. The grammar (digit cap and extension) is shared with the C writer
/// through the KSCRS_RUN_SUMMARY_FILENAME_* constants.
private let runFilenameSuffix = "." + KSCRS_RUN_SUMMARY_FILENAME_EXTENSION

private func parsedRunFilenameNs(_ name: String) -> UInt64? {
    guard name.hasSuffix(runFilenameSuffix) else {
        return nil
    }
    let digits = name.dropLast(runFilenameSuffix.count)
    guard (1...Int(KSCRS_RUN_SUMMARY_FILENAME_DIGITS)).contains(digits.count),
        digits.allSatisfy({ $0.isASCII && $0.isNumber })
    else {
        return nil
    }
    return UInt64(digits)
}
