//
//  Store+Runs.swift
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
import KSCrashRecordingCore
import KSCrashReportModel
import os

/// The run-summary half of the store. The store deletes only what a run
/// exclusively owns (its `.run` files); shared files (`.sessions`, the sidecar
/// directory) are reclaimed by the directory-level sweep, never here.
extension Store {
    /// The run's summary in deliverable form: session records merged from
    /// `.sessions`, metadata stitched from the run's UserInfo sidecar. nil
    /// when the run has no summary on disk, or when reading its `.run`,
    /// `.sessions`, or UserInfo sidecar fails in a way a retry could succeed
    /// at (the data is unknown, so the run waits for a later send). Throws
    /// when the `.run` file was read but does not decode: that is
    /// deterministic, so the send surfaces it as a kept item instead of
    /// silently retrying forever. An absent `.sessions`
    /// means empty records; an absent, empty, or unrecoverably corrupt
    /// sidecar means nil metadata.
    ///
    /// A snapshot can go stale (a concurrent send may deliver and delete a
    /// run after it was captured); a stale or artifact-only run reads as nil
    /// here. Under a send's claim that check is race-free, because deletes
    /// only happen under the claim.
    func summary(of run: Run) throws -> RunSummary? {
        // The payload is read here, per item, never held by the snapshot: a
        // send keeps at most one summary in memory no matter how many runs
        // are pending.
        guard let summary = try decodedBaseSummary(of: run) else {
            return nil
        }
        // The persisted `.run` deliberately carries neither session records nor
        // metadata (the install path stays cheap; the records' and userInfo's
        // single source of truth are their own files). Both are attached here,
        // at delivery. Absence degrades gracefully (empty records, nil
        // metadata), but an UNREADABLE file means the data is unknown, not
        // absent: delivering would ship an incomplete summary and then delete
        // the intact file, so the run is skipped this send and retried by the
        // next one.
        guard let merged = mergingSessions(into: summary, for: run) else {
            return nil
        }
        return stitchingMetadata(into: merged, for: run)
    }

    /// Delete this run's own `.run` file.
    func removeSummary(of run: Run) throws {
        guard let file = run.summaryFile else {
            return
        }
        try FileManager.default.removeItem(at: file)
    }

    private func decodedBaseSummary(of run: Run) throws -> RunSummary? {
        guard let file = run.summaryFile, let data = try? Data(contentsOf: file) else {
            // Artifact-only run, stale entry, or unreadable right now.
            return nil
        }
        do {
            return try JSONDecoder().decode(RunSummary.self, from: data)
        } catch {
            os_log(
                .error, "Undecodable run summary %{public}@: %{public}@", run.runID.description,
                String(describing: error))
            throw error
        }
    }

    // MARK: - Sessions

    /// Replace `base`'s (empty) session records with the run's recorded
    /// sessions, read through the C `.sessions` reader. nil when the file
    /// exists but cannot be read: the records are unknown, not absent, and
    /// the caller must not deliver.
    private func mergingSessions(into base: RunSummary, for run: Run) -> RunSummary? {
        // No file means the run cut no sessions (the writer creates the file
        // lazily on the first cut).
        guard let sessionsFile = run.sessionsFile else {
            return base
        }
        guard let reader = kssr_open(sessionsFile.path) else {
            return nil  // allocation failure: unknown, do not deliver
        }
        defer { kssr_close(reader) }
        guard kssr_lastError(reader) == 0 else {
            return nil
        }
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

    /// Attach the app data recorded for this run via the userInfo API, as a
    /// `Metadata` bag on a copy of `base`. Returns `base` untouched when the
    /// run recorded none, and nil when reading the sidecar fails in a way a
    /// retry could succeed at: the metadata is unknown, not absent, and the
    /// caller must not deliver.
    private func stitchingMetadata(into base: RunSummary, for run: Run) -> RunSummary? {
        // Metadata is stitched at delivery from the run's UserInfo sidecar,
        // never read live and never baked into the `.run`, exactly like
        // session_id from `.sessions` and userInfo on reports. The sidecar is
        // the same file the report stitch reads, so a report and this run's
        // summary always agree on the run's app data.
        guard let sidecarDirectory = run.sidecarDirectory else {
            return base
        }
        let path = sidecarDirectory.appendingPathComponent(KSCRS_USERINFO_RUN_SIDECAR_FILENAME).path
        // The monitor creates the sidecar when it is enabled, so an absent
        // file just means the run never enabled UserInfo. A corrupt file (a
        // crash mid-creation) holds nothing any later read could recover, so
        // both deliver without metadata, matching the report stitch on the
        // same file. Only a failure that may not recur makes the run wait; a
        // summary is telemetry and must never be lost to an unrecoverable
        // file. Read mode needs no config.
        var status = KSKVSOpenSuccess
        guard let store = kskvs_create(path, KSKVSModeRead, nil, &status) else {
            return status == KSKVSOpenFailure ? nil : base
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
        callbacks.onJSON = { key, keyLength, json, jsonLength, context in
            guard let key = kvString(key, keyLength), let json else { return }
            // The store does not validate JSON, so undecodable bytes (a torn
            // or foreign record) drop that entry, matching the report stitch;
            // so does anything but a container, the only JSON values.
            let data = Data(bytes: json, count: Int(jsonLength))
            guard let value = try? JSONDecoder().decode(MetadataValue.self, from: data) else { return }
            switch value {
            case .array, .object: MetadataBox.from(context).metadata.set(value, forKey: key)
            default: break
            }
        }
        callbacks.onRemoved = { key, keyLength, context in
            guard let key = kvString(key, keyLength) else { return }
            MetadataBox.from(context).metadata.removeValue(forKey: key)
        }
        kskvs_iterate(store, &callbacks, Unmanaged.passUnretained(box).toOpaque())

        // A bag that nets out empty means the run persisted no effective
        // userInfo; absence is nil, never an empty bag.
        return box.metadata.isEmpty ? base : base.with(metadata: box.metadata)
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
            schemaVersion: schemaVersion, sdkVersion: sdkVersion, id: id, deviceID: deviceID,
            userID: userID, startedAtMs: startedAtMs, endedAtMs: endedAtMs, isBeingDebugged: isBeingDebugged,
            outcome: outcome, durations: durations, sessions: sessions, app: app, os: os, device: device,
            metadata: metadata)
    }

    fileprivate func with(metadata: Metadata) -> RunSummary {
        RunSummary(
            schemaVersion: schemaVersion, sdkVersion: sdkVersion, id: id, deviceID: deviceID,
            userID: userID, startedAtMs: startedAtMs, endedAtMs: endedAtMs, isBeingDebugged: isBeingDebugged,
            outcome: outcome, durations: durations, sessions: sessions, app: app, os: os, device: device,
            metadata: metadata)
    }
}
