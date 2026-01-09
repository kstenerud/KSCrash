//
//  ProfileExport+CollapsedStack.swift
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

// MARK: - Collapsed Stack Export

extension ProfileInfo {

    /// Converts this profile to collapsed stack format.
    ///
    /// - Returns: A `CollapsedStack` structure ready for export.
    public func toCollapsedStack() -> CollapsedStack {
        // Aggregate identical stacks and count occurrences
        var stackCounts: [String: Int] = [:]

        for sample in samples {
            // Build stack string from root to leaf (reversed from our storage)
            let stackString =
                sample.frames.reversed().map { frames[$0].lossyDisplayName }.joined(separator: ";")

            stackCounts[stackString, default: 0] += 1
        }

        // Convert to sorted lines
        let lines = stackCounts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }

        return CollapsedStack(lines: lines)
    }

    /// Exports this profile to collapsed stack format.
    ///
    /// The collapsed stack format is a simple text format where each line contains
    /// a semicolon-separated stack trace followed by a count. This format is used
    /// by FlameGraph tools and many other visualization tools.
    ///
    /// - Returns: UTF-8 data in collapsed stack format.
    public func exportToCollapsedStack() -> Data {
        toCollapsedStack().toData()
    }
}
