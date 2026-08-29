//
//  MetadataValue.swift
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

/// A single JSON value.
public enum MetadataValue: Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case double(Double)
    case string(String)
    indirect case array([MetadataValue])
    indirect case object([String: MetadataValue])
}

extension MetadataValue: Equatable {
    /// Numeric cases compare by value: JSON does not distinguish `1`, `1.0`,
    /// and an unsigned `1`, and a Codable round-trip may re-type them, so
    /// equality must not either.
    public static func == (lhs: MetadataValue, rhs: MetadataValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let l), .bool(let r)): return l == r
        case (.string(let l), .string(let r)): return l == r
        case (.array(let l), .array(let r)): return l == r
        case (.object(let l), .object(let r)): return l == r
        case (.integer(let l), .integer(let r)): return l == r
        case (.unsignedInteger(let l), .unsignedInteger(let r)): return l == r
        case (.double(let l), .double(let r)): return l == r
        case (.integer(let l), .unsignedInteger(let r)), (.unsignedInteger(let r), .integer(let l)):
            return l >= 0 && UInt64(l) == r
        case (.integer(let l), .double(let r)), (.double(let r), .integer(let l)):
            return Int64(exactly: r) == l
        case (.unsignedInteger(let l), .double(let r)), (.double(let r), .unsignedInteger(let l)):
            return UInt64(exactly: r) == l
        default: return false
        }
    }
}

extension MetadataValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([MetadataValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: MetadataValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Value is not valid JSON.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .unsignedInteger(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// A value that can be stored in a `Metadata` bag.
public protocol MetadataValueConvertible {
    var metadataValue: MetadataValue { get }
}

/// A value that can be read back from a `Metadata` bag.
public protocol MetadataValueDecodable {
    static func decode(from value: MetadataValue) -> Self?
}

/// A value that can be both stored in and read back from a `Metadata` bag.
public protocol MetadataValueRepresentable: MetadataValueConvertible, MetadataValueDecodable {}

// MARK: - Storable

extension String: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .string(self) }
}
extension Bool: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .bool(self) }
}
extension Int: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .integer(Int64(self)) }
}
extension Int64: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .integer(self) }
}
extension UInt: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .unsignedInteger(UInt64(self)) }
}
extension UInt64: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .unsignedInteger(self) }
}
extension Double: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .double(self) }
}
extension Float: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .double(Double(self)) }
}
extension Date: MetadataValueConvertible {
    /// Stored as seconds since 1970 (a JSON double).
    public var metadataValue: MetadataValue { .double(timeIntervalSince1970) }
}
extension MetadataValue: MetadataValueConvertible {
    public var metadataValue: MetadataValue { self }
}
extension Array: MetadataValueConvertible where Element: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .array(map(\.metadataValue)) }
}
extension Dictionary: MetadataValueConvertible where Key == String, Value: MetadataValueConvertible {
    public var metadataValue: MetadataValue { .object(mapValues(\.metadataValue)) }
}
extension Optional: MetadataValueConvertible where Wrapped: MetadataValueConvertible {
    public var metadataValue: MetadataValue {
        switch self {
        case .some(let value): value.metadataValue
        case .none: .null
        }
    }
}

// MARK: - Readable

extension String: MetadataValueDecodable {
    public static func decode(from value: MetadataValue) -> String? {
        guard case .string(let value) = value else { return nil }
        return value
    }
}
extension Bool: MetadataValueDecodable {
    public static func decode(from value: MetadataValue) -> Bool? {
        guard case .bool(let value) = value else { return nil }
        return value
    }
}
extension Int: MetadataValueDecodable {
    /// Accepts any numeric case whose value is exactly representable; a
    /// Codable round-trip may re-type numbers, so typed reads must not care.
    public static func decode(from value: MetadataValue) -> Int? {
        switch value {
        case .integer(let value): Int(exactly: value)
        case .unsignedInteger(let value): Int(exactly: value)
        case .double(let value): Int(exactly: value)
        default: nil
        }
    }
}
extension Int64: MetadataValueDecodable {
    /// Accepts any numeric case whose value is exactly representable; a
    /// Codable round-trip may re-type numbers, so typed reads must not care.
    public static func decode(from value: MetadataValue) -> Int64? {
        switch value {
        case .integer(let value): value
        case .unsignedInteger(let value): Int64(exactly: value)
        case .double(let value): Int64(exactly: value)
        default: nil
        }
    }
}
extension UInt64: MetadataValueDecodable {
    /// Accepts any numeric case whose value is exactly representable; a
    /// Codable round-trip may re-type numbers, so typed reads must not care.
    public static func decode(from value: MetadataValue) -> UInt64? {
        switch value {
        case .integer(let value): UInt64(exactly: value)
        case .unsignedInteger(let value): value
        case .double(let value): UInt64(exactly: value)
        default: nil
        }
    }
}
extension Date: MetadataValueDecodable {
    public static func decode(from value: MetadataValue) -> Date? {
        Double.decode(from: value).map(Date.init(timeIntervalSince1970:))
    }
}
extension Double: MetadataValueDecodable {
    /// An integer reads as a `Double`; a fractional `Double` does not read as an integer.
    public static func decode(from value: MetadataValue) -> Double? {
        switch value {
        case .double(let value): value
        case .integer(let value): Double(value)
        case .unsignedInteger(let value): Double(value)
        default: nil
        }
    }
}

extension MetadataValue: MetadataValueDecodable {
    public static func decode(from value: MetadataValue) -> MetadataValue? { value }
}
extension Array: MetadataValueDecodable where Element: MetadataValueDecodable {
    /// nil unless the value is an array whose every element reads as `Element`;
    /// typed reads are exact, never partial.
    public static func decode(from value: MetadataValue) -> [Element]? {
        guard case .array(let values) = value else { return nil }
        let elements = values.compactMap(Element.decode(from:))
        return elements.count == values.count ? elements : nil
    }
}
extension Dictionary: MetadataValueDecodable where Key == String, Value: MetadataValueDecodable {
    /// nil unless the value is an object whose every value reads as `Value`;
    /// typed reads are exact, never partial.
    public static func decode(from value: MetadataValue) -> [String: Value]? {
        guard case .object(let values) = value else { return nil }
        var decoded: [String: Value] = [:]
        decoded.reserveCapacity(values.count)
        for (key, element) in values {
            guard let element = Value.decode(from: element) else { return nil }
            decoded[key] = element
        }
        return decoded
    }
}

extension String: MetadataValueRepresentable {}
extension Bool: MetadataValueRepresentable {}
extension Int: MetadataValueRepresentable {}
extension Int64: MetadataValueRepresentable {}
extension UInt64: MetadataValueRepresentable {}
extension Double: MetadataValueRepresentable {}
extension Date: MetadataValueRepresentable {}
/// The heterogeneous escape hatch: any JSON shape stores and reads as itself.
extension MetadataValue: MetadataValueRepresentable {}
extension Array: MetadataValueRepresentable where Element: MetadataValueRepresentable {}
extension Dictionary: MetadataValueRepresentable where Key == String, Value: MetadataValueRepresentable {}
