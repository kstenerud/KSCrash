//
//  LiveMetadata.swift
//
//  Created by Alexander Cohen on 2026-08-22.
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
import KSCrashSwiftCore

/// The run's metadata as the crash reporter records it: this class owns the
/// run's UserInfo sidecar store, the same file the report stitch and the
/// run-summary metadata merge read at delivery. Every write lands in the
/// crash-safe store immediately; every read replays it. Before install there
/// is no store: sets are no-ops and reads are nil.
public final class LiveMetadata: MetadataStore, Sendable {
    /// The store's shapes. Readers need no configuration, so these bound only
    /// what a writer accepts; longer keys and strings are truncated.
    private enum StoreLimits {
        static let initialCapacity: UInt32 = 4096
        static let maxKeyLength: UInt16 = 256
        static let maxStringLength: UInt16 = 1024
    }

    /// The kvs engine is single-writer and unsynchronized; this is the one
    /// handle on the file, and every touch of it happens under the lock.
    private let store = UnfairLock<OpaquePointer?>(nil)

    init() {}

    /// Opens the run's store at `<runSidecarsDirectory>/<runID>/UserInfo.ksscr`.
    /// Called once by install; a second call keeps the first store.
    func attach(runSidecarsDirectory: URL, runID: String) {
        guard !runID.isEmpty else { return }
        let directory = runSidecarsDirectory.appendingPathComponent(runID, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(KSCRS_USERINFO_RUN_SIDECAR_FILENAME).path
        var config = KSKVSConfig(
            initialCapacity: StoreLimits.initialCapacity,
            maxKeyLength: StoreLimits.maxKeyLength,
            maxStringLength: StoreLimits.maxStringLength)
        store.withLock { handle in
            guard handle == nil else { return }
            handle = kskvs_create(path, KSKVSModeReadWriteCreate, &config, nil)
        }
    }

    public subscript<Value: MetadataValueRepresentable>(key: String) -> Value? {
        get {
            guard let stored = currentValue(forKey: key) else { return nil }
            return Value.decode(from: stored)
        }
        set {
            store.withLock { handle in
                guard let handle else { return }
                guard let newValue else {
                    kskvs_removeValue(handle, key)
                    return
                }
                // A date keeps its own slot so the report carries a date, not a number.
                if let date = newValue as? Date {
                    kskvs_setDate(handle, key, date.nanosecondsSince1970)
                    return
                }
                switch newValue.metadataValue {
                case .string(let value): kskvs_setString(handle, key, value)
                case .integer(let value): kskvs_setInt64(handle, key, value)
                case .unsignedInteger(let value): kskvs_setUInt64(handle, key, value)
                case .double(let value): kskvs_setDouble(handle, key, value)
                case .bool(let value): kskvs_setBool(handle, key, value)
                case .null: kskvs_removeValue(handle, key)
                case .array, .object:
                    // Unreachable: no container type is MetadataValueRepresentable.
                    preconditionFailure("the live metadata store holds scalars only")
                }
            }
        }
    }

    public func removeValue(forKey key: String) {
        store.withLock { handle in
            guard let handle else { return }
            kskvs_removeValue(handle, key)
        }
    }

    public var keys: [String] {
        final class Keys {
            var names: Set<String> = []
            static func from(_ context: UnsafeMutableRawPointer?) -> Keys {
                Unmanaged<Keys>.fromOpaque(context!).takeUnretainedValue()
            }
        }
        let keys = Keys()
        var callbacks = KSKVSCallbacks()
        callbacks.onString = { key, keyLength, _, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).names.insert(key)
        }
        callbacks.onInt64 = { key, keyLength, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).names.insert(key)
        }
        callbacks.onUInt64 = { key, keyLength, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).names.insert(key)
        }
        callbacks.onDouble = { key, keyLength, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).names.insert(key)
        }
        callbacks.onBool = { key, keyLength, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).names.insert(key)
        }
        callbacks.onDate = { key, keyLength, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).names.insert(key)
        }
        callbacks.onRemoved = { key, keyLength, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).names.remove(key)
        }
        store.withLock { handle in
            guard let handle else { return }
            kskvs_iterate(handle, &callbacks, Unmanaged.passUnretained(keys).toOpaque())
        }
        return keys.names.sorted()
    }

    /// The key's resolved value as the model represents it; nil for no value.
    private func currentValue(forKey key: String) -> MetadataValue? {
        final class Lookup {
            let key: String
            var value: MetadataValue?
            init(key: String) { self.key = key }
            static func from(_ context: UnsafeMutableRawPointer?) -> Lookup {
                Unmanaged<Lookup>.fromOpaque(context!).takeUnretainedValue()
            }
        }
        let lookup = Lookup(key: key)
        var callbacks = KSKVSCallbacks()
        callbacks.onString = { key, keyLength, value, valueLength, context in
            let lookup = Lookup.from(context)
            guard kvString(key, keyLength) == lookup.key, let value = kvString(value, valueLength) else { return }
            lookup.value = .string(value)
        }
        callbacks.onInt64 = { key, keyLength, value, context in
            let lookup = Lookup.from(context)
            guard kvString(key, keyLength) == lookup.key else { return }
            lookup.value = .integer(value)
        }
        callbacks.onUInt64 = { key, keyLength, value, context in
            let lookup = Lookup.from(context)
            guard kvString(key, keyLength) == lookup.key else { return }
            lookup.value = .unsignedInteger(value)
        }
        callbacks.onDouble = { key, keyLength, value, context in
            let lookup = Lookup.from(context)
            guard kvString(key, keyLength) == lookup.key else { return }
            lookup.value = .double(value)
        }
        callbacks.onBool = { key, keyLength, value, context in
            let lookup = Lookup.from(context)
            guard kvString(key, keyLength) == lookup.key else { return }
            lookup.value = .bool(value)
        }
        callbacks.onDate = { key, keyLength, nanoseconds, context in
            let lookup = Lookup.from(context)
            guard kvString(key, keyLength) == lookup.key else { return }
            // Date.decode reads seconds since 1970, the model's date representation.
            lookup.value = .double(Double(nanoseconds) / Double(NSEC_PER_SEC))
        }
        callbacks.onRemoved = { key, keyLength, context in
            let lookup = Lookup.from(context)
            guard kvString(key, keyLength) == lookup.key else { return }
            lookup.value = nil
        }
        store.withLock { handle in
            guard let handle else { return }
            kskvs_iterate(handle, &callbacks, Unmanaged.passUnretained(lookup).toOpaque())
        }
        return lookup.value
    }
}

extension Date {
    fileprivate var nanosecondsSince1970: UInt64 {
        let seconds = timeIntervalSince1970
        return seconds <= 0 ? 0 : UInt64(seconds * Double(NSEC_PER_SEC))
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
