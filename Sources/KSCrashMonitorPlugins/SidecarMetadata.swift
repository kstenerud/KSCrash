//
//  SidecarMetadata.swift
//
//  Created by Alexander Cohen on 2025-12-14.
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
import KSCrashSwiftCore
import os

/// A `MetadataStore` over one run sidecar file: every write is persisted
/// immediately and survives a crash. Scalars persist natively; arrays and
/// dictionaries persist as one JSON value each. Not synchronized: the
/// caller owns serialization of every access.
///
/// Dates range from 1677-09-21 to 2262-04-11; assigning one outside that range
/// removes the key instead of storing it.
public final class SidecarMetadata: MetadataStore, @unchecked Sendable {
    package struct OpenError: Error {
        package let status: KSKVSOpenStatus
    }

    private let store: OpaquePointer

    private init(store: OpaquePointer) {
        self.store = store
    }

    deinit {
        kskvs_destroy(store)
    }

    /// Opens the writable store at `path`, creating it as needed.
    package static func creating(at path: String, config: KSKVSConfig) throws -> SidecarMetadata {
        var config = config
        var status = KSKVSOpenSuccess
        guard let store = kskvs_create(path, KSKVSModeReadWriteCreate, &config, &status) else {
            throw OpenError(status: status)
        }
        return SidecarMetadata(store: store)
    }

    /// A read-only view of the store at `path`; nil when absent or unreadable.
    static func reading(at path: String) -> SidecarMetadata? {
        kskvs_create(path, KSKVSModeRead, nil, nil).map { SidecarMetadata(store: $0) }
    }

    public subscript<Value: MetadataValueRepresentable>(key: String) -> Value? {
        get {
            guard let stored = currentValue(forKey: key) else { return nil }
            return Value.decode(from: stored)
        }
        set { apply(PreparedValue(newValue), forKey: key) }
    }

    /// A value converted and serialized, ready for the store.
    ///
    /// Building one touches nothing shared, so a caller that serializes access
    /// to the store builds it *before* taking that lock: for a container the
    /// work is a full tree walk plus a JSON encode, and holding a lock across
    /// it would make every other thread's metadata write wait on this one.
    package struct PreparedValue {
        fileprivate enum Payload {
            case remove
            case string(String)
            case integer(Int64)
            case unsignedInteger(UInt64)
            case double(Double)
            case bool(Bool)
            case date(Int64)
            case json(Data)
        }
        fileprivate let payload: Payload

        package init(_ value: (some MetadataValueConvertible)?) {
            guard let value else {
                payload = .remove
                return
            }
            // A date keeps its own slot so the report carries a date, not a
            // number. An unrepresentable one removes the key rather than
            // storing a stand-in, so a read never reports an instant that was
            // never set; every other unrepresentable value below does the same.
            if let date = value as? Date {
                payload = date.nanosecondsSince1970.map(Payload.date) ?? .remove
                return
            }
            // Convert once: for containers metadataValue walks the whole tree.
            let converted = value.metadataValue
            switch converted {
            case .string(let value): payload = .string(value)
            case .integer(let value): payload = .integer(value)
            case .unsignedInteger(let value): payload = .unsignedInteger(value)
            case .bool(let value): payload = .bool(value)
            case .null: payload = .remove
            case .double(let value):
                // JSON carries no non-finite number: the C encoder emits
                // `1e999` for an infinity and `null` for a NaN, neither of
                // which a strict reader accepts, so one would make every
                // report and summary of the run undeliverable.
                payload = value.isFinite ? .double(value) : .remove
            case .array, .object:
                // Containers persist as one JSON value, exactly as given: the
                // store records the bytes and every consumer parses them at
                // read time, where nulls resolve to absence. Nothing walks or
                // rewrites the value here; this path runs inside the host app.
                let encoded = try? JSONEncoder().encode(converted)
                payload = encoded.map(Payload.json) ?? .remove
            }
        }
    }

