//
//  ExceptionInfo.swift
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

/// NSException details (Objective-C/Swift exceptions).
public struct ExceptionInfo: Codable, Sendable {
    /// Exception name (e.g., "NSInvalidArgumentException").
    public let name: String

    /// Exception reason string (note: reason is often at the error level, not here).
    public let reason: String?

    /// User info dictionary from the exception.
    public let userInfo: String?

    /// Referenced object that was involved in the exception.
    public let referencedObject: ReferencedObject?

    public init(
        name: String,
        reason: String? = nil,
        userInfo: String? = nil,
        referencedObject: ReferencedObject? = nil
    ) {
        self.name = name
        self.reason = reason
        self.userInfo = userInfo
        self.referencedObject = referencedObject
    }

    enum CodingKeys: String, CodingKey {
        case name
        case reason
        case userInfo
        case referencedObject = "referenced_object"
    }
}
