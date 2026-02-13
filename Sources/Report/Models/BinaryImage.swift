//
//  BinaryImage.swift
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

/// Information about a loaded binary image (executable, framework, or dylib).
public struct BinaryImage: Codable, Sendable {
    /// CPU subtype of the binary.
    public let cpuSubtype: Int

    /// CPU type of the binary.
    public let cpuType: Int

    /// Load address of the image in memory.
    public let imageAddr: UInt64

    /// Virtual memory address of the image.
    public let imageVmAddr: UInt64?

    /// Size of the image in bytes.
    public let imageSize: UInt64

    /// Path to the binary image.
    public let name: String

    /// UUID of the binary image for symbolication.
    public let uuid: String?

    /// Major version of the image.
    public let majorVersion: UInt64?

    /// Minor version of the image.
    public let minorVersion: UInt64?

    /// Revision version of the image.
    public let revisionVersion: UInt64?

    /// Crash info message from __crash_info section.
    public let crashInfoMessage: String?

    /// Secondary crash info message.
    public let crashInfoMessage2: String?

    /// Crash info backtrace.
    public let crashInfoBacktrace: String?

    /// Crash info signature.
    public let crashInfoSignature: String?

    public init(
        cpuSubtype: Int = 0,
        cpuType: Int = 0,
        imageAddr: UInt64,
        imageVmAddr: UInt64? = nil,
        imageSize: UInt64 = 0,
        name: String,
        uuid: String? = nil,
        majorVersion: UInt64? = nil,
        minorVersion: UInt64? = nil,
        revisionVersion: UInt64? = nil,
        crashInfoMessage: String? = nil,
        crashInfoMessage2: String? = nil,
        crashInfoBacktrace: String? = nil,
        crashInfoSignature: String? = nil
    ) {
        self.cpuSubtype = cpuSubtype
        self.cpuType = cpuType
        self.imageAddr = imageAddr
        self.imageVmAddr = imageVmAddr
        self.imageSize = imageSize
        self.name = name
        self.uuid = uuid
        self.majorVersion = majorVersion
        self.minorVersion = minorVersion
        self.revisionVersion = revisionVersion
        self.crashInfoMessage = crashInfoMessage
        self.crashInfoMessage2 = crashInfoMessage2
        self.crashInfoBacktrace = crashInfoBacktrace
        self.crashInfoSignature = crashInfoSignature
    }

    enum CodingKeys: String, CodingKey {
        case cpuSubtype = "cpu_subtype"
        case cpuType = "cpu_type"
        case imageAddr = "image_addr"
        case imageVmAddr = "image_vmaddr"
        case imageSize = "image_size"
        case name
        case uuid
        case majorVersion = "major_version"
        case minorVersion = "minor_version"
        case revisionVersion = "revision_version"
        case crashInfoMessage = "crash_info_message"
        case crashInfoMessage2 = "crash_info_message2"
        case crashInfoBacktrace = "crash_info_backtrace"
        case crashInfoSignature = "crash_info_signature"
    }
}
