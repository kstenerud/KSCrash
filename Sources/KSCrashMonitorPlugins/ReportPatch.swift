//
//  ReportPatch.swift
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
import KSCrashReportModel

/// A report being edited, with typed access to any part of it.
///
/// A ``Section`` names a part of the report by the object keys that lead to it, outermost first,
/// together with the type that models it: `Section<AppMemoryInfo>("system", "app_memory")` is the
/// `app_memory` object inside the report's `system` object, and is also ``Section/appMemory``. Any
/// JSON value, whether the report model covers it or not, is reached through a
/// `Section<MetadataValue>`.
///
/// Typed edits through ``update(_:body:)`` change only what the edit changed. Everything else
/// in the section stays as it was, including keys the type does not model, in nested objects at
/// any depth, with any nulls inside dropped. An array the edit changed is written back as the edit
/// left it, keeping only what the type models.
///
/// A report holds no nulls. A nil written through a patch is a removal at every depth, and a null
/// already in the report reads as absent.
///
/// Dates are seconds since 1970, as metadata holds them. The report's own timestamps keep the
/// formats their model types read and write.
public struct ReportPatch {
    /// The report as a JSON object, in the form `JSONSerialization` produces.
    var dictionary: [String: Any]

    /// A patch over a report as `JSONSerialization` decodes it.
    public init(_ dictionary: [String: Any]) {
        self.dictionary = dictionary
    }

    /// A section whose path runs through a value that is neither an object nor null.
    public struct PathError: Error, CustomStringConvertible {
        /// The part of the path that leads to that value.
        public let path: [String]

        public var description: String {
            "\(path.joined(separator: ".")) is not an object"
        }
    }

    /// The section's value, or nil when there is none (the key is absent or holds null). A null
    /// inside the value reads as absent too.
    ///
    /// Throws a ``PathError`` when the section's path runs through a value that is neither an
    /// object nor null, a `DecodingError` when the value does not decode as `T`, and an
    /// `EncodingError` when the value cannot be written as JSON (such as a non-finite number in the
    /// report).
    public func value<T>(_ section: Section<T>) throws -> T? {
        guard let object = try Self.value(at: section.path[...], in: dictionary, walked: []).flatMap(Self.withoutNulls)
        else { return nil }
        return try Self.decode(T.self, from: object)
    }

    /// Decodes the section's value, lets `body` change it, and writes back what changed.
    ///
    /// When the section has no value (the key is absent or holds null), `T` starts as what it
    /// decodes from null when it can (an optional starts as nil), and otherwise from an empty
    /// object, so a type that can be built from neither (required fields, a non-optional scalar or
    /// array) throws there. An edit that changes nothing there leaves the patch unchanged.
    ///
    /// When `body` sets an optional `T` to nil, the section's value is removed. A key that
    /// `body`'s change removes (an optional member set to nil) is removed; a key `body` added is
    /// added. Keys `body` did not change keep their original values, and so do keys `T` does not
    /// model, with any nulls inside dropped. An array `body` changed is written back as `body` left
    /// it, so its elements keep only what `T` models; an array `body` did not change is kept.
    ///
    /// An edit is what `body` changed in the value `T` read, so a value `T` reads lossily cannot be
    /// replaced by setting it to what `T` already read. A value `T` cannot parse reads as nil, and
    /// setting it to nil is no change, so the value stays; a value `T` reads into a normalized form
    /// stays as written when `body` sets that same form. Use ``set(_:at:)`` or ``remove(_:)`` to
    /// replace or clear such a value.
    ///
    /// Throws a ``PathError`` when the section's path runs through a value that is neither an
    /// object nor null, a `DecodingError` when the value does not decode as `T`, an `EncodingError`
    /// when the value cannot be written as JSON (such as a non-finite number), and whatever `body`
    /// throws. The patch is unchanged when this throws.
    public mutating func update<T: Codable>(_ section: Section<T>, body: (inout T) throws -> Void) throws {
        let path = section.path
        // Nulls already in the value read as absent, like a null at the path, and are not written
        // back.
        let existing = try Self.value(at: path[...], in: dictionary, walked: []).flatMap(Self.withoutNulls)
        let original = existing ?? [String: Any]()
        var value = try Self.startingValue(T.self, from: existing)
        let baseline = try Self.encode(value)
        try body(&value)
        let changed = try Self.encode(value)
        // With no value at the path, an edit that changed nothing leaves the patch as it is, rather
        // than writing out the empty object `T` started from or removing a null.
        if existing == nil, Self.jsonEqual(baseline ?? NSNull(), changed ?? NSNull()) { return }
        guard let changed else {
            // An edit that sets a nil optional removes the value: a report holds no nulls. A
            // value `T` read as nil and left nil is no change, so it stays.
            if baseline != nil {
                remove(path: path)
            }
            return
        }
        let merged = Self.merge(original: original, baseline: baseline ?? NSNull(), changed: changed)
        dictionary = try Self.setting(merged, at: path[...], in: dictionary, walked: [])
    }

