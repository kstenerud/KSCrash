//
//  CorpseLanguageException.swift
//
//  Created by Alexander Cohen on 2026-09-27.
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
import KSCrashRecordingCore
import ObjectiveC

/// The uncaught language exception a corpse died of, read back from the messages the runtime
/// libraries leave in their `__crash_info` sections on the way down.
///
/// Nothing in the corpse carries the exception itself: the in-process monitors that would have
/// caught it never ran. What survives is text, so this matches the exact wording observed on
/// iOS 27 and nothing looser. Wording it does not recognize yields nil and the report keeps
/// the Mach classification it already has.
///
/// Every match is on exact scalars, never on grapheme clusters. A name, reason or `what()` is
/// the app's own text, and one that starts with a combining mark would otherwise fuse with the
/// quote or space before it, hiding the separator.
enum CorpseLanguageException: Equatable {
    /// CoreFoundation's uncaught-exception handler wrote its message. It does so before any
    /// handler the app installed runs, so an app whose own handler aborts still leaves it.
    case objC(name: String, reason: String?, throwAddresses: [UInt64])
    /// libc++abi's terminate handler wrote its message. A bare `std::terminate()` has no
    /// exception to name. An Objective-C object that is not an NSException lands here too,
    /// which is where the in-process C++ monitor files it.
    case cpp(name: String?, reason: String?)

    /// Reads the exception from a report's `binary_images`. CoreFoundation's message is checked
    /// first: libc++abi also writes one for an NSException, naming a subclass by its own class,
    /// so its message alone cannot tell an NSException subclass from a C++ type.
    static func read(fromBinaryImages images: [[String: Any]]) -> CorpseLanguageException? {
        func message(ofImageEndingWith suffix: String) -> String? {
            images.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }?["crash_info_message"] as? String
        }
        if let message = message(ofImageEndingWith: "/CoreFoundation"), let exception = parseCoreFoundation(message) {
            return exception
        }
        guard let message = message(ofImageEndingWith: "/libc++abi.dylib"),
            let exception = parseCxxABI(message)
        else { return nil }
        // Only an NSException whose CoreFoundation message is gone gets this far: one whose
        // reason pushed the message past the string cap the reader applies, or wording a later
        // system changed. libc++abi names it by its class, which is no exception name, and it
        // has no reason, so it stays what the corpse says rather than becoming a C++ exception.
        if case .cpp(let name?, _) = exception, isNSExceptionClass(named: name) {
            return nil
        }
        return exception
    }

    /// Whether `name` is NSException or a class inheriting from it, by the same test the
    /// in-process C++ monitor applies to a thrown type. The lookup sends no message, so no class
    /// is initialized for the question. The stitch runs in the app that crashed, so the app's own
    /// subclasses resolve.
    static func isNSExceptionClass(named name: String) -> Bool {
        objc_lookUpClass(name).map { ksobjc_isNSExceptionClass($0) } ?? false
    }

    /// `*** Terminating app due to uncaught exception 'NAME', reason: 'REASON'`, then a newline,
    /// `*** First throw call stack:`, and the throw addresses in parentheses. The name and reason
    /// are written unescaped, so the name ends at the first separator and the reason at the last
    /// stack header: a quote or newline inside either survives.
    static func parseCoreFoundation(_ message: String) -> CorpseLanguageException? {
        let prefix = "*** Terminating app due to uncaught exception '"
        let separator = "', reason: '"
        let stackHeader = "'\n*** First throw call stack:\n"
        guard let prefixRange = message.range(of: prefix, options: [.anchored, .literal]) else { return nil }
        let afterPrefix = message[prefixRange.upperBound...]
        guard let separatorRange = afterPrefix.range(of: separator, options: .literal) else { return nil }
        let name = String(afterPrefix[..<separatorRange.lowerBound])
        guard !name.isEmpty else { return nil }
        let afterSeparator = afterPrefix[separatorRange.upperBound...]

        var reason: Substring
        var throwAddresses: [UInt64] = []
        if let headerRange = afterSeparator.range(of: stackHeader, options: [.backwards, .literal]) {
            reason = afterSeparator[..<headerRange.lowerBound]
            throwAddresses = parseAddressList(afterSeparator[headerRange.upperBound...]) ?? []
        } else {
            var scalars = afterSeparator.unicodeScalars
            while scalars.last == "\n" {
                scalars.removeLast()
            }
            guard scalars.last == "'" else { return .objC(name: name, reason: nil, throwAddresses: []) }
            scalars.removeLast()
            reason = Substring(scalars)
        }
        // CoreFoundation prints a nil reason as "(null)", which is also what a reason of that
        // literal text prints as. Nil is the likely one, and it is what an in-process report
        // records for it: no reason.
        let hasReason = !reason.isEmpty && !reason.unicodeScalars.elementsEqual("(null)".unicodeScalars)
        return .objC(name: name, reason: hasReason ? String(reason) : nil, throwAddresses: throwAddresses)
    }

    /// `(0x19a203190 0x199f80380 ...)`. All or nothing: a list with any token that is not an
    /// address is not trusted for the rest either.
    static func parseAddressList(_ text: Substring) -> [UInt64]? {
        let scalars = text.unicodeScalars
        guard let open = scalars.firstIndex(of: "("), let close = scalars[open...].firstIndex(of: ")") else {
            return nil
        }
        let tokens = scalars[scalars.index(after: open)..<close].split(whereSeparator: { $0 == " " || $0 == "\n" })
        var addresses: [UInt64] = []
        for token in tokens {
            // Swift's integer parser takes a leading sign; an address never has one.
            let digits = token.dropFirst(2)
            guard token.starts(with: "0x".unicodeScalars), let first = digits.first,
                first.properties.isASCIIHexDigit,
                let address = UInt64(String(String.UnicodeScalarView(digits)), radix: 16)
            else { return nil }
            addresses.append(address)
        }
        return addresses.isEmpty ? nil : addresses
    }

    /// `terminating due to uncaught exception of type TYPE`, optionally followed by `: WHAT`
    /// for a `std::exception`, or `terminating` alone when nothing was thrown. A type name
    /// holds `::` but never a colon followed by a space. libc++abi stores the line with no
    /// newline of its own, so everything after the colon is `what()` as thrown, trailing
    /// whitespace included.
    static func parseCxxABI(_ message: String) -> CorpseLanguageException? {
        if message.unicodeScalars.elementsEqual("terminating".unicodeScalars) {
            return .cpp(name: nil, reason: nil)
        }
        let prefix = "terminating due to uncaught exception of type "
        guard let prefixRange = message.range(of: prefix, options: [.anchored, .literal]) else { return nil }
        let described = message[prefixRange.upperBound...]
        guard let whatRange = described.range(of: ": ", options: .literal) else {
            return described.isEmpty ? nil : .cpp(name: String(described), reason: nil)
        }
        let name = described[..<whatRange.lowerBound]
        guard !name.isEmpty else { return nil }
        let what = described[whatRange.upperBound...]
        return .cpp(name: String(name), reason: what.isEmpty ? nil : String(what))
    }
}
