//
//  MetricKitMonitor+Helpers.swift
//
//  Created by Alexander Cohen on 2026-01-31.
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
import os.log

let metricKitLog = OSLog(subsystem: "com.kscrash", category: "MetricKit")

// MARK: - OS Version Parsing

struct OSVersionInfo {
    let name: String?
    let version: String?
    let build: String?
}

/// Parses a MetricKit OS version string into its components.
/// Format: "<Name> <Version> (<Build>)" e.g. "iPhone OS 26.2.1 (23C71)"
/// Falls back to using the raw string as systemVersion if parsing fails.
func parseOSVersion(_ raw: String) -> OSVersionInfo {
    let pattern = #"^(.+?)\s+([\d.]+)\s+\((.+)\)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
        match.numberOfRanges == 4,
        let nameRange = Range(match.range(at: 1), in: raw),
        let versionRange = Range(match.range(at: 2), in: raw),
        let buildRange = Range(match.range(at: 3), in: raw)
    else {
        return OSVersionInfo(name: nil, version: raw, build: nil)
    }
    return OSVersionInfo(
        name: String(raw[nameRange]),
        version: String(raw[versionRange]),
        build: String(raw[buildRange])
    )
}

// MARK: - VM Region Parsing

/// Parses the faulting address from a `virtualMemoryRegionInfo` string.
/// The string starts with the address (decimal or hex), e.g.
/// "0 is not in any region. ..." or "0x1234 is not in any region. ..."
func parseVMRegionAddress(from info: String) -> UInt64? {
    let token = String(info.prefix(while: { !$0.isWhitespace }))
    guard !token.isEmpty else { return nil }
    if token.hasPrefix("0x") || token.hasPrefix("0X") {
        return UInt64(token.dropFirst(2), radix: 16)
    }
    return UInt64(token)
}

// MARK: - Termination Reason Parsing

/// Parses a hex or decimal integer from the substring starting at `start`.
/// Reads until the next whitespace, common delimiter, or end of string.
private func parseCodeValue(from str: Substring) -> UInt64? {
    let terminators: Set<Character> = [" ", "\t", "\n", "\r", ">", ",", ";", "|"]
    let raw = String(str.prefix(while: { !terminators.contains($0) }))
    if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
        return UInt64(raw.dropFirst(2), radix: 16)
    }
    return UInt64(raw)
}

/// Parses the exit code from a termination reason string.
///
/// Supports three known formats:
/// 1. Old style: `Namespace SPRINGBOARD, Code 0x8badf00d`
/// 2. Newer with context: `FRONTBOARD 2343432205 <RBSTerminateContext| domain:10 code:0x8BADF00D ...>`
/// 3. Just context: `<RBSTerminateContext| domain:10 code:0x8BADF00D ...>`
///
/// Prefers the `code:` field inside RBSTerminateContext when present,
/// falling back to the old `Code ` prefix format.
func parseExitCode(from terminationReason: String) -> UInt64? {
    // Try RBSTerminateContext code: field first (formats 2 & 3)
    if let contextCodeRange = terminationReason.range(of: "code:", options: .caseInsensitive) {
        let after = terminationReason[contextCodeRange.upperBound...]
        if let result = parseCodeValue(from: after) {
            return result
        }
    }

    // Fall back to old format: "Code <value>" (format 1)
    if let codeRange = terminationReason.range(of: "Code ") {
        let after = terminationReason[codeRange.upperBound...]
        return parseCodeValue(from: after)
    }

    return nil
}
