//
//  CrashReport.swift
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

/// A type that decodes and discards user data.
///
/// Use this as the generic parameter for `CrashReport` when you don't need
/// to access the user-defined custom data.
public struct NoUserData: Decodable, Sendable, Equatable {}

/// A wrapper that provides indirection for recursive crash reports.
public final class RecrashReport<UserData: Decodable & Sendable>: Decodable, Sendable {
    public let report: CrashReport<UserData>

    public init(from decoder: Decoder) throws {
        self.report = try CrashReport<UserData>(from: decoder)
    }
}

/// The root structure representing a complete KSCrash report.
///
/// The generic parameter `UserData` represents the type of user-defined custom data
/// attached to the crash report. Use your own `Decodable` type for type-safe access,
/// or use `NoUserData` to skip decoding user data entirely:
///
/// ```swift
/// // With custom user data type
/// struct MyUserData: Decodable, Sendable {
///     let userId: String
///     let sessionId: String
/// }
/// let report = try JSONDecoder().decode(CrashReport<MyUserData>.self, from: data)
///
/// // Ignoring user data
/// let report = try JSONDecoder().decode(CrashReport<NoUserData>.self, from: data)
/// ```
public struct CrashReport<UserData: Decodable & Sendable>: Decodable, Sendable {
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
    public let recrashReport: RecrashReport<UserData>?

    /// System information at the time of crash.
    public let system: SystemInfo?

    /// User-defined custom data attached to the crash report.
    public let user: UserData?

    /// Whether this report is incomplete (crash during crash handling).
    public let incomplete: Bool?

    enum CodingKeys: String, CodingKey {
        case binaryImages = "binary_images"
        case crash
        case debug
        case process
        case report
        case recrashReport = "recrash_report"
        case system
        case user
        case incomplete
    }
}
