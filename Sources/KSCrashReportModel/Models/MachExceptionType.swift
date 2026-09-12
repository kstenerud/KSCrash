//
//  MachExceptionType.swift
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

/// A Mach exception type, named after its `EXC_*` symbol (`<mach/exception_types.h>`). The kernel
/// has grown this set across OS releases (EXC_GUARD and EXC_CORPSE_NOTIFY were both additions), so
/// this is an open struct holding the raw value; the known types are static constants. An unknown
/// value still classifies, encodes, and decodes.
// swift-format-ignore: AlwaysUseLowerCamelCase
public struct MachExceptionType: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }

    public static let EXC_BAD_ACCESS = Self(rawValue: 1)
    public static let EXC_BAD_INSTRUCTION = Self(rawValue: 2)
    public static let EXC_ARITHMETIC = Self(rawValue: 3)
    public static let EXC_EMULATION = Self(rawValue: 4)
    public static let EXC_SOFTWARE = Self(rawValue: 5)
    public static let EXC_BREAKPOINT = Self(rawValue: 6)
    public static let EXC_SYSCALL = Self(rawValue: 7)
    public static let EXC_MACH_SYSCALL = Self(rawValue: 8)
    public static let EXC_RPC_ALERT = Self(rawValue: 9)
    public static let EXC_CRASH = Self(rawValue: 10)
    public static let EXC_RESOURCE = Self(rawValue: 11)
    public static let EXC_GUARD = Self(rawValue: 12)
    public static let EXC_CORPSE_NOTIFY = Self(rawValue: 13)
}
