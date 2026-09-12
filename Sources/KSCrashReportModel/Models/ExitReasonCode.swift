//
//  ExitReasonCode.swift
//
//  Created by Alexander Cohen on 2026-06-28.
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

/// A process exit code, as carried by an exit reason. A handful are the recognizable "magic" codes
/// Apple documents (TN2151), exposed as static constants; everything else (a jetsam reason, a signal
/// number, ...) is meaningful only within its `ExitReasonNamespace`, so this is an open struct that
/// preserves the raw value.
public struct ExitReasonCode: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let watchdogTimeout = Self(rawValue: 0x8BAD_F00D)
    public static let resourceHeldWhileSuspended = Self(rawValue: 0xDEAD_10CC)
    public static let telephonyTimeout = Self(rawValue: 0xBAAD_CA11)
    public static let voipResumedTooFrequently = Self(rawValue: 0xBAD2_2222)
    public static let thermalEvent = Self(rawValue: 0xC000_10FF)
    public static let userForceQuit = Self(rawValue: 0xDEAD_FA11)
    public static let privacyViolation = Self(rawValue: 0x2BAD_45EC)
}
