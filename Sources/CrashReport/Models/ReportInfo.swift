//
//  ReportInfo.swift
//
//  Created by Alexander Cohen on 2024-12-09.
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

/// The type of crash report.
public enum ReportType: RawRepresentable, Decodable, Sendable, Equatable {
    case standard
    case minimal
    case custom
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "standard": self = .standard
        case "minimal": self = .minimal
        case "custom": self = .custom
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .standard: return "standard"
        case .minimal: return "minimal"
        case .custom: return "custom"
        case .unknown(let value): return value
        }
    }
}

/// Metadata about the crash report itself.
public struct ReportInfo: Decodable, Sendable {
    /// Unique identifier for this report.
    public let id: String

    /// Name of the process that crashed.
    public let processName: String?

    /// Timestamp when the crash occurred.
    public let timestamp: Date?

    /// Type of report.
    public let type: ReportType?

    /// Report format version.
    public let version: ReportVersion?

    enum CodingKeys: String, CodingKey {
        case id
        case processName = "process_name"
        case timestamp
        case type
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.processName = try container.decodeIfPresent(String.self, forKey: .processName)
        self.type = try container.decodeIfPresent(ReportType.self, forKey: .type)
        self.version = try container.decodeIfPresent(ReportVersion.self, forKey: .version)

        // Timestamp can be ISO 8601 string or microseconds since epoch
        if let microseconds = try? container.decode(Int64.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: Double(microseconds) / 1_000_000)
        } else if let dateString = try? container.decode(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                self.timestamp = date
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                self.timestamp = formatter.date(from: dateString)
            }
        } else {
            self.timestamp = nil
        }
    }
}

/// Report format version information.
public struct ReportVersion: Decodable, Sendable {
    /// Major version number.
    public let major: Int

    /// Minor version number.
    public let minor: Int
}
