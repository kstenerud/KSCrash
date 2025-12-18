//
//  UnsafeReportWriter.swift
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

#if SWIFT_PACKAGE
    import KSCrashRecording
#endif

/// A Swift-friendly wrapper around the C `ReportWriter` struct.
///
/// This wrapper provides type-safe methods for writing JSON elements to a KSCrash report.
/// It handles the conversion between Swift strings and C strings internally.
///
/// - Important: This struct holds an unsafe pointer and should only be used within the
///   scope where the underlying `ReportWriter` is valid (i.e., during a report write callback).
struct UnsafeReportWriter {
    private let ptr: UnsafePointer<ReportWriter>

    /// Creates a wrapper around the given report writer pointer.
    ///
    /// - Parameter writer: A pointer to a C `ReportWriter` struct.
    /// - Returns: `nil` if the pointer is `nil`.
    init?(_ writer: UnsafePointer<ReportWriter>?) {
        guard let writer else { return nil }
        self.ptr = writer
    }

    // MARK: - Primitives

    /// Adds a boolean element to the report.
    func add(_ name: String, _ value: Bool) {
        name.withCString { cName in
            ptr.pointee.addBooleanElement(ptr, cName, value)
        }
    }

    /// Adds a floating-point element to the report.
    func add(_ name: String, _ value: Double) {
        name.withCString { cName in
            ptr.pointee.addFloatingPointElement(ptr, cName, value)
        }
    }

    /// Adds a signed integer element to the report.
    ///
    /// - Parameter name: The key name, or `nil` when adding to an array.
    func add(_ name: String?, _ value: Int64) {
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
    func add(_ name: String?, _ value: UInt64) {
        if let name {
            name.withCString { cName in
                ptr.pointee.addUIntegerElement(ptr, cName, value)
            }
        } else {
            ptr.pointee.addUIntegerElement(ptr, nil, value)
        }
    }

    /// Adds a string element to the report.
    func add(_ name: String, _ value: String) {
        name.withCString { cName in
            value.withCString { cValue in
                ptr.pointee.addStringElement(ptr, cName, cValue)
            }
        }
    }

    // MARK: - Containers

    /// Begins a new JSON object.
    ///
    /// - Parameter name: The key name for the object, or `nil` when adding to an array.
    func beginObject(_ name: String?) {
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
    func beginArray(_ name: String?) {
        if let name {
            name.withCString { cName in
                ptr.pointee.beginArray(ptr, cName)
            }
        } else {
            ptr.pointee.beginArray(ptr, nil)
        }
    }

    /// Ends the current container (object or array).
    func endContainer() {
        ptr.pointee.endContainer(ptr)
    }

    // MARK: - Context

    /// The raw context pointer from the underlying writer.
    var context: UnsafeMutableRawPointer? { ptr.pointee.context }

    /// Retrieves the context as a specific class type.
    ///
    /// - Parameter type: The expected type of the context object.
    /// - Returns: The context cast to the specified type, or `nil` if the context is `nil`.
    /// - Warning: The caller must ensure the context actually contains an object of the specified type.
    func context<T: AnyObject>(as _: T.Type) -> T? {
        guard let ctx = context else { return nil }
        return Unmanaged<T>.fromOpaque(ctx).takeUnretainedValue()
    }
}
