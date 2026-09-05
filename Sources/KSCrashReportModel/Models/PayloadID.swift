//
//  PayloadID.swift
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

/// A payload's identity: a UUID in its canonical lowercase text form.
///
/// `Owner` is phantom typing: ids of different payload kinds are different
/// types, so one cannot stand in for another.
public struct PayloadID<Owner>: Hashable, Codable, Sendable, LosslessStringConvertible, ExpressibleByStringLiteral {
    public let uuid: UUID

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    /// nil unless `string` is a UUID; any case is accepted.
    public init?(_ string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        self.uuid = uuid
    }

    /// Lowercase, the canonical text form of every payload id.
    public var description: String { uuid.uuidString.lowercased() }

    /// A literal that is not a UUID is a programming error.
    public init(stringLiteral value: String) {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("id literal is not a UUID: \(value)")
        }
        self.uuid = uuid
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "id is not a UUID: \(raw)"))
        }
        self.uuid = uuid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension Report: Identifiable {
    /// The report's identity: the UUID minted when the report was recorded.
    public typealias ID = PayloadID<Report>

    public var id: ID { report.id }
}

extension RunSummary: Identifiable {
    /// The run's identity: the UUID minted at launch.
    public typealias ID = PayloadID<RunSummary>
}
