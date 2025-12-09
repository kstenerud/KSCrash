//
//  StackDump.swift
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

/// Raw stack memory dump.
public struct StackDump: Decodable, Sendable {
    /// Hexadecimal string of stack contents.
    public let contents: String?

    /// End address of the dump.
    public let dumpEnd: UInt64?

    /// Start address of the dump.
    public let dumpStart: UInt64?

    /// Stack growth direction ("-" for downward, "+" for upward).
    public let growDirection: String?

    /// Whether stack overflow was detected.
    public let overflow: Bool?

    /// Current stack pointer value.
    public let stackPointer: UInt64?

    /// Error message if stack contents couldn't be read.
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case contents
        case dumpEnd = "dump_end"
        case dumpStart = "dump_start"
        case growDirection = "grow_direction"
        case overflow
        case stackPointer = "stack_pointer"
        case error
    }
}