    /// Replaces the section's value with `value` encoded as JSON, creating objects along the path
    /// where there are none. A nil optional is a removal, exactly as ``remove(_:)``, since a report
    /// holds no nulls; so is a nil anywhere inside `value`, which leaves out that member or array
    /// element.
    ///
    /// Throws a ``PathError`` when the section's path runs through a value that is neither an
    /// object nor null (except for a nil `value`, which, like a removal, changes nothing there), and
    /// an `EncodingError` when `value` cannot be written as JSON.
    public mutating func set<T: Codable>(_ value: T, at section: Section<T>) throws {
        guard let encoded = try Self.encode(value) else {
            remove(path: section.path)
            return
        }
        dictionary = try Self.setting(encoded, at: section.path[...], in: dictionary, walked: [])
    }

    /// Removes the section's value. The patch is unchanged when there is none, or when the
    /// section's path runs through a value that is neither an object nor null.
    public mutating func remove<T>(_ section: Section<T>) {
        remove(path: section.path)
    }

    private mutating func remove(path: [String]) {
        dictionary = (try? Self.setting(nil, at: path[...], in: dictionary, walked: [])) ?? dictionary
    }

    // MARK: - Paths

    private static func value(at path: ArraySlice<String>, in object: Any, walked: [String]) throws -> Any? {
        guard let key = path.first else { return object }
        guard let dictionary = object as? [String: Any] else { throw PathError(path: walked) }
        // A null is absent, the report's only "no value".
        guard let next = dictionary[key], !(next is NSNull) else { return nil }
        return try value(at: path.dropFirst(), in: next, walked: walked + [key])
    }

    /// `object` with `value` at `path`, or with nothing there when `value` is nil.
    private static func setting(
        _ value: Any?, at path: ArraySlice<String>, in object: [String: Any], walked: [String]
    ) throws -> [String: Any] {
        // A section's path has at least one key, and the recursion stops at the last one.
        guard let key = path.first else { return object }
        var result = object
        if path.count == 1 {
            result[key] = value
            return result
        }
        let child: [String: Any]
        switch object[key] {
        case nil, is NSNull:
            // Removing below a missing object removes nothing; setting creates it. A null is
            // missing too.
            guard value != nil else { return object }
            child = [:]
        case let existing as [String: Any]:
            child = existing
        default:
            throw PathError(path: walked + [key])
        }
        result[key] = try setting(value, at: path.dropFirst(), in: child, walked: walked + [key])
        return result
    }

    // MARK: - JSON

    /// What `update` hands its body: the value there, or with no value there, `T` decoded from null
    /// when it can be (an optional is nil) and otherwise from an empty object.
    private static func startingValue<T: Decodable>(_ type: T.Type, from object: Any?) throws -> T {
        if let object {
            return try decode(T.self, from: object)
        }
        if let none = try? decode(T.self, from: NSNull()) {
            return none
        }
        return try decode(T.self, from: [String: Any]())
    }

