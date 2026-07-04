//
//  ResourceType.swift
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

/// The resource an `EXC_RESOURCE` exception was raised for, named after its `RESOURCE_TYPE_*` symbol
/// (`<kern/exc_resource.h>`). The kernel can add types, so this is an open struct holding the raw
/// value; the known types are static constants.
// swift-format-ignore: AlwaysUseLowerCamelCase
public struct ResourceType: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let RESOURCE_TYPE_CPU = Self(rawValue: 1)
    public static let RESOURCE_TYPE_WAKEUPS = Self(rawValue: 2)
    public static let RESOURCE_TYPE_MEMORY = Self(rawValue: 3)
    public static let RESOURCE_TYPE_IO = Self(rawValue: 4)
    public static let RESOURCE_TYPE_THREADS = Self(rawValue: 5)
    public static let RESOURCE_TYPE_PORTS = Self(rawValue: 6)
}

/// The flavor of an `EXC_RESOURCE` exception, named after its `FLAVOR_*` symbol and interpreted within
/// its `ResourceType` (`<kern/exc_resource.h>`). A flavor number repeats across resource types, so the
/// raw value packs the pair as `type * 10 + flavor`. Open struct; known flavors are static constants.
// swift-format-ignore: AlwaysUseLowerCamelCase
public struct ResourceFlavor: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Build from a raw (resource type, flavor) pair.
    public init(type: UInt32, flavor: UInt32) { self.init(rawValue: type * 10 + flavor) }

    public static let FLAVOR_CPU_MONITOR = Self(rawValue: 11)
    public static let FLAVOR_CPU_MONITOR_FATAL = Self(rawValue: 12)
    public static let FLAVOR_WAKEUPS_MONITOR = Self(rawValue: 21)
    public static let FLAVOR_HIGH_WATERMARK = Self(rawValue: 31)
    public static let FLAVOR_THREADS_HIGH_WATERMARK = Self(rawValue: 51)
    public static let FLAVOR_PORT_SPACE_FULL = Self(rawValue: 61)
}
