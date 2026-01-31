//
//  MachError.swift
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

/// Mach exception details.
public struct MachError: Codable, Sendable {
    /// Mach exception code.
    public let code: UInt64

    /// Human-readable name for the code.
    public let codeName: String?

    /// Mach exception type.
    public let exception: UInt64

    /// Human-readable name for the exception.
    public let exceptionName: String?

    /// Mach exception subcode.
    public let subcode: UInt64?

    public init(
        code: UInt64,
        codeName: String? = nil,
        exception: UInt64,
        exceptionName: String? = nil,
        subcode: UInt64? = nil
    ) {
        self.code = code
        self.codeName = codeName
        self.exception = exception
        self.exceptionName = exceptionName
        self.subcode = subcode
    }

    enum CodingKeys: String, CodingKey {
        case code
        case codeName = "code_name"
        case exception
        case exceptionName = "exception_name"
        case subcode
    }
}
