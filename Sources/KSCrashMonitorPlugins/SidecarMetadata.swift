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
        set {
            guard let newValue else {
                checkAccepted(kskvs_removeValue(store, key), key: key)
                return
            }
            // A date keeps its own slot so the report carries a date, not a number.
            if let date = newValue as? Date {
                // An unrepresentable date removes the key rather than storing a
                // stand-in, so a read never reports an instant that was never set.
                if let nanoseconds = date.nanosecondsSince1970 {
                    checkAccepted(kskvs_setDate(store, key, nanoseconds), key: key)
                } else {
                    checkAccepted(kskvs_removeValue(store, key), key: key)
                }
                return
            }
            switch newValue.metadataValue {
            case .string(let value): checkAccepted(kskvs_setString(store, key, value), key: key)
            case .integer(let value): checkAccepted(kskvs_setInt64(store, key, value), key: key)
            case .unsignedInteger(let value): checkAccepted(kskvs_setUInt64(store, key, value), key: key)
            case .double(let value): checkAccepted(kskvs_setDouble(store, key, value), key: key)
            case .bool(let value): checkAccepted(kskvs_setBool(store, key, value), key: key)
            case .null: checkAccepted(kskvs_removeValue(store, key), key: key)
            case .array, .object:
                // Containers persist as one JSON value; the store records the
                // bytes and every consumer parses them at read time. A shape
                // JSON cannot carry (a non-finite number) is a refused write.
                let encoded = try? JSONEncoder().encode(newValue.metadataValue)
                guard let encoded else {
                    checkAccepted(false, key: key)
                    return
                }
                let accepted = encoded.withUnsafeBytes { buffer in
                    kskvs_setJSON(
                        store, key, buffer.baseAddress?.assumingMemoryBound(to: CChar.self), buffer.count)
                }
                checkAccepted(accepted, key: key)
            }
        }
    }

    public func removeValue(forKey key: String) {
        checkAccepted(kskvs_removeValue(store, key), key: key)
    }

    /// A refused write is loud in debug and silently dropped in release.
    /// Usually a programmer error (a key or value past the record format's
    /// 64KB bound, a non-finite number in a container); rarely the store
    /// failing to grow.
    private func checkAccepted(_ accepted: Bool, key: String) {
        assert(
            accepted,
            "metadata write failed for key \"\(key)\": past the record format's bound, or the store could not grow")
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
        callbacks.onJSON = { key, keyLength, _, _, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).names.insert(key)
        }
        callbacks.onRemoved = { key, keyLength, context in
            guard let key = kvString(key, keyLength) else { return }
            Keys.from(context).names.remove(key)
        }
        kskvs_iterate(store, &callbacks, Unmanaged.passUnretained(keys).toOpaque())
        return keys.names.sorted()
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
            guard let json else { return }
            // The store does not validate JSON, so undecodable bytes (a torn
            // or foreign record) are absence, never a trap; so is anything
            // that decodes but is not a container, the only JSON values.
            let data = Data(bytes: json, count: Int(jsonLength))
            guard let value = try? JSONDecoder().decode(MetadataValue.self, from: data) else { return }
            switch value {
            case .array, .object: Lookup.from(context).value = value
            default: break
            }
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

/// The buffer's bytes as a string; nil when not valid UTF-8. KV keys and
/// values are length-delimited, not NUL-terminated.
func kvString(_ bytes: UnsafePointer<CChar>?, _ length: UInt16) -> String? {
    guard let bytes else {
        return nil
    }
    return bytes.withMemoryRebound(to: UInt8.self, capacity: Int(length)) {
        String(bytes: UnsafeBufferPointer(start: $0, count: Int(length)), encoding: .utf8)
    }
}
