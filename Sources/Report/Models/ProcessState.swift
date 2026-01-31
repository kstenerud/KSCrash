//
//  ProcessState.swift
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

/// Process state information including zombie exception data.
public struct ProcessState: Codable, Sendable {
    /// Information about the last deallocated NSException (for zombie detection).
    public let lastDeallocedNSException: LastDeallocedNSException?

    enum CodingKeys: String, CodingKey {
        case lastDeallocedNSException = "last_dealloced_nsexception"
    }
}

/// Information about a deallocated NSException (zombie).
public struct LastDeallocedNSException: Codable, Sendable {
    /// Memory address of the exception.
    public let address: UInt64?

    /// Exception name.
    public let name: String?

    /// Exception reason.
    public let reason: String?

    /// Object referenced in the exception reason.
    public let referencedObject: ReferencedObject?

    enum CodingKeys: String, CodingKey {
        case address
        case name
        case reason
        case referencedObject = "referenced_object"
    }
}