    /// Writes a prepared value under `key`.
    package func apply(_ prepared: PreparedValue, forKey key: String) {
        switch prepared.payload {
        case .remove: remove(key)
        case .string(let value): record(key) { kskvs_setString(store, key, value) }
        case .integer(let value): record(key) { kskvs_setInt64(store, key, value) }
        case .unsignedInteger(let value): record(key) { kskvs_setUInt64(store, key, value) }
        case .double(let value): record(key) { kskvs_setDouble(store, key, value) }
        case .bool(let value): record(key) { kskvs_setBool(store, key, value) }
        case .date(let nanoseconds): record(key) { kskvs_setDate(store, key, nanoseconds) }
        case .json(let encoded):
            record(key) {
                encoded.withUnsafeBytes { buffer in
                    kskvs_setJSON(store, key, buffer.baseAddress?.assumingMemoryBound(to: CChar.self), buffer.count)
                }
            }
        }
    }

    public func removeValue(forKey key: String) {
        remove(key)
    }

    /// Applies a write, removing the key when the store refuses it.
    ///
    /// Refusal is data-dependent, not programmer error: a key or value past
    /// the record format's 64KB bound, or a store that cannot grow. The key
    /// must not keep serving the value the app believes it replaced, so it
    /// becomes absent, the same outcome as a value the model cannot represent.
    private func record(_ key: String, _ write: () -> Bool) {
        if write() {
            return
        }
        os_log(.error, "Metadata write for key \"%{public}@\" refused; removing the key", key)
        remove(key)
    }

    private func remove(_ key: String) {
        if !kskvs_removeValue(store, key) {
            os_log(.error, "Metadata removal for key \"%{public}@\" failed", key)
        }
    }

    public var keys: [String] { keySnapshot().resolvedNames }

    /// The store's keys, with container payloads copied out but not yet judged.
    ///
    /// Two phases so a caller that serializes store access can release its
    /// lock before `resolvedNames` does the parsing: deciding whether a
    /// container record reads as a value is a full JSON parse per record, and
    /// running those under the lock would block every writing thread for the
    /// length of the walk.
    package struct KeySnapshot {
        fileprivate var names: Set<String> = []
        fileprivate var containers: [String: Data] = [:]

        /// The keys whose read is a value. Containers are judged by the same
        /// reader the getter uses, so this never names a key that reads nil.
        package var resolvedNames: [String] {
            var resolved = names
            for (key, payload) in containers where kvContainer(payload) == nil {
                resolved.remove(key)
            }
            return resolved.sorted()
        }
    }

