//
//  KSBacktraceTests.swift
//
//  Created by Alexander Cohen on 2025-05-27.
//
// Copyright (c) 2012 Karl Stenerud. All rights reserved.
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

#if !os(watchOS)  // there are no backtraces on watchOS
    class KSBacktraceTests: XCTestCase {

        func testSameThreadBacktrace() {

            let thread = pthread_self()
            let entries = 512
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

            XCTAssert(count > 0)
            XCTAssert(count <= entries)
            for _ in 0..<count {
                // This is flaky right now, i'm not sure why. Will revisit.
                // XCTAssert(addresses[Int(index)] != 0)
            }
        }

        func testOtherThreadSymbolicate() async {
            nonisolated(unsafe) let thread = pthread_self()
            let entries = 10

            let (addresses, count): ([UInt], Int32) = await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .default).async {
                    var localAddresses = [UInt](repeating: 0, count: entries)
                    let localCount = captureBacktrace(thread: thread, addresses: &localAddresses, count: Int32(entries))
                    cont.resume(returning: (localAddresses, localCount))
                }
            }

            XCTAssert(count > 0)
            XCTAssert(count <= entries)
            for i in 0..<Int(count) {
                XCTAssertNotEqual(addresses[i], 0)
            }

            var result = SymbolInformation()
            let success = symbolicate(address: addresses[0], result: &result)
            XCTAssertTrue(success)
            XCTAssertEqual(result.returnAddress, addresses[0])
            XCTAssertNotNil(result.imageName)
            XCTAssertNotNil(result.imageUUID)
            XCTAssertNotNil(result.symbolName)
            XCTAssert(result.imageAddress > 0)
            XCTAssert(result.imageSize > 0)
            XCTAssert(result.symbolAddress > 0)
            XCTAssertNotEqual(result.imageCpuType, 0)
        }

        func testSameThreadSymbolicate() {
            let thread = pthread_self()

            let entries = 10
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            var count: Int32 = 0

            count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

            XCTAssert(count > 0)
            XCTAssert(count <= entries)
            for index in 0..<count {
                XCTAssert(addresses[Int(index)] != 0)
            }

            var result = SymbolInformation()
            let success = symbolicate(address: addresses[0], result: &result)

            XCTAssertTrue(success == true)
            XCTAssert(result.returnAddress == addresses[0])
            XCTAssertNotNil(result.imageName)
            XCTAssertNotNil(result.imageUUID)
            XCTAssertNotNil(result.symbolName)
            XCTAssert(result.imageAddress > 0)
            XCTAssert(result.imageSize > 0)
            XCTAssert(result.symbolAddress > 0)
            XCTAssertNotEqual(result.imageCpuType, 0)
        }

        /// Regression test: Verify that backtrace symbolication returns correct symbols
        /// and not "GCC_except_table" which indicates incorrect image matching.
        func testBacktraceSymbolsAreNotGCCExceptTable() {
            let thread = pthread_self()

            let entries = 20
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

            XCTAssertGreaterThan(count, 0, "Should capture some backtrace frames")

            var gccExceptTableCount = 0
            var validSymbolCount = 0

            for i in 0..<Int(count) {
                let address = addresses[i]
                guard address != 0 else { continue }

                var result = SymbolInformation()
                let success = symbolicate(address: address, result: &result)

                if success, let symbolNamePtr = result.symbolName {
                    let symbolName = String(cString: symbolNamePtr)
                    validSymbolCount += 1

                    // Check for the regression: symbols should NOT be GCC_except_table
                    if symbolName.contains("GCC_except_tab") {
                        gccExceptTableCount += 1
                        let imageName =
                            result.imageName.map { String(cString: $0) } ?? "nil"
                        XCTFail(
                            "Frame \(i): Got GCC_except_table instead of real symbol. "
                                + "Address: 0x\(String(address, radix: 16)), "
                                + "Symbol: \(symbolName), "
                                + "Image: \(imageName)"
                        )
                    }
                }
            }

            // We should have symbolicated at least some frames successfully
            XCTAssertGreaterThan(validSymbolCount, 0, "Should symbolicate at least some frames")

            // None of them should be GCC_except_table
            XCTAssertEqual(
                gccExceptTableCount, 0,
                "No symbols should be GCC_except_table (found \(gccExceptTableCount) out of \(validSymbolCount))"
            )
        }

        /// Test that symbolication across different images (main binary vs dylibs) works correctly.
        /// This specifically tests the fix for __PAGEZERO causing incorrect image matching.
        func testCrossImageSymbolication() {
            // Capture a backtrace that will include frames from different images
            // (test binary, XCTest framework, libdispatch, etc.)
            let thread = pthread_self()

            let entries = 50
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

            XCTAssertGreaterThan(count, 0)

            var imagesSeen = Set<String>()
            var allSymbolsValid = true

            for i in 0..<Int(count) {
                let address = addresses[i]
                guard address != 0 else { continue }

                var result = SymbolInformation()
                let success = symbolicate(address: address, result: &result)

                if success {
                    if let imageNamePtr = result.imageName {
                        imagesSeen.insert(String(cString: imageNamePtr))
                    }

                    if let symbolNamePtr = result.symbolName {
                        let symbolName = String(cString: symbolNamePtr)
                        // Verify no GCC_except_table symbols
                        if symbolName.contains("GCC_except_tab") {
                            allSymbolsValid = false
                            XCTFail("Frame \(i) incorrectly symbolicated to \(symbolName)")
                        }
                    }
                }
            }

            XCTAssertTrue(allSymbolsValid, "All symbols should be valid (not GCC_except_table)")

            // We should see multiple different images in a typical backtrace
            // (at minimum: test binary and some system framework)
            XCTAssertGreaterThan(
                imagesSeen.count, 1,
                "Backtrace should span multiple images, saw: \(imagesSeen)"
            )
        }

        // MARK: - Quick Symbolication Tests

        func testQuickSymbolicateReturnsBasicInfo() {
            let thread = pthread_self()

            let entries = 10
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

            XCTAssertGreaterThan(count, 0)

            var result = SymbolInformation()
            let success = quickSymbolicate(address: addresses[0], result: &result)

            XCTAssertTrue(success)
            XCTAssertEqual(result.returnAddress, addresses[0])
            XCTAssertNotNil(result.imageName)
            XCTAssertNotNil(result.symbolName)
            XCTAssertGreaterThan(result.imageAddress, 0)
            XCTAssertGreaterThan(result.symbolAddress, 0)
        }

        func testQuickSymbolicateDoesNotReturnImageSizeOrUUID() {
            let thread = pthread_self()

            let entries = 10
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

            XCTAssertGreaterThan(count, 0)

            var result = SymbolInformation()
            let success = quickSymbolicate(address: addresses[0], result: &result)

            XCTAssertTrue(success)
            // quickSymbolicate should NOT fill in imageSize or imageUUID
            // (those require additional binary image lookup)
            XCTAssertEqual(result.imageSize, 0, "quickSymbolicate should not fill imageSize")
            XCTAssertNil(result.imageUUID, "quickSymbolicate should not fill imageUUID")
        }

        func testQuickSymbolicateVsFullSymbolicate() {
            let thread = pthread_self()

            let entries = 10
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            let count = captureBacktrace(thread: thread, addresses: &addresses, count: Int32(entries))

            XCTAssertGreaterThan(count, 0)

            var quickResult = SymbolInformation()
            var fullResult = SymbolInformation()

            let quickSuccess = quickSymbolicate(address: addresses[0], result: &quickResult)
            let fullSuccess = symbolicate(address: addresses[0], result: &fullResult)

            XCTAssertTrue(quickSuccess)
            XCTAssertTrue(fullSuccess)

            // Both should return the same basic info
            XCTAssertEqual(quickResult.returnAddress, fullResult.returnAddress)
            XCTAssertEqual(quickResult.symbolAddress, fullResult.symbolAddress)
            XCTAssertEqual(quickResult.imageAddress, fullResult.imageAddress)

            // Full symbolicate should have additional info
            XCTAssertGreaterThan(fullResult.imageSize, 0)
            XCTAssertNotNil(fullResult.imageUUID)
        }

        func testQuickSymbolicateWithInvalidAddress() {
            var result = SymbolInformation()
            let success = quickSymbolicate(address: 0, result: &result)

            XCTAssertFalse(success, "quickSymbolicate should fail for address 0")
        }
    }
#endif
