//
//  AnyCodable.swift
//
//  Created by KSCrash on 2024.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// A type-erased Codable value that can represent any JSON-compatible type.
///
/// Use this type when you need to decode JSON values of unknown or mixed types,
/// such as user-defined custom data in crash reports.
public struct AnyCodable: Codable, @unchecked Sendable {
    /// The underlying value.
    /// - Note: This is marked @unchecked Sendable because the value is immutable
    ///   and only contains JSON-compatible types (primitives, arrays, dictionaries).
    public let value: Any

    /// Creates an AnyCodable from any value.
    public init(_ value: Any) {
        self.value = AnyCodable.convertToSendable(value)
    }

    private static func convertToSendable(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues { convertToSendable($0) }
        case let array as [Any]:
            return array.map { convertToSendable($0) }
        case let string as String:
            return string
        case let number as NSNumber:
            return number
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let int64 as Int64:
            return int64
        case let uint64 as UInt64:
            return uint64
        case let double as Double:
            return double
        case is NSNull:
            return NSNull()
        default:
            return String(describing: value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let int64 = try? container.decode(Int64.self) {
            self.value = int64
        } else if let uint64 = try? container.decode(UInt64.self) {
            self.value = uint64
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable cannot decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int64 as Int64:
            try container.encode(int64)
        case let uint64 as UInt64:
            try container.encode(uint64)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable cannot encode value of type \(type(of: value))"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}

// MARK: - Type-Safe Access

extension AnyCodable {
    /// Returns the value as a String, if possible.
    public var stringValue: String? {
        value as? String
    }

    /// Returns the value as an Int, if possible.
    public var intValue: Int? {
        value as? Int
    }

    /// Returns the value as a Double, if possible.
    public var doubleValue: Double? {
        value as? Double
    }

    /// Returns the value as a Bool, if possible.
    public var boolValue: Bool? {
        value as? Bool
    }

    /// Returns the value as an array, if possible.
    public var arrayValue: [Any]? {
        value as? [Any]
    }

    /// Returns the value as a dictionary, if possible.
    public var dictionaryValue: [String: Any]? {
        value as? [String: Any]
    }

    /// Returns true if the value is null.
    public var isNull: Bool {
        value is NSNull
    }
}

// MARK: - Equatable

extension AnyCodable: Equatable {
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (NSNull, NSNull):
            return true
        case (let lhs as Bool, let rhs as Bool):
            return lhs == rhs
        case (let lhs as Int, let rhs as Int):
            return lhs == rhs
        case (let lhs as Int64, let rhs as Int64):
            return lhs == rhs
        case (let lhs as UInt64, let rhs as UInt64):
            return lhs == rhs
        case (let lhs as Double, let rhs as Double):
            return lhs == rhs
        case (let lhs as String, let rhs as String):
            return lhs == rhs
        case (let lhs as [String: AnyCodable], let rhs as [String: AnyCodable]):
            return lhs == rhs
        case (let lhs as [AnyCodable], let rhs as [AnyCodable]):
            return lhs == rhs
        default:
            return false
        }
    }
}

// MARK: - Hashable

extension AnyCodable: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch value {
        case is NSNull:
            hasher.combine(0)
        case let value as Bool:
            hasher.combine(value)
        case let value as Int:
            hasher.combine(value)
        case let value as Int64:
            hasher.combine(value)
        case let value as UInt64:
            hasher.combine(value)
        case let value as Double:
            hasher.combine(value)
        case let value as String:
            hasher.combine(value)
        default:
            break
        }
    }
}

// MARK: - CustomStringConvertible

extension AnyCodable: CustomStringConvertible {
    public var description: String {
        switch value {
        case is NSNull:
            return "null"
        case let value as Bool:
            return value.description
        case let value as Int:
            return value.description
        case let value as Int64:
            return value.description
        case let value as UInt64:
            return value.description
        case let value as Double:
            return value.description
        case let value as String:
            return "\"\(value)\""
        case let value as [Any]:
            return value.description
        case let value as [String: Any]:
            return value.description
        default:
            return String(describing: value)
        }
    }
}

// MARK: - ExpressibleBy Protocols

extension AnyCodable: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self.value = NSNull()
    }
}

extension AnyCodable: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self.value = value
    }
}

extension AnyCodable: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.value = value
    }
}

extension AnyCodable: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.value = value
    }
}

extension AnyCodable: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.value = value
    }
}

extension AnyCodable: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Any...) {
        self.value = elements.map { AnyCodable.convertToSendable($0) }
    }
}

extension AnyCodable: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Any)...) {
        self.value = Dictionary(elements.map { ($0, AnyCodable.convertToSendable($1)) }) { _, new in new }
    }
}