    private static func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(T.self, from: data(from: object))
    }

    /// `value` as JSON with every null left out: a member or array element that encodes as null
    /// is dropped, since a report holds no nulls. nil when `value` itself encodes as null.
    private static func encode(_ value: some Encodable) throws -> Any? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return withoutNulls(try JSONSerialization.jsonObject(with: encoder.encode(value), options: .fragmentsAllowed))
    }

    private static func withoutNulls(_ value: Any) -> Any? {
        switch value {
        case is NSNull:
            return nil
        case let object as [String: Any]:
            return object.compactMapValues(withoutNulls)
        case let array as [Any]:
            return array.compactMap(withoutNulls)
        default:
            return value
        }
    }

    private static func data(from object: Any) throws -> Data {
        // JSONSerialization raises an Objective-C exception, which Swift cannot catch, for a value
        // JSON cannot hold, such as a non-finite number. Check first and throw instead.
        guard JSONSerialization.isValidJSONObject([object]) else {
            throw EncodingError.invalidValue(
                object, .init(codingPath: [], debugDescription: "The value cannot be written as JSON"))
        }
        return try JSONSerialization.data(withJSONObject: object, options: .fragmentsAllowed)
    }

    /// Equality of two JSON values as JSON sees them. `NSNumber.isEqual` alone calls `true` equal
    /// to 1 and `false` to 0, which would hide an edit that turns one into the other.
    private static func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case (let lhs as [String: Any], let rhs as [String: Any]):
            return lhs.count == rhs.count
                && lhs.allSatisfy { key, value in rhs[key].map { jsonEqual(value, $0) } ?? false }
        case (let lhs as [Any], let rhs as [Any]):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { jsonEqual($0, $1) }
        case (let lhs as NSNumber, let rhs as NSNumber):
            return isBoolean(lhs) == isBoolean(rhs) && lhs.isEqual(rhs)
        case (let lhs as String, let rhs as String):
            return lhs == rhs
        default:
            return (lhs as AnyObject).isEqual(rhs)
        }
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// `original` with the changes between `baseline` (the typed value as decoded, re-encoded)
    /// and `changed` (the same after the edit). A key whose encoding did not change keeps its
    /// original value, which is what preserves keys a nested type does not model.
    private static func merge(original: Any, baseline: Any, changed: Any) -> Any {
        guard let original = original as? [String: Any],
            let baseline = baseline as? [String: Any],
            let changed = changed as? [String: Any]
        else {
            return jsonEqual(baseline, changed) ? original : changed
        }
        var result = original
        for key in Set(baseline.keys).union(changed.keys) {
            switch (baseline[key], changed[key]) {
            case (let before?, let after?):
                guard !jsonEqual(before, after) else { continue }
                result[key] = original[key].map { merge(original: $0, baseline: before, changed: after) } ?? after
            case (_?, nil):
                result.removeValue(forKey: key)
            case (nil, let after?):
                result[key] = after
            case (nil, nil):
                break
            }
        }
        return result
    }
}

// MARK: - Sections

extension ReportPatch {
    /// A part of the report, named by the object keys that lead to it, together with the type
    /// that models it. Reading a section needs only `Decodable`; editing one needs `Codable`.
    ///
    /// ```swift
    /// try patch.update(.appMemory) { $0.memoryFootprint = footprint }
    /// ```
    public struct Section<Value: Decodable>: Sendable {
        /// The keys that lead to this part of the report, outermost first.
        public let path: [String]

        /// The part of the report at the path (`first`, then `rest`): the object keys that lead
        /// to it, outermost first.
        public init(_ first: String, _ rest: String...) {
            self.path = [first] + rest
        }
    }
}

extension ReportPatch.Section where Value == ReportInfo {
    /// The report's identity and bookkeeping.
    public static var report: Self { .init("report") }
}

extension ReportPatch.Section where Value == SystemInfo {
    /// The process, device and app details.
    public static var system: Self { .init("system") }
}

extension ReportPatch.Section where Value == AppMemoryInfo {
    /// The app's memory state.
    public static var appMemory: Self { .init("system", "app_memory") }
}

extension ReportPatch.Section where Value == ApplicationStats {
    /// The app's lifecycle statistics.
    public static var applicationStats: Self { .init("system", "application_stats") }
}

extension ReportPatch.Section where Value == CrashError {
    /// What ended or interrupted the process.
    public static var crashError: Self { .init("crash", "error") }
}

extension ReportPatch.Section where Value == HangInfo {
    /// The hang the report describes.
    public static var hang: Self { .init("crash", "error", "hang") }
}
