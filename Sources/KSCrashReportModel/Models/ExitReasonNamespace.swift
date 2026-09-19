//
//  ExitReasonNamespace.swift
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

/// The `os_reason` namespace of an exit reason, named after its `OS_REASON_*` symbol
/// (`<sys/reason.h>`). Apple adds namespaces almost every OS release, so this is an open struct
/// holding the raw value; the known namespaces are static constants.
// swift-format-ignore: AlwaysUseLowerCamelCase
public struct ExitReasonNamespace: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let OS_REASON_INVALID = Self(rawValue: 0)
    public static let OS_REASON_JETSAM = Self(rawValue: 1)
    public static let OS_REASON_SIGNAL = Self(rawValue: 2)
    public static let OS_REASON_CODESIGNING = Self(rawValue: 3)
    public static let OS_REASON_HANGTRACER = Self(rawValue: 4)
    public static let OS_REASON_TEST = Self(rawValue: 5)
    public static let OS_REASON_DYLD = Self(rawValue: 6)
    public static let OS_REASON_LIBXPC = Self(rawValue: 7)
    public static let OS_REASON_OBJC = Self(rawValue: 8)
    public static let OS_REASON_EXEC = Self(rawValue: 9)
    public static let OS_REASON_SPRINGBOARD = Self(rawValue: 10)
    public static let OS_REASON_TCC = Self(rawValue: 11)
    public static let OS_REASON_REPORTCRASH = Self(rawValue: 12)
    public static let OS_REASON_COREANIMATION = Self(rawValue: 13)
    public static let OS_REASON_AGGREGATED = Self(rawValue: 14)
    public static let OS_REASON_RUNNINGBOARD = Self(rawValue: 15)
    public static let OS_REASON_SKYWALK = Self(rawValue: 16)
    public static let OS_REASON_SETTINGS = Self(rawValue: 17)
    public static let OS_REASON_LIBSYSTEM = Self(rawValue: 18)
    public static let OS_REASON_FOUNDATION = Self(rawValue: 19)
    public static let OS_REASON_WATCHDOG = Self(rawValue: 20)
    public static let OS_REASON_METAL = Self(rawValue: 21)
    public static let OS_REASON_WATCHKIT = Self(rawValue: 22)
    public static let OS_REASON_GUARD = Self(rawValue: 23)
    public static let OS_REASON_ANALYTICS = Self(rawValue: 24)
    public static let OS_REASON_SANDBOX = Self(rawValue: 25)
    public static let OS_REASON_SECURITY = Self(rawValue: 26)
    public static let OS_REASON_ENDPOINTSECURITY = Self(rawValue: 27)
    public static let OS_REASON_PAC_EXCEPTION = Self(rawValue: 28)
    public static let OS_REASON_BLUETOOTH_CHIP = Self(rawValue: 29)
    public static let OS_REASON_PORT_SPACE = Self(rawValue: 30)
    public static let OS_REASON_WEBKIT = Self(rawValue: 31)
    public static let OS_REASON_BACKLIGHTSERVICES = Self(rawValue: 32)
    public static let OS_REASON_MEDIA = Self(rawValue: 33)
    public static let OS_REASON_ROSETTA = Self(rawValue: 34)
    public static let OS_REASON_LIBIGNITION = Self(rawValue: 35)
    public static let OS_REASON_BOOTMOUNT = Self(rawValue: 36)
    public static let OS_REASON_REALITYKIT = Self(rawValue: 38)
    public static let OS_REASON_AUDIO = Self(rawValue: 39)
    public static let OS_REASON_WAKEBOARD = Self(rawValue: 40)
    public static let OS_REASON_CORERC = Self(rawValue: 41)
    public static let OS_REASON_SELF_RESTRICT = Self(rawValue: 42)
    public static let OS_REASON_ARKIT = Self(rawValue: 43)
    public static let OS_REASON_CAMERA = Self(rawValue: 44)
    public static let OS_REASON_BACKBOARD = Self(rawValue: 45)
    public static let OS_REASON_POWEREXCEPTIONS = Self(rawValue: 46)
    public static let OS_REASON_SECINIT = Self(rawValue: 47)
}
