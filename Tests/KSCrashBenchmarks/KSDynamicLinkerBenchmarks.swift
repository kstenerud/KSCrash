//
//  KSDynamicLinkerBenchmarks.swift
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

import Darwin
import KSCrashRecordingCore
import XCTest

final class KSDynamicLinkerBenchmarks: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        ksbic_init()
    }

    // MARK: - Image Lookup Benchmarks

    /// Benchmark looking up which image contains an address (via ksdl_dladdr)
    /// This is the primary performance bottleneck - O(n*m) where n=images, m=load commands
    func testBenchmarkImageLookupSingleAddress() {
        // Get a valid address to look up (use a function pointer from this module)
        let address = unsafeBitCast(ksbic_init as @convention(c) () -> Void, to: UInt.self)

        var info = Dl_info()
        measure {
            for _ in 0..<100 {
                _ = ksdl_dladdr(address, &info)
            }
        }
    }

    /// Benchmark looking up multiple different addresses (simulates crash stack symbolication)
    func testBenchmarkImageLookupMultipleAddresses() {
        // Capture a backtrace to get realistic addresses from different images
        let thread = pthread_self()
        let entries = 50
        var addresses: [UInt] = Array(repeating: 0, count: entries)
        let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

        guard count > 0 else {
            XCTFail("Failed to capture backtrace")
            return
        }

        var info = Dl_info()
        measure {
            for i in 0..<Int(count) {
                _ = ksdl_dladdr(addresses[i], &info)
            }
        }
    }

    /// Benchmark worst-case: addresses from many different images
    func testBenchmarkImageLookupDifferentImages() {
        // Get addresses from different loaded images
        var imageCount: UInt32 = 0
        guard let images = ksbic_getImages(&imageCount), imageCount > 0 else {
            XCTFail("Failed to get images")
            return
        }

        // Collect addresses from up to 20 different images
        let testCount = min(Int(imageCount), 20)
        var addresses: [UInt] = []
        for i in 0..<testCount {
            let header = images[i].imageLoadAddress
            addresses.append(UInt(bitPattern: header))
        }

        var info = Dl_info()
        measure {
            for address in addresses {
                _ = ksdl_dladdr(address, &info)
            }
        }
    }

    // MARK: - Binary Image Extraction Benchmarks

    /// Benchmark extracting binary image info for a single image
    func testBenchmarkBinaryImageForHeaderSingle() {
        var imageCount: UInt32 = 0
        guard let images = ksbic_getImages(&imageCount), imageCount > 0 else {
            XCTFail("Failed to get images")
            return
        }

        let header = images[0].imageLoadAddress
        let name = images[0].imageFilePath

        var buffer = KSBinaryImage()
        measure {
            for _ in 0..<100 {
                _ = ksdl_binaryImageForHeader(header, name, &buffer)
            }
        }
    }

    /// Benchmark extracting binary image info for multiple images (simulates crash report generation)
    func testBenchmarkBinaryImageForHeaderMultiple() {
        var imageCount: UInt32 = 0
        guard let images = ksbic_getImages(&imageCount), imageCount > 0 else {
            XCTFail("Failed to get images")
            return
        }

        let testCount = min(Int(imageCount), 50)
        var buffer = KSBinaryImage()

        measure {
            for i in 0..<testCount {
                let header = images[i].imageLoadAddress
                let name = images[i].imageFilePath
                _ = ksdl_binaryImageForHeader(header, name, &buffer)
            }
        }
    }

    /// Benchmark extracting all binary images (full crash report scenario)
    func testBenchmarkBinaryImageForHeaderAll() {
        var imageCount: UInt32 = 0
        guard let images = ksbic_getImages(&imageCount), imageCount > 0 else {
            XCTFail("Failed to get images")
            return
        }

        var buffer = KSBinaryImage()

        measure {
            for i in 0..<Int(imageCount) {
                let header = images[i].imageLoadAddress
                let name = images[i].imageFilePath
                _ = ksdl_binaryImageForHeader(header, name, &buffer)
            }
        }
    }

    // MARK: - Combined Benchmarks (Realistic Crash Scenarios)

    /// Benchmark typical crash handling: capture backtrace + symbolicate all frames
    func testBenchmarkTypicalCrashSymbolication() {
        let thread = pthread_self()
        let entries = 50
        var addresses: [UInt] = Array(repeating: 0, count: entries)

        measure {
            let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))
            var info = Dl_info()
            for i in 0..<Int(count) {
                _ = ksdl_dladdr(addresses[i], &info)
            }
        }
    }

    /// Benchmark full crash report: symbolicate stack + extract all binary images
    func testBenchmarkFullCrashReport() {
        let thread = pthread_self()
        let entries = 50
        var addresses: [UInt] = Array(repeating: 0, count: entries)

        var imageCount: UInt32 = 0
        guard let images = ksbic_getImages(&imageCount), imageCount > 0 else {
            XCTFail("Failed to get images")
            return
        }

        measure {
            // Phase 1: Capture and symbolicate backtrace
            let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))
            var info = Dl_info()
            for i in 0..<Int(count) {
                _ = ksdl_dladdr(addresses[i], &info)
            }

            // Phase 2: Extract all binary image info
            var buffer = KSBinaryImage()
            for i in 0..<Int(imageCount) {
                let header = images[i].imageLoadAddress
                let name = images[i].imageFilePath
                _ = ksdl_binaryImageForHeader(header, name, &buffer)
            }
        }
    }

    // MARK: - Stress Tests

    /// Benchmark repeated lookups of the same address (tests potential cache benefit)
    func testBenchmarkRepeatedSameAddressLookup() {
        let address = unsafeBitCast(ksbic_init as @convention(c) () -> Void, to: UInt.self)

        var info = Dl_info()
        measure {
            for _ in 0..<1000 {
                _ = ksdl_dladdr(address, &info)
            }
        }
    }

    /// Benchmark sequential lookups of nearby addresses (tests locality benefit)
    func testBenchmarkSequentialNearbyAddresses() {
        // Get a base address
        var imageCount: UInt32 = 0
        guard let images = ksbic_getImages(&imageCount), imageCount > 0 else {
            XCTFail("Failed to get images")
            return
        }

        let baseAddress = UInt(bitPattern: images[0].imageLoadAddress)

        var info = Dl_info()
        measure {
            for offset in stride(from: 0, to: 10000, by: 100) {
                _ = ksdl_dladdr(baseAddress + UInt(offset), &info)
            }
        }
    }

    /// Benchmark exact function address lookup (tests early termination benefit)
    /// Uses actual function pointers which should be exact symbol matches
    func testBenchmarkExactFunctionAddressLookup() {
        // Get addresses of known functions - these should be exact matches (distance = 0)
        let functions: [UInt] = [
            unsafeBitCast(ksbic_init as @convention(c) () -> Void, to: UInt.self),
            unsafeBitCast(
                ksbic_getImages as @convention(c) (UnsafeMutablePointer<UInt32>?) -> UnsafePointer<ks_dyld_image_info>?,
                to: UInt.self),
        ]

        var info = Dl_info()
        measure {
            for _ in 0..<500 {
                for addr in functions {
                    _ = ksdl_dladdr(addr, &info)
                }
            }
        }
    }

    /// Benchmark non-exact address lookup (address inside function, not at entry)
    /// This tests the worst case where we must scan more symbols
    func testBenchmarkNonExactAddressLookup() {
        // Use address slightly after function entry - this won't be an exact match
        let baseAddress = unsafeBitCast(ksbic_init as @convention(c) () -> Void, to: UInt.self)
        let offsetAddress = baseAddress + 0x10  // 16 bytes into the function

        var info = Dl_info()
        measure {
            for _ in 0..<1000 {
                _ = ksdl_dladdr(offsetAddress, &info)
            }
        }
    }
}
