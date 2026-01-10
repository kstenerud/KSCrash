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

// MARK: - Display

extension StackFrame {
    /// Display name for this frame, using symbol name if available or hex address as fallback.
    public var displayName: String {
        symbolName ?? String(format: "0x%llx", instructionAddr)
    }

    /// Lossy display name with verbose prefixes, parameters, and return types removed.
    ///
    /// Transforms verbose demangled names like:
    /// `MyModule.MyClass.method<T>(arg: Type) -> Result`
    /// into concise names like:
    /// `MyModule.MyClass.method<T>()`
    public var lossyDisplayName: String {
        guard let name = symbolName else {
            return String(format: "0x%llx", instructionAddr)
        }
        return Self.simplify(name)
    }

    /// Simplifies a demangled symbol name by extracting the core symbol.
    ///
    /// Removes verbose prefixes like "merged type metadata accessor for" while
    /// preserving the actual symbol name including generic parameters.
    internal static func simplify(_ name: String) -> String {
        var result = name

        // Patterns that prefix a symbol name - extract what comes after
        let prefixPatterns = [
            "merged type metadata accessor for ",
            "type metadata accessor for ",
            "lazy protocol witness table accessor for type ",
            "protocol witness table accessor for ",
            "associated type descriptor for ",
            "base conformance descriptor for ",
            "protocol conformance descriptor for ",
            "nominal type descriptor for ",
            "reflection metadata field descriptor ",
            "value witness table for ",
            "full type metadata for ",
            "type metadata for ",
            "direct field offset for ",
            "property descriptor for ",
            "method descriptor for ",
            "getter for ",
            "setter for ",
            "modify accessor for ",
            "outlined init with copy of ",
            "outlined destroy of ",
            "outlined copy of ",
            "outlined consume of ",
            "outlined retain of ",
            "outlined release of ",
            "assignWithTake value witness for ",
            "assignWithCopy value witness for ",
            "initializeWithCopy value witness for ",
            "initializeWithTake value witness for ",
            "destroy value witness for ",
        ]

        for prefix in prefixPatterns {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }

        // Handle "X for Y and conformance Z" - extract Y
        if let forRange = result.range(of: " and conformance ") {
            result = String(result[..<forRange.lowerBound])
        }

        // Handle "partial apply forwarder for closure #N ... in X" - simplify to "closure in X"
        if result.hasPrefix("partial apply forwarder for ") {
            result = String(result.dropFirst("partial apply forwarder for ".count))
        }
        if result.hasPrefix("reabstraction thunk helper for ") {
            result = String(result.dropFirst("reabstraction thunk helper for ".count))
        }

        // Handle "function signature specialization <...> of X" - extract X
        if result.hasPrefix("function signature specialization ") {
            if let ofRange = result.range(of: " of ", options: .backwards) {
                result = String(result[ofRange.upperBound...])
            }
        }

        // Handle "generic specialization <...> of X" - extract X
        if result.hasPrefix("generic specialization ") {
            if let ofRange = result.range(of: " of ", options: .backwards) {
                result = String(result[ofRange.upperBound...])
            }
        }

        // Remove all parenthesized content and return types
        result = removeParenthesesAndReturnTypes(from: result)

        result = result.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? name : result
    }

    /// Removes parenthesized content and return types from a symbol name.
    ///
    /// For function parameters (parens followed by end, ` -> `, or ` where `), keeps `()`.
    /// For other parens (like in `closure #1 (A1) -> Type`), removes entirely.
    ///
    /// Examples:
    /// - `Foo.bar(arg: Type) -> Result` becomes `Foo.bar()`
    /// - `closure #1 (A1) -> Type in X` becomes `closure #1 in X`
    private static func removeParenthesesAndReturnTypes(from string: String) -> String {
        var result = ""
        var i = string.startIndex

        while i < string.endIndex {
            let char = string[i]

            if char == "(" {
                // Find matching close paren
                if let closeIdx = findMatchingClose(in: string, from: i) {
                    let afterClose = string.index(after: closeIdx)
                    let remaining = afterClose < string.endIndex ? string[afterClose...] : ""

                    // Check if this looks like function parameters:
                    // - at end of string
                    // - followed by " -> "
                    // - followed by " where "
                    let isFunctionParams =
                        remaining.isEmpty || remaining.hasPrefix(" -> ") || remaining.hasPrefix(" where ")

                    if isFunctionParams {
                        // Keep () but skip contents
                        result.append("()")
                    }
                    // Otherwise, skip the parens entirely

                    i = afterClose
                    continue
                }
            }

            // Check for " -> " return type - skip to end or next context marker
            if char == " " {
                let remaining = string[i...]
                if remaining.hasPrefix(" -> ") {
                    // Find where return type ends
                    let afterArrow = string.index(i, offsetBy: 4)
                    let returnPart = string[afterArrow...]

                    if let inRange = returnPart.range(of: " in ") {
                        // Skip to " in "
                        i = inRange.lowerBound
                        continue
                    } else if let whereRange = returnPart.range(of: " where ") {
                        i = whereRange.lowerBound
                        continue
                    } else {
                        // Return type goes to end - we're done
                        break
                    }
                }
            }

            result.append(char)
            i = string.index(after: i)
        }

        return result
    }

    /// Finds the matching close paren for an open paren.
    private static func findMatchingClose(in string: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var current = start
        while current < string.endIndex {
            let char = string[current]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    return current
                }
            }
            current = string.index(after: current)
        }
        return nil
    }
}
