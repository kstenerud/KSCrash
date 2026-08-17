//
//  Report.swift
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

/// A wrapper that provides indirection for recursive crash reports.
public final class RecrashReport: Codable, Sendable {
    public let report: Report

    public init(report: Report) {
        self.report = report
    }

    public init(from decoder: Decoder) throws {
        self.report = try Report(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try report.encode(to: encoder)
    }
}

extension RecrashReport: Equatable {
    public static func == (lhs: RecrashReport, rhs: RecrashReport) -> Bool {
        lhs.report == rhs.report
    }
}

/// The root structure representing a complete KSCrash report.
public struct Report: Codable, Sendable, Equatable {
    /// List of binary images loaded in the process at crash time.
    public let binaryImages: [BinaryImage]?

    /// Information about the crash itself.
    public let crash: Crash

    /// Debug information (console logs, etc.).
    public let debug: DebugInfo?

    /// Process-specific information (zombie exceptions, etc.).
    public let process: ProcessState?

    /// Metadata about this report.
    public let report: ReportInfo

    /// If a crash occurred while writing the crash report, the original report is embedded here.
    public let recrashReport: RecrashReport?

    /// System information at the time of crash.
    public let system: SystemInfo?

    /// App data attached via the userInfo API.
    public let metadata: Metadata?

    /// Data contributed by custom monitors at delivery time, keyed by monitor
    /// id. nil when no monitor contributed any. Use ``monitorData(_:for:)``
    /// to read a section as its concrete type.
    public let monitorData: [String: Metadata]?

    /// Whether this report is incomplete (crash during crash handling).
    public let incomplete: Bool?

    public init(
        binaryImages: [BinaryImage]? = nil,
        crash: Crash,
        debug: DebugInfo? = nil,
        process: ProcessState? = nil,
        report: ReportInfo,
        recrashReport: RecrashReport? = nil,
        system: SystemInfo? = nil,
        metadata: Metadata? = nil,
        monitorData: [String: Metadata]? = nil,
        incomplete: Bool? = nil
    ) {
        self.binaryImages = binaryImages
        self.crash = crash
        self.debug = debug
        self.process = process
        self.report = report
        self.recrashReport = recrashReport
        self.system = system
        self.metadata = metadata
        self.monitorData = monitorData
        self.incomplete = incomplete
    }

    /// The named monitor's section decoded as `type`. nil when the report
    /// carries no section for that monitor; throws when the section exists
    /// but does not decode as `type`.
    public func monitorData<Value: Decodable>(
        _ type: Value.Type = Value.self, for monitorID: String
    ) throws -> Value? {
        guard let section = monitorData?[monitorID] else {
            return nil
        }
        return try section.decoded(as: Value.self)
    }

    enum CodingKeys: String, CodingKey {
        case binaryImages = "binary_images"
        case crash
        case debug
        case process
        case report
        case recrashReport = "recrash_report"
        case system
        case metadata = "user"
        case monitorData = "monitor_data"
        case incomplete
    }
}
