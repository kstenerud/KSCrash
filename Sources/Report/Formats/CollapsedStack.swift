//
//  CollapsedStack.swift
//
//  Created by Alexander Cohen on 2026-01-08.
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

/// Collapsed stack format for flame graph generation.
///
/// This is the format used by Brendan Gregg's FlameGraph tools and many other
/// visualization tools (Inferno, speedscope collapsed import, etc.).
///
/// Each line represents a stack trace with a count:
/// ```
/// main;doWork;sleep 42
/// main;doWork;compute 15
/// main;idle 3
/// ```
///
/// The stack is semicolon-separated from root to leaf, followed by a space
/// and the sample count. Identical stacks are aggregated with their counts summed.
///
/// See: https://github.com/brendangregg/FlameGraph
public struct CollapsedStack: Sendable {
    /// Lines in the collapsed stack format, each representing a unique stack with its count.
    public let lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }

    /// Converts the collapsed stack to a single string.
    public func toString() -> String {
        lines.joined(separator: "\n")
    }

    /// Converts the collapsed stack to UTF-8 data.
    public func toData() -> Data {
        Data(toString().utf8)
    }
}
