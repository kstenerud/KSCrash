//
//  MemoryContents.swift
//
//  Created by Alexander Cohen on 2026-08-19.
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

/// What the memory at an inspected address held.
public enum MemoryType: RawRepresentable, Codable, Sendable, Equatable {
    case objcClass
    case objcObject
    case objcBlock
    case nullPointer
    case string
    /// The writer could not identify the contents.
    case unknown
    /// A type this model does not know.
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "objc_class": self = .objcClass
        case "objc_object": self = .objcObject
        case "objc_block": self = .objcBlock
        case "null_pointer": self = .nullPointer
        case "string": self = .string
        case "unknown": self = .unknown
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .objcClass: return "objc_class"
        case .objcObject: return "objc_object"
        case .objcBlock: return "objc_block"
        case .nullPointer: return "null_pointer"
        case .string: return "string"
        case .unknown: return "unknown"
        case .other(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The contents of an inspected memory address: a thread's notable addresses
/// and the object an exception reason refers to.
public struct MemoryContents: Codable, Sendable, Equatable {
    /// The inspected address.
    public let address: UInt64

    /// What the memory held.
    public let type: MemoryType

    /// Objective-C class name, for class, object, and block contents.
    public let `class`: String?

    /// The value, when the contents have a printable one: a string for strings
    /// and URLs, a number for dates and numbers.
    public let value: MetadataValue?

    /// The first element, when the contents are a collection.
    public var firstObject: MemoryContents? { firstObjectStorage.first }

    /// Instance variables by name, when the contents are an object of a class
    /// the writer does not special-case. Pointer-typed variables nest another
    /// memory-contents object.
    public let ivars: [String: MetadataValue]?

    /// Class name of the object that was last deallocated at this address, when
    /// zombie tracking knows one.
    public let lastDeallocatedObject: String?

    private let firstObjectStorage: [MemoryContents]

    public init(
        address: UInt64,
        type: MemoryType,
        class: String? = nil,
        value: MetadataValue? = nil,
        firstObject: MemoryContents? = nil,
        ivars: [String: MetadataValue]? = nil,
        lastDeallocatedObject: String? = nil
    ) {
        self.address = address
        self.type = type
        self.class = `class`
        self.value = value
        self.firstObjectStorage = firstObject.map { [$0] } ?? []
        self.ivars = ivars
        self.lastDeallocatedObject = lastDeallocatedObject
    }

    enum CodingKeys: String, CodingKey {
        case address
        case type
        case `class`
        case value
        case firstObject = "first_object"
        case ivars
        case lastDeallocatedObject = "last_deallocated_obj"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(UInt64.self, forKey: .address)
        type = try c.decode(MemoryType.self, forKey: .type)
        `class` = try c.decodeIfPresent(String.self, forKey: .class)
        value = try c.decodeIfPresent(MetadataValue.self, forKey: .value)
        firstObjectStorage = try c.decodeIfPresent(MemoryContents.self, forKey: .firstObject).map { [$0] } ?? []
        ivars = try c.decodeIfPresent([String: MetadataValue].self, forKey: .ivars)
        lastDeallocatedObject = try c.decodeIfPresent(String.self, forKey: .lastDeallocatedObject)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(address, forKey: .address)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(`class`, forKey: .class)
        try c.encodeIfPresent(value, forKey: .value)
        try c.encodeIfPresent(firstObject, forKey: .firstObject)
        try c.encodeIfPresent(ivars, forKey: .ivars)
        try c.encodeIfPresent(lastDeallocatedObject, forKey: .lastDeallocatedObject)
    }
}
