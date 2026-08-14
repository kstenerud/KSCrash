//
//  RunDataStore.swift
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

/// The runs directory: every past run with data on disk. Artifact paths are
/// only ever taken from directory enumeration, never built from decoded run
/// IDs, so a corrupt `.run` cannot address files outside the store.
struct RunDataStore: Sendable {
    let runsDirectory: URL
    let runSidecarsDirectory: URL

    /// Retention cap enforced by `runs()`; 0 or negative disables pruning.
    let maxRunCount: Int

    /// The current process run, excluded from every snapshot.
    let liveRunID: String?

    private let reclaim: @Sendable () -> Void

    init(
        runsDirectory: URL,
        runSidecarsDirectory: URL,
        maxRunCount: Int,
        liveRunID: String?,
        reclaim: @escaping @Sendable () -> Void = {}
    ) {
        self.runsDirectory = runsDirectory
        self.runSidecarsDirectory = runSidecarsDirectory
        self.maxRunCount = maxRunCount
        self.liveRunID = liveRunID
        self.reclaim = reclaim
    }

    /// Immutable snapshot of every past run with data on disk. Prunes first,
    /// then groups all artifacts (`.run` decodes, `.sessions` filenames,
    /// sidecar subdirectories) by runID. Runs with a summary come first,
    /// newest first; artifact-only runs follow. An undecodable or
    /// runID-less `.run` is skipped and left on disk for pruning. Throws only
    /// when the runs directory exists but cannot be read.
    func runs() throws -> [RunStore] {
        // Enforce retention before looking at anything: install only appends
        // (keeping launch cheap), so the send path is where the cap is applied.
        // Pruning first keeps files that are about to be deleted out of the
        // snapshot, so a store can never point at a pruned file.
        prune()

        // One directory listing is the snapshot's point-in-time boundary:
        // everything below works off this list and never re-reads the
        // directory, so files appearing mid-send are simply not part of this
        // send. A missing directory means no run has ever recorded anything
        // (the install path creates it lazily), which is a normal empty result;
        // any other failure means the store itself is unusable and is the one
        // error worth surfacing to the caller.
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: runsDirectory.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }

        // A run's artifacts share nothing but the runID, so the snapshot is a
        // grouping problem: collect each artifact kind under its runID and
        // build one store per key at the end.
        struct Group {
            var summaries: [(orderNs: UInt64, url: URL)] = []
            var sessionsFile: URL?
        }
        var groups: [String: Group] = [:]
        let decoder = JSONDecoder()

        for name in entries {
            let url = runsDirectory.appendingPathComponent(name)
            switch (name as NSString).pathExtension.lowercased() {
            case "run":
                // A `.run` file's grouping key (its runID) lives inside the
                // JSON, so each file is decoded here transiently, just to
                // extract its identity; the payload is discarded immediately
                // and re-read per item under the send's claim, so a send
                // never holds more than one summary regardless of backlog. A
                // summary that cannot be decoded, or decodes without a runID,
                // cannot be keyed or tied to its shared artifacts, so it is
                // skipped and left on disk where pruning eventually reclaims
                // it.
                guard let data = try? Data(contentsOf: url),
                    let summary = try? decoder.decode(RunSummary.self, from: data),
                    !summary.runID.isEmpty
                else {
                    os_log(.error, "Skipping undecodable run summary: %{public}@", name)
                    continue
                }
                // The writer names each file with the run's wall-clock start in
                // nanoseconds, which is the send-order key. Files not named by
                // the writer (tests, hand-made) fall back to the decoded start
                // time so they still order sensibly among the rest.
                let orderNs = parsedRunFilenameNs(name) ?? UInt64(clamping: summary.startedAtMs) &* 1_000_000
                groups[summary.runID, default: Group()].summaries.append((orderNs, url))
            case "sessions":
                // `.sessions` filenames are `<runID>.sessions`, so the name
                // alone keys the file; nothing needs to be read.
                let runID = (name as NSString).deletingPathExtension
                if !runID.isEmpty {
                    groups[runID, default: Group()].sessionsFile = url
                }
            default:
                break
            }
        }

        // Run sidecars live in a sibling directory as one `<runID>/` folder
        // per run. A run with only shared files (its summary already sent, its
        // `.sessions` or sidecars still held for an unsent crash report) still
        // gets a group: orphans are not a separate concept, they are stores
        // with nothing left to send, and reclaim needs to see them. The
        // directory listing is also the only source of these paths; nothing is
        // ever built from a decoded runID, so a corrupt `.run` cannot address
        // files outside the store.
        var sidecarDirectories: [String: URL] = [:]
        if let names = try? FileManager.default.contentsOfDirectory(atPath: runSidecarsDirectory.path) {
            for name in names {
                let url = runSidecarsDirectory.appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                    isDirectory.boolValue
                {
                    sidecarDirectories[name] = url
                    if groups[name] == nil {
                        groups[name] = Group()
                    }
                }
            }
        }

        // The live run is still writing its artifacts (its `.run` does not
        // even exist until the next launch persists it), so it is never a
        // send or reclaim candidate, whatever artifacts of it we saw.
        if let liveRunID {
            groups.removeValue(forKey: liveRunID)
        }

        // One store per run. Within a run, duplicate `.run` files (distinct
        // files that decoded to the same runID) sort newest first and the
        // newest is the run's summary; removeSummary() still deletes them all
        // so a duplicate can never resurrect a sent run. Across runs, newest
        // first so the freshest telemetry ships first and an interrupted send
        // has already delivered the most valuable summaries. Artifact-only
        // runs have nothing to send, so they go last, ordered by runID only
        // to keep snapshots deterministic.
        var withSummary: [(orderNs: UInt64, store: RunStore)] = []
        var artifactOnly: [RunStore] = []
        for (runID, group) in groups {
            let summaries = group.summaries.sorted { $0.orderNs > $1.orderNs }
            let store = RunStore(
                runID: runID,
                summaryFiles: summaries.map(\.url),
                sessionsFile: group.sessionsFile,
                sidecarDirectory: sidecarDirectories[runID]
            )
            if let newest = summaries.first {
                withSummary.append((newest.orderNs, store))
            } else {
                artifactOnly.append(store)
            }
        }
        return withSummary.sorted { $0.orderNs > $1.orderNs }.map(\.store)
            + artifactOnly.sorted { $0.runID < $1.runID }
    }

    /// Remove shared run data nothing references any more.
    func reclaimOrphans() {
        reclaim()
    }

    /// Delete the oldest writer-named `.run` files beyond `maxRunCount`.
    private func prune() {
        guard maxRunCount > 0,
            let entries = try? FileManager.default.contentsOfDirectory(atPath: runsDirectory.path)
        else {
            return
        }
        let parsed = entries.compactMap { name in
            parsedRunFilenameNs(name).map { (ns: $0, name: name) }
        }
        guard parsed.count > maxRunCount else {
            return
        }
        for entry in parsed.sorted(by: { $0.ns < $1.ns }).prefix(parsed.count - maxRunCount) {
            try? FileManager.default.removeItem(at: runsDirectory.appendingPathComponent(entry.name))
        }
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
