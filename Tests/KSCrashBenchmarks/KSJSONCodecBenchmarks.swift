//
//  KSJSONCodecBenchmarks.swift
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

import KSCrashRecordingCore
import XCTest

final class KSJSONCodecBenchmarks: XCTestCase {

    // Buffer to collect JSON output
    private var outputBuffer: [UInt8] = []

    private func createAddDataCallback() -> KSJSONAddDataFunc {
        return { data, length, userData in
            guard let data = data, let context = userData else {
                return Int32(KSJSON_ERROR_CANNOT_ADD_DATA)
            }
            let buffer = context.assumingMemoryBound(to: [UInt8].self)
            let bytes = UnsafeBufferPointer(start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
            buffer.pointee.append(contentsOf: bytes)
            return Int32(KSJSON_OK)
        }
    }

    // MARK: - Simple Value Encoding Benchmarks

    /// Benchmark encoding integer values
    func testBenchmarkEncodeIntegers() {
        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(4096)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    "field\(i)".withCString { name in
                        ksjson_addIntegerElement(&context, name, Int64(i * 1000))
                    }
                }
                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }

    /// Benchmark encoding floating point values
    func testBenchmarkEncodeFloats() {
        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(4096)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    "field\(i)".withCString { name in
                        ksjson_addFloatingPointElement(&context, name, Double(i) * 3.14159)
                    }
                }
                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }

    /// Benchmark encoding boolean values
    func testBenchmarkEncodeBooleans() {
        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(4096)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    "field\(i)".withCString { name in
                        ksjson_addBooleanElement(&context, name, i % 2 == 0)
                    }
                }
                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }

    // MARK: - String Encoding Benchmarks

    /// Benchmark encoding short strings
    func testBenchmarkEncodeShortStrings() {
        let shortString = "Hello, World!"

        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(8192)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    "field\(i)".withCString { name in
                        shortString.withCString { value in
                            ksjson_addStringElement(&context, name, value, KSJSON_SIZE_AUTOMATIC)
                        }
                    }
                }
                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }

    /// Benchmark encoding long strings (typical symbol names)
    func testBenchmarkEncodeLongStrings() {
        let longString = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", count: 10)

        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(65536)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)
                for i in 0..<50 {
                    "field\(i)".withCString { name in
                        longString.withCString { value in
                            ksjson_addStringElement(&context, name, value, KSJSON_SIZE_AUTOMATIC)
                        }
                    }
                }
                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }

    /// Benchmark encoding strings with special characters (requires escaping)
    func testBenchmarkEncodeStringsWithEscaping() {
        let escapingString = "Hello\n\t\"World\"\\Path/To/File\r\n"

        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(8192)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    "field\(i)".withCString { name in
                        escapingString.withCString { value in
                            ksjson_addStringElement(&context, name, value, KSJSON_SIZE_AUTOMATIC)
                        }
                    }
                }
                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }

    // MARK: - Nested Structure Benchmarks

    /// Benchmark encoding nested objects (typical crash report structure)
    func testBenchmarkEncodeNestedObjects() {
        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(16384)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)
                for i in 0..<20 {
                    "thread\(i)".withCString { threadName in
                        ksjson_beginObject(&context, threadName)
                        "index".withCString { name in
                            ksjson_addIntegerElement(&context, name, Int64(i))
                        }
                        "name".withCString { name in
                            "Thread \(i)".withCString { value in
                                ksjson_addStringElement(&context, name, value, KSJSON_SIZE_AUTOMATIC)
                            }
                        }
                        "crashed".withCString { name in
                            ksjson_addBooleanElement(&context, name, i == 0)
                        }
                        ksjson_endContainer(&context)
                    }
                }
                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }

    /// Benchmark encoding arrays (typical backtrace structure)
    func testBenchmarkEncodeArrays() {
        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(16384)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)
                "backtrace".withCString { name in
                    ksjson_beginArray(&context, name)
                    for i in 0..<50 {
                        ksjson_addUIntegerElement(&context, nil, UInt64(0x1_0000_0000 + i * 4))
                    }
                    ksjson_endContainer(&context)
                }
                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }

    // MARK: - Data Encoding Benchmarks

    /// Benchmark encoding binary data as hex (typical memory dump)
    func testBenchmarkEncodeHexData() {
        let dataSize = 256
        var data = [CChar](repeating: 0, count: dataSize)
        for i in 0..<dataSize {
            data[i] = CChar(truncatingIfNeeded: i)
        }

        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(8192)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)
                for i in 0..<10 {
                    "data\(i)".withCString { name in
                        ksjson_addDataElement(&context, name, data, Int32(dataSize))
                    }
                }
                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }

    // MARK: - Simulated Crash Report Structure

    /// Benchmark encoding a structure similar to a crash report
    func testBenchmarkEncodeTypicalCrashReport() {
        measure {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(65536)

            withUnsafeMutablePointer(to: &buffer) { bufferPtr in
                var context = KSJSONEncodeContext()
                ksjson_beginEncode(
                    &context, false,
                    { data, length, userData in
                        guard let data = data, let ctx = userData else { return Int32(KSJSON_ERROR_CANNOT_ADD_DATA) }
                        let buf = ctx.assumingMemoryBound(to: [UInt8].self)
                        let bytes = UnsafeBufferPointer(
                            start: UnsafePointer<UInt8>(OpaquePointer(data)), count: Int(length))
                        buf.pointee.append(contentsOf: bytes)
                        return Int32(KSJSON_OK)
                    }, bufferPtr)

                ksjson_beginObject(&context, nil)

                // System info
                "system".withCString { name in
                    ksjson_beginObject(&context, name)
                    "os_version".withCString { key in
                        "17.0".withCString { value in
                            ksjson_addStringElement(&context, key, value, KSJSON_SIZE_AUTOMATIC)
                        }
                    }
                    "device_type".withCString { key in
                        "iPhone14,2".withCString { value in
                            ksjson_addStringElement(&context, key, value, KSJSON_SIZE_AUTOMATIC)
                        }
                    }
                    "memory_size".withCString { key in
                        ksjson_addUIntegerElement(&context, key, 6_000_000_000)
                    }
                    ksjson_endContainer(&context)
                }

                // Crash info
                "crash".withCString { name in
                    ksjson_beginObject(&context, name)
                    "type".withCString { key in
                        "mach".withCString { value in
                            ksjson_addStringElement(&context, key, value, KSJSON_SIZE_AUTOMATIC)
                        }
                    }
                    "signal".withCString { key in
                        ksjson_addIntegerElement(&context, key, 11)
                    }
                    ksjson_endContainer(&context)
                }

                // Threads (10 threads, each with 30-frame backtrace)
                "threads".withCString { name in
                    ksjson_beginArray(&context, name)
                    for t in 0..<10 {
                        ksjson_beginObject(&context, nil)
                        "index".withCString { key in
                            ksjson_addIntegerElement(&context, key, Int64(t))
                        }
                        "crashed".withCString { key in
                            ksjson_addBooleanElement(&context, key, t == 0)
                        }
                        "backtrace".withCString { key in
                            ksjson_beginArray(&context, key)
                            for f in 0..<30 {
                                ksjson_beginObject(&context, nil)
                                "address".withCString { k in
                                    ksjson_addUIntegerElement(&context, k, UInt64(0x1_0000_0000 + t * 1000 + f * 4))
                                }
                                "symbol".withCString { k in
                                    "_ZN5MyApp10SomeClass15someFunctionEv".withCString { v in
                                        ksjson_addStringElement(&context, k, v, KSJSON_SIZE_AUTOMATIC)
                                    }
                                }
                                ksjson_endContainer(&context)
                            }
                            ksjson_endContainer(&context)
                        }
                        ksjson_endContainer(&context)
                    }
                    ksjson_endContainer(&context)
                }

                ksjson_endContainer(&context)
                ksjson_endEncode(&context)
            }
        }
    }
}
