//
//  ExitReasonInfo.swift
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

/// Exit reason information from the OS.
public struct ExitReasonInfo: Codable, Sendable, Equatable {
    /// Exit reason code. (ex: 0x8badf00d)
    public let code: UInt64

    /// The namespace the code belongs to, when known. A code is only meaningful within its
    /// namespace, so the same number means different things under jetsam and code signing.
    ///
    /// Absent from reports written by the crashing process itself, which records only a code.
    /// A corpse report carries it, because kcdata's exit reason knows it.
    public let namespace: ExitReasonNamespace?

    /// OS reason flags, when known. Same availability as `namespace`.
    public let flags: UInt64?

    public init(code: UInt64, namespace: ExitReasonNamespace? = nil, flags: UInt64? = nil) {
        self.code = code
        self.namespace = namespace
        self.flags = flags
    }
}
