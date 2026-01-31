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
    case memoryTermination
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
        case "memory_termination": self = .memoryTermination
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
        case .memoryTermination: return "memory_termination"
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

/// The error that caused the crash.
public struct CrashError: Codable, Sendable {
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

    /// C++ exception information.
    public let cppException: CppExceptionInfo?

    /// User-reported crash information.
    public let userReported: UserReportedInfo?

    /// Memory termination information (OOM kills).
    public let memoryTermination: MemoryTerminationInfo?

    /// Hang information (watchdog timeouts).
    public let hang: HangInfo?

    /// Exit reason information from the OS.
    public let exitReason: ExitReasonInfo?

    /// Reason for the crash (often from abort message or exception reason).
    public let reason: String?

    /// Profile information (for profiling reports).
    public let profile: ProfileInfo?

    public init(
        address: UInt64? = nil,
        mach: MachError? = nil,
        nsexception: ExceptionInfo? = nil,
        signal: SignalError? = nil,
        type: CrashErrorType,
        cppException: CppExceptionInfo? = nil,
        userReported: UserReportedInfo? = nil,
        memoryTermination: MemoryTerminationInfo? = nil,
        hang: HangInfo? = nil,
        exitReason: ExitReasonInfo? = nil,
        reason: String? = nil,
        profile: ProfileInfo? = nil
    ) {
        self.address = address
        self.mach = mach
        self.nsexception = nsexception
        self.signal = signal
        self.type = type
        self.cppException = cppException
        self.userReported = userReported
        self.memoryTermination = memoryTermination
        self.hang = hang
        self.exitReason = exitReason
        self.reason = reason
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case address
        case mach
        case nsexception
        case signal
        case type
        case cppException = "cpp_exception"
        case userReported = "user_reported"
        case memoryTermination = "memory_termination"
        case hang
        case exitReason = "exit_reason"
        case reason
        case profile
    }
}
