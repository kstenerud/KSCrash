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

    /// The run ID of the process that generated this report.
    public let runId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case processName = "process_name"
        case timestamp
        case type
        case version
        case runId = "run_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.processName = try container.decodeIfPresent(String.self, forKey: .processName)
        self.type = try container.decodeIfPresent(ReportType.self, forKey: .type)
        self.version = try container.decodeIfPresent(ReportVersion.self, forKey: .version)
        self.runId = try container.decodeIfPresent(String.self, forKey: .runId)

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
///
/// Handles two formats:
/// - Legacy (v2.x): Dictionary with `major` and `minor` keys
/// - Current (v3.x+): Semantic version string like "3.6.0"
public struct ReportVersion: Decodable, Sendable {
    /// Major version number.
    public let major: Int

    /// Minor version number.
    public let minor: Int

    /// Patch version number.
    public let patch: Int

    /// The string representation of the version.
    public var versionString: String {
        "\(major).\(minor).\(patch)"
    }

    public init(from decoder: Decoder) throws {
        // Try dictionary format first (v2.x format)
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.major = try container.decode(Int.self, forKey: .major)
            self.minor = try container.decode(Int.self, forKey: .minor)
            self.patch = 0
        }
        // Try string format (v3.x+ format)
        else if let versionStr = try? decoder.singleValueContainer().decode(String.self) {
            let components = versionStr.split(separator: ".").compactMap { Int($0) }
            self.major = components.count > 0 ? components[0] : 0
            self.minor = components.count > 1 ? components[1] : 0
            self.patch = components.count > 2 ? components[2] : 0
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected dictionary with major/minor keys or version string"
                )
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case major
        case minor
    }
}
