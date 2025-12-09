//
//  HangInfo.swift
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

/// Information about a hang detected by the watchdog monitor.
public struct HangInfo: Decodable, Sendable {
    /// Timestamp when the hang started (in nanoseconds).
    public let hangStartNanos: UInt64

    /// The app's role when the hang started (e.g., "FOREGROUND_APPLICATION").
    public let hangStartRole: String

    /// Timestamp when the hang ended/was detected (in nanoseconds).
    public let hangEndNanos: UInt64

    /// The app's role when the hang ended.
    public let hangEndRole: String

    enum CodingKeys: String, CodingKey {
        case hangStartNanos = "hang_start_nanos"
        case hangStartRole = "hang_start_role"
        case hangEndNanos = "hang_end_nanos"
        case hangEndRole = "hang_end_role"
    }
}
