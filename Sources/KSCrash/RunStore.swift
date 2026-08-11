//
//  RunStore.swift
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
import KSCrashRecordingCore
import KSCrashReportModel

/// One past run's on-disk artifacts. A store deletes only what the run
/// exclusively owns (its `.run` files); shared files (`.sessions`, the sidecar
/// directory) are reclaimed by the directory-level sweep, never here.
struct RunStore: Sendable {
    let runID: String

    /// This run's `.run` files, newest first. Usually one; several when
    /// duplicates decoded to the same runID. Empty when the run has no summary
    /// on disk.
    let summaryFiles: [URL]

    let sessionsFile: URL?
    let sidecarDirectory: URL?

    /// The decoded newest `.run`, before merge and stitch.
    let baseSummary: RunSummary?

    /// Whether any of this run's `.run` files still exists. A snapshot can go
    /// stale (a concurrent send may deliver and delete a run after this store
    /// was built), and `baseSummary` would happily outlive the file; checking
    /// under a send's claim is race-free, because deletes only happen under
    /// the claim.
    var hasSummaryOnDisk: Bool {
        summaryFiles.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The run's summary in deliverable form: session records merged from
    /// `.sessions`, metadata stitched from the run's UserInfo sidecar. nil when
    /// the run has no summary on disk. An unreadable `.sessions` degrades to
    /// empty records; a missing or empty sidecar to nil metadata.
    func summary() -> RunSummary? {
        guard var summary = baseSummary else {
            return nil
        }
        // The persisted `.run` deliberately carries neither session records nor
        // metadata (the install path stays cheap; the records' and userInfo's
        // single source of truth are their own files). Both are attached here,
        // at delivery, and each enrichment degrades independently: a problem
        // with one file costs that enrichment, never the summary itself.
        summary = mergingSessions(into: summary)
        if let metadata = stitchedMetadata() {
            summary = summary.with(metadata: metadata)
        }
        return summary
    }

    /// Delete this run's own `.run` files. Deletes every duplicate, so a run
    /// whose summary was delivered once can never resurface through a stray
    /// second file that decoded to the same runID.
    func removeSummary() throws {
        for file in summaryFiles {
            try FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Sessions

    /// Replace `base`'s (empty) session records with the run's recorded
    /// sessions, read through the C `.sessions` reader.
    private func mergingSessions(into base: RunSummary) -> RunSummary {
        // No file means the run cut no sessions (the writer creates the file
        // lazily on the first cut); an unopenable one is treated the same,
        // matching the previous ObjC merge: the summary ships with empty
        // records rather than not shipping.
        guard let sessionsFile, let reader = kssr_open(sessionsFile.path) else {
            return base
        }
        defer { kssr_close(reader) }
        let count = kssr_count(reader)
        guard count > 0 else {
            return base
        }
        var records: [RunSummary.Session] = []
        records.reserveCapacity(Int(count))
        for index in 0..<count {
            var record = KSSessionRecord()
            guard kssr_sessionAt(reader, index, &record) else {
                continue
            }
            // The C reader has already validated the entries and inferred each
            // session's end from its successor's start, so dropping a record
            // here (corrupt guid) cannot distort its neighbors' bounds.
            guard let sessionID = cArrayString(&record.guid) else {
                continue  // corrupt on-disk guid (invalid UTF-8); skip the record
            }
            // Empty user is anonymous; absence is modeled as nil, never "".
            let user = cArrayString(&record.user)
            let userID = (user?.isEmpty ?? true) ? nil : user
            // The final session is still open when the run ends (nothing cut
            // after it), so its end is the run's end. Flooring to its own start
            // keeps the duration non-negative if the run's end predates the
            // session start (e.g. clock adjustments between the two files).
            let endedAtMs = record.endInferred ? max(base.endedAtMs, record.startedAtMs) : record.endedAtMs
            records.append(
                RunSummary.Session(
                    sessionID: sessionID,
                    userID: userID,
                    perceptible: record.perceptible,
                    startedAtMs: record.startedAtMs,
                    endedAtMs: endedAtMs
                ))
        }
        // The model is immutable, so merging means rebuilding a copy with the
        // records swapped in.
        return base.with(sessions: RunSummary.Sessions(records: records))
    }

    // MARK: - Metadata

    /// The app data recorded for this run via the userInfo API, as a `Metadata`
    /// bag; nil when the run recorded none.
    private func stitchedMetadata() -> Metadata? {
        // Metadata is stitched at delivery from the run's UserInfo sidecar,
        // never read live and never baked into the `.run`, exactly like
        // session_id from `.sessions` and userInfo on reports. The sidecar is
        // the same file the report stitch reads, so a report and this run's
        // summary always agree on the run's app data.
        guard let sidecarDirectory else {
            return nil
        }
        let path = sidecarDirectory.appendingPathComponent("UserInfo.ksscr").path
        // Read mode needs no config; failure to open just means the run
        // recorded no userInfo (the sidecar is created on the first write).
        guard let store = kskvs_create(path, KSKVSModeRead, nil) else {
            return nil
        }
        defer { kskvs_destroy(store) }

        // The C iteration resolves the store to its last-write-wins state
        // first, so each callback fires once per key with its final value, and
        // onRemoved fires for keys whose final state is a tombstone. Since the
        // bag starts empty, a removal is a no-op here; it is honored anyway so
        // this stays faithful to the callback contract rather than depending
        // on iteration internals. C callbacks cannot capture, so the bag rides
        // through the context pointer as an unmanaged box, and every key or
        // string value that is not valid UTF-8 drops that entry, matching how
        // the report stitch's NSString construction behaves.
        let box = MetadataBox()
        var callbacks = KSKVSCallbacks()
        callbacks.onString = { key, keyLength, value, valueLength, context in
            guard let key = kvString(key, keyLength), let value = kvString(value, valueLength) else { return }
            MetadataBox.from(context).metadata.set(value, forKey: key)
        }
        callbacks.onInt64 = { key, keyLength, value, context in
            guard let key = kvString(key, keyLength) else { return }
            MetadataBox.from(context).metadata.set(value, forKey: key)
        }
        callbacks.onUInt64 = { key, keyLength, value, context in
            guard let key = kvString(key, keyLength) else { return }
            MetadataBox.from(context).metadata.set(value, forKey: key)
        }
        callbacks.onDouble = { key, keyLength, value, context in
            guard let key = kvString(key, keyLength) else { return }
            MetadataBox.from(context).metadata.set(value, forKey: key)
        }
        callbacks.onBool = { key, keyLength, value, context in
            guard let key = kvString(key, keyLength) else { return }
            MetadataBox.from(context).metadata.set(value, forKey: key)
        }
        callbacks.onDate = { key, keyLength, nanoseconds, context in
            guard let key = kvString(key, keyLength) else { return }
            // The same nanoseconds-to-seconds conversion the report userInfo
            // stitch uses, so a date set via the userInfo API reads back as
            // the identical instant from a report and from this metadata.
            let date = Date(timeIntervalSince1970: Double(nanoseconds) / 1_000_000_000)
            MetadataBox.from(context).metadata.set(date, forKey: key)
        }
        callbacks.onRemoved = { key, keyLength, context in
            guard let key = kvString(key, keyLength) else { return }
            MetadataBox.from(context).metadata.removeValue(forKey: key)
        }
        kskvs_iterate(store, &callbacks, Unmanaged.passUnretained(box).toOpaque())

        // A bag that nets out empty means the run persisted no effective
        // userInfo; absence is nil, never an empty bag.
        return box.metadata.isEmpty ? nil : box.metadata
    }
}

/// Mutable target for the non-capturing C iteration callbacks.
private final class MetadataBox {
    var metadata = Metadata()

    static func from(_ context: UnsafeMutableRawPointer?) -> MetadataBox {
        Unmanaged<MetadataBox>.fromOpaque(context!).takeUnretainedValue()
    }
}

/// The buffer's bytes as a string; nil when not valid UTF-8. KV keys and
/// values are length-delimited, not NUL-terminated.
private func kvString(_ bytes: UnsafePointer<CChar>?, _ length: UInt16) -> String? {
    guard let bytes else {
        return nil
    }
    return bytes.withMemoryRebound(to: UInt8.self, capacity: Int(length)) {
        String(bytes: UnsafeBufferPointer(start: $0, count: Int(length)), encoding: .utf8)
    }
}

/// The fixed-size C char array's contents up to its NUL (the reader guarantees
/// termination); nil when not valid UTF-8.
private func cArrayString<T>(_ array: inout T) -> String? {
    withUnsafePointer(to: &array) {
        String(validatingUTF8: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
    }
}

extension RunSummary {
    fileprivate func with(sessions: Sessions) -> RunSummary {
        RunSummary(
            schemaVersion: schemaVersion, sdkVersion: sdkVersion, runID: runID, deviceID: deviceID,
            userID: userID, startedAtMs: startedAtMs, endedAtMs: endedAtMs, isBeingDebugged: isBeingDebugged,
            outcome: outcome, durations: durations, sessions: sessions, app: app, os: os, device: device,
            metadata: metadata)
    }

    fileprivate func with(metadata: Metadata) -> RunSummary {
        RunSummary(
            schemaVersion: schemaVersion, sdkVersion: sdkVersion, runID: runID, deviceID: deviceID,
            userID: userID, startedAtMs: startedAtMs, endedAtMs: endedAtMs, isBeingDebugged: isBeingDebugged,
            outcome: outcome, durations: durations, sessions: sessions, app: app, os: os, device: device,
            metadata: metadata)
    }
}
