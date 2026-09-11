//
//  ReportSectionWriter.swift
//
//  Created by Alexander Cohen on 2025-12-14.
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
import KSCrashRecording

/// A Swift-friendly wrapper around the C `ReportWriter` struct.
///
/// This wrapper provides type-safe methods for writing JSON elements to a KSCrash report.
/// It handles the conversion between Swift strings and C strings internally.
///
/// - Important: This struct holds an unsafe pointer and should only be used within the
///   scope where the underlying `ReportWriter` is valid (i.e., during a report write callback).
public struct ReportSectionWriter {
    private let ptr: UnsafePointer<ReportWriter>

    /// Tracks a not-yet-opened enclosing section, so a monitor that writes nothing produces no
    /// key at all rather than an empty object. A reference type because the writer is a struct
    /// handed to the monitor by value; the bridge needs to see whether the section was opened.
    final class PendingSection {
        let name: String
        private(set) var isOpen = false
        init(name: String) { self.name = name }
        func markOpen() { isOpen = true }
    }

    private let pendingSection: PendingSection?

    /// Creates a wrapper around the given report writer pointer.
    ///
    /// - Parameter writer: A pointer to a C `ReportWriter` struct.
    /// - Returns: `nil` if the pointer is `nil`.
    public init?(_ writer: UnsafePointer<ReportWriter>?) {
        guard let writer else { return nil }
        self.ptr = writer
        self.pendingSection = nil
    }

    /// Creates a writer that opens `section` lazily, on the first value written through it.
    init?(_ writer: UnsafePointer<ReportWriter>?, section: PendingSection) {
        guard let writer else { return nil }
        self.ptr = writer
        self.pendingSection = section
    }

    /// Opens the enclosing section on first write. No-op once open, or when this writer has no
    /// pending section (the plain init).
    private func openSectionIfNeeded() {
        guard let pendingSection, !pendingSection.isOpen else { return }
        pendingSection.markOpen()
        pendingSection.name.withCString { ptr.pointee.beginObject(ptr, $0) }
    }

    // MARK: - Primitives

    /// Adds a boolean element to the report.
    public func add(_ name: String, _ value: Bool) {
        openSectionIfNeeded()
        name.withCString { cName in
            ptr.pointee.addBooleanElement(ptr, cName, value)
        }
    }

    /// Adds a floating-point element to the report.
    public func add(_ name: String, _ value: Double) {
        openSectionIfNeeded()
        name.withCString { cName in
            ptr.pointee.addFloatingPointElement(ptr, cName, value)
        }
    }

    /// Adds a signed integer element to the report.
    ///
    /// - Parameter name: The key name, or `nil` when adding to an array.
    public func add(_ name: String?, _ value: Int64) {
        openSectionIfNeeded()
        if let name {
            name.withCString { cName in
                ptr.pointee.addIntegerElement(ptr, cName, value)
            }
        } else {
            ptr.pointee.addIntegerElement(ptr, nil, value)
        }
    }

    /// Adds an unsigned integer element to the report.
    ///
    /// - Parameter name: The key name, or `nil` when adding to an array.
    public func add(_ name: String?, _ value: UInt64) {
        openSectionIfNeeded()
        if let name {
            name.withCString { cName in
                ptr.pointee.addUIntegerElement(ptr, cName, value)
            }
        } else {
            ptr.pointee.addUIntegerElement(ptr, nil, value)
        }
    }

    /// Adds a string element to the report.
    public func add(_ name: String, _ value: String) {
        openSectionIfNeeded()
        name.withCString { cName in
            value.withCString { cValue in
                ptr.pointee.addStringElement(ptr, cName, cValue)
            }
        }
    }

    /// Adds a UUID element to the report (formatted as a standard UUID string).
    public func addUUID(_ name: String, _ value: UnsafePointer<UInt8>) {
        openSectionIfNeeded()
        name.withCString { cName in
            ptr.pointee.addUUIDElement(ptr, cName, value)
        }
    }

    // MARK: - Containers

    /// Begins a new JSON object.
    ///
    /// - Parameter name: The key name for the object, or `nil` when adding to an array.
    public func beginObject(_ name: String?) {
        openSectionIfNeeded()
        if let name {
            name.withCString { cName in
                ptr.pointee.beginObject(ptr, cName)
            }
        } else {
            ptr.pointee.beginObject(ptr, nil)
        }
    }

    /// Begins a new JSON array.
    ///
    /// - Parameter name: The key name for the array, or `nil` when adding to an array.
    public func beginArray(_ name: String?) {
        openSectionIfNeeded()
        if let name {
            name.withCString { cName in
                ptr.pointee.beginArray(ptr, cName)
            }
        } else {
            ptr.pointee.beginArray(ptr, nil)
        }
    }

    /// Ends the current container (object or array).
    ///
    /// Deliberately does NOT open a pending section: ending is only meaningful after a begin,
    /// which already opened it, and opening here would leave the bridge closing a container
    /// this call had already closed.
    public func endContainer() {
        ptr.pointee.endContainer(ptr)
    }

    // MARK: - Encodable

    /// JSON-encodes `value` and adds it under `name` via the writer's JSON-element support.
    ///
    /// The writer re-parses the JSON with a fixed per-string buffer (5000 bytes), so no single
    /// string inside `value` may exceed it; oversized elements are rejected by the writer.
    public func encode(_ name: String, _ value: some Encodable) throws {
        openSectionIfNeeded()
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else { return }
        name.withCString { cName in
            json.withCString { cJSON in
                ptr.pointee.addJSONElement(ptr, cName, cJSON, false)
            }
        }
    }
}
