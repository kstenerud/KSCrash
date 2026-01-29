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

class KSJSONCodecBenchmarks: XCTestCase {

    // MARK: - Helper

    private func withJSONEncoder(bufferCapacity: Int = 4096, _ block: (inout KSJSONEncodeContext) -> Void) {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(bufferCapacity)

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

            block(&context)

            ksjson_endEncode(&context)
        }
    }

    // MARK: - Simple Value Encoding Benchmarks

    /// Benchmark encoding integer values
    func testBenchmarkEncodeIntegers() {
        measure {
            withJSONEncoder { context in
                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    let name = "field\(i)"
                    _ = name.withCString { ksjson_addIntegerElement(&context, $0, Int64(i * 1000)) }
                }
                ksjson_endContainer(&context)
            }
        }
    }

    /// Benchmark encoding floating point values
    func testBenchmarkEncodeFloats() {
        measure {
            withJSONEncoder { context in
                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    let name = "field\(i)"
                    _ = name.withCString { ksjson_addFloatingPointElement(&context, $0, Double(i) * 3.14159) }
                }
                ksjson_endContainer(&context)
            }
        }
    }

    /// Benchmark encoding boolean values
    func testBenchmarkEncodeBooleans() {
        measure {
            withJSONEncoder { context in
                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    let name = "field\(i)"
                    _ = name.withCString { ksjson_addBooleanElement(&context, $0, i % 2 == 0) }
                }
                ksjson_endContainer(&context)
            }
        }
    }

    // MARK: - String Encoding Benchmarks

    /// Benchmark encoding short strings
    func testBenchmarkEncodeShortStrings() {
        let shortString = "Hello, World!"

        measure {
            withJSONEncoder(bufferCapacity: 8192) { context in
                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    let name = "field\(i)"
                    _ = name.withCString { namePtr in
                        shortString.withCString {
                            ksjson_addStringElement(&context, namePtr, $0, KSJSON_SIZE_AUTOMATIC)
                        }
                    }
                }
                ksjson_endContainer(&context)
            }
        }
    }

    /// Benchmark encoding long strings (typical symbol names)
    func testBenchmarkEncodeLongStrings() {
        let longString = String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", count: 10)

        measure {
            withJSONEncoder(bufferCapacity: 65536) { context in
                ksjson_beginObject(&context, nil)
                for i in 0..<50 {
                    let name = "field\(i)"
                    _ = name.withCString { namePtr in
                        longString.withCString { ksjson_addStringElement(&context, namePtr, $0, KSJSON_SIZE_AUTOMATIC) }
                    }
                }
                ksjson_endContainer(&context)
            }
        }
    }

    /// Benchmark encoding strings with special characters (requires escaping)
    func testBenchmarkEncodeStringsWithEscaping() {
        let escapingString = "Hello\n\t\"World\"\\Path/To/File\r\n"

        measure {
            withJSONEncoder(bufferCapacity: 8192) { context in
                ksjson_beginObject(&context, nil)
                for i in 0..<100 {
                    let name = "field\(i)"
                    _ = name.withCString { namePtr in
                        escapingString.withCString {
                            ksjson_addStringElement(&context, namePtr, $0, KSJSON_SIZE_AUTOMATIC)
                        }
                    }
                }
                ksjson_endContainer(&context)
            }
        }
    }

    // MARK: - Nested Structure Benchmarks

    /// Benchmark encoding nested objects (typical crash report structure)
    func testBenchmarkEncodeNestedObjects() {
        measure {
            withJSONEncoder(bufferCapacity: 16384) { context in
                ksjson_beginObject(&context, nil)
                for i in 0..<20 {
                    let threadName = "thread\(i)"
                    threadName.withCString { threadNamePtr in
                        ksjson_beginObject(&context, threadNamePtr)
                        _ = "index".withCString { ksjson_addIntegerElement(&context, $0, Int64(i)) }
                        let value = "Thread \(i)"
                        _ = "name".withCString { namePtr in
                            value.withCString { ksjson_addStringElement(&context, namePtr, $0, KSJSON_SIZE_AUTOMATIC) }
                        }
                        _ = "crashed".withCString { ksjson_addBooleanElement(&context, $0, i == 0) }
                        ksjson_endContainer(&context)
                    }
                }
                ksjson_endContainer(&context)
            }
        }
    }

    /// Benchmark encoding arrays (typical backtrace structure)
    func testBenchmarkEncodeArrays() {
        measure {
            withJSONEncoder(bufferCapacity: 16384) { context in
                ksjson_beginObject(&context, nil)
                "backtrace".withCString { namePtr in
                    ksjson_beginArray(&context, namePtr)
                    for i in 0..<50 {
                        ksjson_addUIntegerElement(&context, nil, UInt64(0x1_0000_0000 + i * 4))
                    }
                    ksjson_endContainer(&context)
                }
                ksjson_endContainer(&context)
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
            withJSONEncoder(bufferCapacity: 8192) { context in
                ksjson_beginObject(&context, nil)
                for i in 0..<10 {
                    let name = "data\(i)"
                    _ = name.withCString { ksjson_addDataElement(&context, $0, data, Int32(dataSize)) }
                }
                ksjson_endContainer(&context)
            }
        }
    }

    // MARK: - Simulated Crash Report Structure

    /// Benchmark encoding a structure similar to a crash report
    func testBenchmarkEncodeTypicalCrashReport() {
        measure {
            withJSONEncoder(bufferCapacity: 65536) { context in
                ksjson_beginObject(&context, nil)

                // System info
                "system".withCString { namePtr in
                    ksjson_beginObject(&context, namePtr)
                    _ = "os_version".withCString { key in
                        "17.0".withCString { ksjson_addStringElement(&context, key, $0, KSJSON_SIZE_AUTOMATIC) }
                    }
                    _ = "device_type".withCString { key in
                        "iPhone14,2".withCString { ksjson_addStringElement(&context, key, $0, KSJSON_SIZE_AUTOMATIC) }
                    }
                    _ = "memory_size".withCString { ksjson_addUIntegerElement(&context, $0, 6_000_000_000) }
                    ksjson_endContainer(&context)
                }

                // Crash info
                "crash".withCString { namePtr in
                    ksjson_beginObject(&context, namePtr)
                    _ = "type".withCString { key in
                        "mach".withCString { ksjson_addStringElement(&context, key, $0, KSJSON_SIZE_AUTOMATIC) }
                    }
                    _ = "signal".withCString { ksjson_addIntegerElement(&context, $0, 11) }
                    ksjson_endContainer(&context)
                }

                // Threads (10 threads, each with 30-frame backtrace)
                "threads".withCString { namePtr in
                    ksjson_beginArray(&context, namePtr)
                    for t in 0..<10 {
                        ksjson_beginObject(&context, nil)
                        _ = "index".withCString { ksjson_addIntegerElement(&context, $0, Int64(t)) }
                        _ = "crashed".withCString { ksjson_addBooleanElement(&context, $0, t == 0) }
                        "backtrace".withCString { key in
                            ksjson_beginArray(&context, key)
                            for f in 0..<30 {
                                ksjson_beginObject(&context, nil)
                                _ = "address".withCString {
                                    ksjson_addUIntegerElement(&context, $0, UInt64(0x1_0000_0000 + t * 1000 + f * 4))
                                }
                                _ = "symbol".withCString { k in
                                    "_ZN5MyApp10SomeClass15someFunctionEv".withCString {
                                        ksjson_addStringElement(&context, k, $0, KSJSON_SIZE_AUTOMATIC)
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
            }
        }
    }
}
