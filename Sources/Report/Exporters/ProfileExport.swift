//
//  ProfileExport.swift
//
//  Created by Alexander Cohen on 2025-01-06.
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

// MARK: - Profile Export Format

/// Supported profile export formats.
public enum ProfileExportFormat: Sendable {
    /// Speedscope JSON format for visualization at https://speedscope.app
    case speedscope

    /// Collapsed stack format for FlameGraph tools.
    /// See: https://github.com/brendangregg/FlameGraph
    case collapsedStack

    /// Chrome Trace Event format for Chrome DevTools and Perfetto.
    /// See: https://ui.perfetto.dev
    case chromeTrace
}

// MARK: - ProfileInfo Export Extension

extension ProfileInfo {

    /// Exports this profile to the specified format.
    ///
    /// - Parameter format: The target export format.
    /// - Returns: Encoded data in the specified format.
    /// - Throws: An error if encoding fails.
    public func export(to format: ProfileExportFormat) throws -> Data {
        switch format {
        case .speedscope:
            return try exportToSpeedscope()
        case .collapsedStack:
            return exportToCollapsedStack()
        case .chromeTrace:
            return try exportToChromeTrace()
        }
    }
}
