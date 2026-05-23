//
//  AppMemoryInfo.swift
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

/// App memory state classification.
///
/// Mirrors the C `KSCrashAppMemoryState` enum (`KSCrashAppMemory.h`). Values are
/// emitted as lowercase strings in the report JSON and used for both the app's
/// own memory level and system-wide memory pressure.
public enum MemoryState: RawRepresentable, Codable, Sendable, Equatable {
    case normal
    case warn
    case urgent
    case critical
    case terminal
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "normal": self = .normal
        case "warn": self = .warn
        case "urgent": self = .urgent
        case "critical": self = .critical
        case "terminal": self = .terminal
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .normal: return "normal"
        case .warn: return "warn"
        case .urgent: return "urgent"
        case .critical: return "critical"
        case .terminal: return "terminal"
        case .unknown(let value): return value
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

/// App memory information at crash time.
public struct AppMemoryInfo: Codable, Sendable, Equatable {
    /// Memory footprint of the app in bytes.
    public let memoryFootprint: UInt64?

    /// Memory remaining before limit in bytes.
    public let memoryRemaining: UInt64?

    /// System memory pressure level.
    public let memoryPressure: MemoryState?

    /// App memory level.
    public let memoryLevel: MemoryState?

    /// Memory limit for the app in bytes.
    public let memoryLimit: UInt64?

    /// App transition state at crash time.
    public let appTransitionState: AppTransitionState?

    enum CodingKeys: String, CodingKey {
        case memoryFootprint = "memory_footprint"
        case memoryRemaining = "memory_remaining"
        case memoryPressure = "memory_pressure"
        case memoryLevel = "memory_level"
        case memoryLimit = "memory_limit"
        case appTransitionState = "app_transition_state"
    }
}
