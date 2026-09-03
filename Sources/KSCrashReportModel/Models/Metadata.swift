//
//  Metadata.swift
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

/// A heterogeneous JSON key-value bag for app-supplied data on a report or run summary.
///
/// Values are stored and read as ordinary Swift types through `MetadataValueConvertible`
/// and `MetadataValueDecodable`; unsupported types are rejected at compile time. The whole
/// bag can also be built from, or decoded into, any `Codable` type.
public struct Metadata: Equatable, Sendable {
    private var storage: [String: MetadataValue]

    public init() {
        storage = [:]
    }

    /// Whether the bag holds no keys.
    public var isEmpty: Bool { storage.isEmpty }

    /// Stores `value` under `key`, replacing any existing value.
    public mutating func set(_ value: some MetadataValueConvertible, forKey key: String) {
        storage[key] = value.metadataValue
    }

    /// The value under `key` as `type`, or nil when the key is absent or holds a different type.
    public func value<Value: MetadataValueDecodable>(forKey key: String, as type: Value.Type = Value.self) -> Value? {
        guard let value = storage[key] else { return nil }
        return Value.decode(from: value)
    }

    /// Removes any value under `key`.
    public mutating func removeValue(forKey key: String) {
        storage.removeValue(forKey: key)
    }

    /// Whether a value is stored under `key`.
    public func contains(_ key: String) -> Bool {
        storage[key] != nil
    }

    public subscript<Value: MetadataValueDecodable>(key: String, as type: Value.Type) -> Value? {
        value(forKey: key, as: type)
    }

    /// Reads or writes a value under `key`. Assigning nil removes the key.
    public subscript<Value: MetadataValueRepresentable>(key: String) -> Value? {
        get { value(forKey: key) }
        set {
            if let newValue {
                set(newValue, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }

    /// The whole bag decoded into `type`. Dates are seconds since 1970, the
    /// same representation `set`/`value(forKey:as:)` use for `Date`.
    public func decoded<Value: Decodable>(as type: Value.Type = Value.self) throws -> Value {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Value.self, from: encoder.encode(self))
    }

    /// A bag built from any `Encodable` value; throws if `value` does not
    /// encode to a JSON object. Dates are seconds since 1970, the same
    /// representation `set`/`value(forKey:as:)` use for `Date`.
    public static func from(_ value: some Encodable) throws -> Metadata {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Metadata.self, from: encoder.encode(value))
    }
}

extension Metadata: Codable {
    public init(from decoder: Decoder) throws {
        storage = try [String: MetadataValue](from: decoder)
    }
    public func encode(to encoder: Encoder) throws {
        try storage.encode(to: encoder)
    }
}

extension Metadata: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .object(storage) }
}

/// The one place a monitor's section is read as its concrete type; the
/// public `monitorData(_:for:)` accessors on `Report` and `CrashError` both
/// go through it, so both read sections the same way.
extension Optional where Wrapped == [String: Metadata] {
    func decodedSection<Value: Decodable>(_ type: Value.Type, for monitorID: String) throws -> Value? {
        guard let section = self?[monitorID] else {
            return nil
        }
        return try section.decoded(as: Value.self)
    }
}
