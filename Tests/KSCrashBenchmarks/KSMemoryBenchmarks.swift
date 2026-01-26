//
//  KSMemoryBenchmarks.swift
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

@objc(KSMemoryBenchmarks)
public class KSMemoryBenchmarks: XCTestCase {

    // MARK: - Memory Readability Checks

    /// Benchmark checking if memory is readable (small buffer)
    func testBenchmarkIsMemoryReadableSmall() {
        let size = 64
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }

        measure {
            for _ in 0..<1000 {
                _ = ksmem_isMemoryReadable(buffer, Int32(size))
            }
        }
    }

    /// Benchmark checking if memory is readable (page-sized buffer)
    func testBenchmarkIsMemoryReadablePage() {
        let size = 4096  // Typical page size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4096)
        defer { buffer.deallocate() }

        measure {
            for _ in 0..<1000 {
                _ = ksmem_isMemoryReadable(buffer, Int32(size))
            }
        }
    }

    /// Benchmark checking if memory is readable (large buffer)
    func testBenchmarkIsMemoryReadableLarge() {
        let size = 64 * 1024  // 64KB
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4096)
        defer { buffer.deallocate() }

        measure {
            for _ in 0..<100 {
                _ = ksmem_isMemoryReadable(buffer, Int32(size))
            }
        }
    }

    // MARK: - Safe Copy Benchmarks

    /// Benchmark safe memory copy (small buffer)
    func testBenchmarkCopySafelySmall() {
        let size = 64
        let src = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        let dst = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer {
            src.deallocate()
            dst.deallocate()
        }

        // Initialize source
        memset(src, 0xAB, size)

        measure {
            for _ in 0..<1000 {
                _ = ksmem_copySafely(src, dst, Int32(size))
            }
        }
    }

    /// Benchmark safe memory copy (page-sized buffer)
    func testBenchmarkCopySafelyPage() {
        let size = 4096
        let src = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4096)
        let dst = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4096)
        defer {
            src.deallocate()
            dst.deallocate()
        }

        memset(src, 0xAB, size)

        measure {
            for _ in 0..<1000 {
                _ = ksmem_copySafely(src, dst, Int32(size))
            }
        }
    }

    /// Benchmark safe memory copy (large buffer, typical stack dump scenario)
    func testBenchmarkCopySafelyLarge() {
        let size = 32 * 1024  // 32KB - typical stack content dump
        let src = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4096)
        let dst = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4096)
        defer {
            src.deallocate()
            dst.deallocate()
        }

        memset(src, 0xAB, size)

        measure {
            for _ in 0..<100 {
                _ = ksmem_copySafely(src, dst, Int32(size))
            }
        }
    }

    // MARK: - Max Readable Bytes Benchmarks

    /// Benchmark finding maximum readable bytes (valid memory)
    func testBenchmarkMaxReadableBytesValid() {
        let size = 4096
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4096)
        defer { buffer.deallocate() }

        measure {
            for _ in 0..<100 {
                _ = ksmem_maxReadableBytes(buffer, Int32(size))
            }
        }
    }

    // MARK: - Copy Max Possible Benchmarks

    /// Benchmark copying maximum possible bytes
    func testBenchmarkCopyMaxPossible() {
        let size = 4096
        let src = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4096)
        let dst = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 4096)
        defer {
            src.deallocate()
            dst.deallocate()
        }

        memset(src, 0xAB, size)

        measure {
            for _ in 0..<100 {
                _ = ksmem_copyMaxPossible(src, dst, Int32(size))
            }
        }
    }

    // MARK: - Combined Operations (Crash Scenario)

    /// Benchmark typical crash memory dump scenario
    func testBenchmarkTypicalCrashMemoryDump() {
        // Simulate reading stack memory during crash
        let stackSize = 8192  // Typical stack dump size
        let src = UnsafeMutableRawPointer.allocate(byteCount: stackSize, alignment: 4096)
        let dst = UnsafeMutableRawPointer.allocate(byteCount: stackSize, alignment: 4096)
        defer {
            src.deallocate()
            dst.deallocate()
        }

        memset(src, 0xAB, stackSize)

        measure {
            // Check readability first (typical crash handling pattern)
            if ksmem_isMemoryReadable(src, Int32(stackSize)) {
                _ = ksmem_copySafely(src, dst, Int32(stackSize))
            }
        }
    }
}
