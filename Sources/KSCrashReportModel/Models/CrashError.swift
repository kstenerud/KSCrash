//
//  CrashError.swift
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

/// The type of error that caused the crash.
public enum CrashErrorType: RawRepresentable, Codable, Sendable, Equatable {
    case mach
    case signal
    case nsexception
    case cppException
    case deadlock
    case user
    case termination
    case hang
    case profile
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "mach": self = .mach
        case "signal": self = .signal
        case "nsexception": self = .nsexception
        case "cpp_exception": self = .cppException
        case "deadlock": self = .deadlock
        case "user": self = .user
        case "termination", "memory_termination", "resource_termination": self = .termination
        case "hang": self = .hang
        case "profile": self = .profile
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .mach: return "mach"
        case .signal: return "signal"
        case .nsexception: return "nsexception"
        case .cppException: return "cpp_exception"
        case .deadlock: return "deadlock"
        case .user: return "user"
        case .termination: return "termination"
        case .hang: return "hang"
        case .profile: return "profile"
        case .unknown(let value): return value
        }
    }

    /// Whether this error type is unknown.
    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

/// A subtype that refines ``CrashErrorType``.
///
/// Generic across error types: any report can carry a subtype to distinguish a variant of
/// its primary `type` without inventing a new top-level type. For example a profile report
/// (`type == .profile`) sourced from a hang carries `subtype == .hang`, so consumers can
/// identify hangs reliably instead of matching on a profile name.
public enum CrashErrorSubtype: RawRepresentable, Codable, Sendable, Equatable {
    /// The report describes a hang (e.g. a MetricKit hang diagnostic or a watchdog hang
    /// captured as a profile).
    case hang
    /// The report describes a memory termination captured from a MetricKit memory exception
    /// diagnostic (iOS 27+). Carried on a `.termination` report so consumers can tell a
    /// memory kill apart from other terminations, while still treating it as an OOM.
    case memoryException
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "hang": self = .hang
        case "memory_exception": self = .memoryException
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .hang: return "hang"
        case .memoryException: return "memory_exception"
        case .unknown(let value): return value
        }
    }

    /// Whether this subtype is unknown.
    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

/// The error that caused the crash.
public struct CrashError: Codable, Sendable, Equatable {
    /// Memory address involved in the crash (if applicable).
    public let address: UInt64?

    /// Mach exception information.
    public let mach: MachError?

    /// NSException information (for Objective-C/Swift exceptions).
    public let nsexception: ExceptionInfo?

    /// Unix signal information.
    public let signal: SignalError?

    /// The type of error that caused the crash.
    public let type: CrashErrorType

    /// An optional subtype refining ``type`` (e.g. `.hang` for a hang-sourced profile report).
    public let subtype: CrashErrorSubtype?

    /// C++ exception information.
    public let cppException: CppExceptionInfo?

    /// User-reported crash information.
    public let userReported: UserReportedInfo?

    /// Hang information (watchdog timeouts).
    public let hang: HangInfo?

    /// Exit reason information from the OS.
    public let exitReason: ExitReasonInfo?

    /// Reason for the crash (often from abort message or exception reason).
    public let reason: String?

    /// Profile information (for profiling reports).
    public let profile: ProfileInfo?

    /// Whether this error was fatal to the process.
    public let isFatal: Bool?

    /// Whether the exit was expected and not a crash (e.g., SIGTERM).
    /// Only meaningful when `isFatal` is true.
    public let isCleanExit: Bool?

    /// Termination reason for resource termination reports.
    public let terminationReason: TerminationReason?

    /// Memory state at the time of a memory termination.
    public var memoryTermination: Metadata? { memoryTerminationSection?.metadata }

    private let memoryTerminationSection: FaithfulMetadata?

    /// Data added by custom monitors, keyed by monitor id. The monitor that
    /// caused the event writes its section here under the id carried in
    /// ``type``. nil when the error carries no custom-monitor data. Use
    /// ``monitorData(_:for:)`` to read a section as its concrete type.
    public var monitorData: [String: Metadata]? { monitorSections?.mapValues(\.metadata) }

    private let monitorSections: [String: FaithfulMetadata]?

    /// The named monitor's section decoded as `type`. nil when the error
    /// carries no section for that monitor; throws when the section exists
    /// but does not decode as `type`.
    public func monitorData<Value: Decodable>(
        _ type: Value.Type = Value.self, for monitorID: String
    ) throws -> Value? {
        try monitorData.decodedSection(Value.self, for: monitorID)
    }

    public init(
        address: UInt64? = nil,
        mach: MachError? = nil,
        nsexception: ExceptionInfo? = nil,
        signal: SignalError? = nil,
        type: CrashErrorType,
        subtype: CrashErrorSubtype? = nil,
        cppException: CppExceptionInfo? = nil,
        userReported: UserReportedInfo? = nil,
        hang: HangInfo? = nil,
        exitReason: ExitReasonInfo? = nil,
        reason: String? = nil,
        profile: ProfileInfo? = nil,
        isFatal: Bool? = nil,
        isCleanExit: Bool? = nil,
        terminationReason: TerminationReason? = nil,
        memoryTermination: Metadata? = nil,
        monitorData: [String: Metadata]? = nil
    ) {
        self.address = address
        self.mach = mach
        self.nsexception = nsexception
        self.signal = signal
        self.type = type
        self.subtype = subtype
        self.cppException = cppException
        self.userReported = userReported
        self.hang = hang
        self.exitReason = exitReason
        self.reason = reason
        self.profile = profile
        self.isFatal = isFatal
        self.isCleanExit = isCleanExit
        self.terminationReason = terminationReason
        self.memoryTerminationSection = memoryTermination.map(FaithfulMetadata.init)
        self.monitorSections = monitorData?.mapValues(FaithfulMetadata.init)
    }

    enum CodingKeys: String, CodingKey {
        case address
        case mach
        case nsexception
        case signal
        case type
        case subtype
        case cppException = "cpp_exception"
        case userReported = "user_reported"
        case hang
        case exitReason = "exit_reason"
        case reason
        case profile
        case isFatal = "is_fatal"
        case isCleanExit = "is_clean_exit"
        case terminationReason = "termination_reason"
        case memoryTerminationSection = "memory_termination"
        case monitorSections = "monitor_data"
    }

}