    package func keySnapshot() -> KeySnapshot {
        final class Keys {
            var snapshot = KeySnapshot()
            static func from(_ context: UnsafeMutableRawPointer?) -> Keys {
                Unmanaged<Keys>.fromOpaque(context!).takeUnretainedValue()
            }
        }
        let keys = Keys()
        var callbacks = KSKVSCallbacks()
        callbacks.onString = { key, keyLength, value, valueLength, context in
            // Judged by the reader the getter uses: bytes that are not UTF-8
            // read as absence, and a key that reads as absence is not a key.
            guard let key = kvString(key, keyLength), kvString(value, valueLength) != nil else { return }
            Keys.from(context).snapshot.names.insert(key)
        }
        callbacks.onInt64 = { key, keyLength, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).snapshot.names.insert(key)
        }
        callbacks.onUInt64 = { key, keyLength, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).snapshot.names.insert(key)
        }
        callbacks.onDouble = { key, keyLength, value, context in
            // A non-finite double has no JSON form, so the getter calls it
            // absence and this must too.
            guard let key = kvString(key, keyLength), value.isFinite else { return }
            Keys.from(context).snapshot.names.insert(key)
        }
        callbacks.onBool = { key, keyLength, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).snapshot.names.insert(key)
        }
        callbacks.onDate = { key, keyLength, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).snapshot.names.insert(key)
        }
        callbacks.onJSON = { key, keyLength, json, jsonLength, context in
            // Copied, not parsed: the bytes live in the store's mapping and
            // this callback runs where the caller's lock is held. The verdict
            // comes later, in resolvedNames.
            guard let key = kvString(key, keyLength), let json else { return }
            let payload = Data(bytes: json, count: Int(jsonLength))
            let keys = Keys.from(context)
            keys.snapshot.names.insert(key)
            keys.snapshot.containers[key] = payload
        }
        callbacks.onRemoved = { key, keyLength, context in
            guard let key = kvString(key, keyLength) else { return }
            let keys = Keys.from(context)
            keys.snapshot.names.remove(key)
            keys.snapshot.containers.removeValue(forKey: key)
        }
        kskvs_iterate(store, &callbacks, Unmanaged.passUnretained(keys).toOpaque())
        return keys.snapshot
    }

    /// The key's resolved value as the model represents it; nil for no value.
    private func currentValue(forKey key: String) -> MetadataValue? {
        final class Lookup {
            var value: MetadataValue?
            static func from(_ context: UnsafeMutableRawPointer?) -> Lookup {
                Unmanaged<Lookup>.fromOpaque(context!).takeUnretainedValue()
            }
        }
        let lookup = Lookup()
        var callbacks = KSKVSCallbacks()
        callbacks.onString = { _, _, value, valueLength, context in
            guard let value = kvString(value, valueLength) else { return }
            Lookup.from(context).value = .string(value)
        }
        callbacks.onInt64 = { _, _, value, context in
            Lookup.from(context).value = .integer(value)
        }
        callbacks.onUInt64 = { _, _, value, context in
            Lookup.from(context).value = .unsignedInteger(value)
        }
        callbacks.onDouble = { _, _, value, context in
            // JSON carries no non-finite number, so a record holding one (a
            // foreign writer, or a build that predates the write-side guard)
            // reads as absence rather than as a value no consumer can encode.
            guard value.isFinite else { return }
            Lookup.from(context).value = .double(value)
        }
        callbacks.onBool = { _, _, value, context in
            Lookup.from(context).value = .bool(value)
        }
        callbacks.onDate = { _, _, nanoseconds, context in
            // Date.decode reads seconds since 1970, the model's date representation.
            Lookup.from(context).value = .double(Double(nanoseconds) / Double(NSEC_PER_SEC))
        }
        callbacks.onJSON = { _, _, json, jsonLength, context in
            Lookup.from(context).value = kvContainer(json, jsonLength)
        }
        kskvs_lookup(store, key, &callbacks, Unmanaged.passUnretained(lookup).toOpaque())
        return lookup.value
    }
}

extension Date {
    /// Nanoseconds since 1970, or nil for a date the store cannot represent.
    /// A non-finite interval fails both comparisons and yields nil.
    var nanosecondsSince1970: Int64? {
        let nanos = timeIntervalSince1970 * Double(NSEC_PER_SEC)
        guard nanos >= -9.2e18, nanos <= 9.2e18 else { return nil }
        return Int64(nanos)
    }
}

/// The container a JSON record holds, or nil when the bytes are not one.
///
/// The single reader for JSON records: `keys`, the getter, and the
/// run-summary stitch all judge a record here, so none of them can list,
/// return, or deliver a record the others treat as absent. The store does not
/// validate JSON, so undecodable bytes (a torn or foreign record) are absence,
/// never a trap; so is anything that decodes but is not a container, the only
/// JSON values. The bytes are read in place out of the store's mapping, which
/// outlives the call.
package func kvContainer(_ bytes: UnsafePointer<CChar>?, _ length: UInt16) -> MetadataValue? {
    guard let bytes else {
        return nil
    }
    return kvContainer(
        Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes), count: Int(length), deallocator: .none))
}

package func kvContainer(_ data: Data) -> MetadataValue? {
    guard let value = try? JSONDecoder().decode(MetadataValue.self, from: data) else {
        return nil
    }
    switch value {
    case .array, .object: return value
    default: return nil
    }
}

/// The buffer's bytes as a string; nil when not valid UTF-8. KV keys and
/// values are length-delimited, not NUL-terminated.
package func kvString(_ bytes: UnsafePointer<CChar>?, _ length: UInt16) -> String? {
    guard let bytes else {
        return nil
    }
    return bytes.withMemoryRebound(to: UInt8.self, capacity: Int(length)) {
        String(bytes: UnsafeBufferPointer(start: $0, count: Int(length)), encoding: .utf8)
    }
}
