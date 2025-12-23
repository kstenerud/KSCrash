//
//  StackFrame.swift
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

/// A single frame in a stack trace.
public struct StackFrame: Decodable, Sendable {
    /// Instruction pointer address.
    public let instructionAddr: UInt64

    /// Base address of the containing binary image.
    public let objectAddr: UInt64?

    /// Name of the containing binary image.
    public let objectName: String?

    /// Address of the symbol.
    public let symbolAddr: UInt64?

    /// Name of the symbol (function/method name).
    public let symbolName: String?

    enum CodingKeys: String, CodingKey {
        case instructionAddr = "instruction_addr"
        case objectAddr = "object_addr"
        case objectName = "object_name"
        case symbolAddr = "symbol_addr"
        case symbolName = "symbol_name"
    }
}
