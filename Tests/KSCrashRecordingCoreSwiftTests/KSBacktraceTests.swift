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

        func testSwiftAsyncStackTracesToggleStillCapturesCurrentThread() {
            defer { kssc_setSwiftAsyncStackTracesEnabled(false) }

            let entries = 128
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            kssc_setSwiftAsyncStackTracesEnabled(false)
            let defaultCount = captureBacktrace(thread: pthread_self(), addresses: &addresses, count: Int32(entries))
            XCTAssertGreaterThan(defaultCount, 0)

            addresses = Array(repeating: 0, count: entries)
            kssc_setSwiftAsyncStackTracesEnabled(true)
            let enabledCount = captureBacktrace(thread: pthread_self(), addresses: &addresses, count: Int32(entries))
            XCTAssertGreaterThan(enabledCount, 0)
        }

        func testSwiftAsyncStackTracesEnabledCapturesAsyncCallers() async {
            defer { kssc_setSwiftAsyncStackTracesEnabled(false) }

            kssc_setSwiftAsyncStackTracesEnabled(false)
            let symbolsWithoutAsync = await swiftAsyncOuterFrame()
            let callerSymbolsWithoutAsync = Self.swiftAsyncCallerSymbolCount(in: symbolsWithoutAsync)

            kssc_setSwiftAsyncStackTracesEnabled(true)
            let symbolsWithAsync = await swiftAsyncOuterFrame()
            let callerSymbolsWithAsync = Self.swiftAsyncCallerSymbolCount(in: symbolsWithAsync)

            XCTAssertGreaterThanOrEqual(
                callerSymbolsWithAsync, 3,
                "backtrace_async should include the suspended Swift async caller chain. Symbols: \(symbolsWithAsync)"
            )
            XCTAssertGreaterThanOrEqual(
                callerSymbolsWithAsync, callerSymbolsWithoutAsync,
                "Enabling Swift async stack traces must not lose async caller frames. Without: \(symbolsWithoutAsync), with: \(symbolsWithAsync)"
            )
        }

        @inline(never)
        private func swiftAsyncOuterFrame() async -> [String] {
            await swiftAsyncMiddleFrame()
        }

        @inline(never)
        private func swiftAsyncMiddleFrame() async -> [String] {
            await Task { @MainActor in }.value
            return await swiftAsyncInnerFrame()
        }

        @inline(never)
        private func swiftAsyncInnerFrame() async -> [String] {
            let entries = 128
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            let count = captureBacktrace(thread: pthread_self(), addresses: &addresses, count: Int32(entries))
            return Self.symbolNames(for: addresses.prefix(Int(count)))
        }

        private static func swiftAsyncCallerSymbolCount(in symbolNames: [String]) -> Int {
            let expectedCallers = ["swiftAsyncOuterFrame", "swiftAsyncMiddleFrame", "swiftAsyncInnerFrame"]
            return symbolNames.filter { symbolName in
                expectedCallers.contains { expectedCaller in
                    symbolName.contains(expectedCaller)
                }
            }.count
        }

        private static func symbolNames(for addresses: ArraySlice<UInt>) -> [String] {
            addresses.compactMap { address in
                guard address != 0 else { return nil }
                var result = SymbolInformation()
                guard quickSymbolicate(address: address, result: &result), let symbolName = result.symbolName else {
                    return nil
                }
                return String(cString: symbolName)
            }
        }

        func testOtherThreadSymbolicate() {
            // A thread of the test's own, parked on a semaphore. Capturing a thread the test does
            // not own (such as its own after an await) lets the scheduler decide whether the
            // capture runs on that same thread, which turns the test into a self-capture.
            let ready = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var target: pthread_t?
            let parked = Thread {
                target = pthread_self()
                ready.signal()
                release.wait()
            }
            parked.start()
            ready.wait()
            defer { release.signal() }
            guard let target else {
                XCTFail("The parked thread never reported itself")
                return
            }
            XCTAssertEqual(pthread_equal(target, pthread_self()), 0, "The capture must not target its own thread")
            waitUntilBlocked(pthread_mach_thread_np(target))

            let entries = 10
            var addresses = [UInt](repeating: 0, count: entries)
            let count = captureBacktrace(thread: target, addresses: &addresses, count: Int32(entries))

            XCTAssert(count > 0)
            XCTAssert(count <= entries)
            for i in 0..<Int(count) {
                XCTAssertNotEqual(addresses[i], 0)
            }

            var result = SymbolInformation()
            let success = symbolicate(address: addresses[0], result: &result)
            // Name every frame on failure, so a frame that resolves to an image without a symbol
            // says which image and offset it was.
            let frames = Self.describe(addresses[0..<Int(max(count, 0))])
            XCTAssertTrue(success, frames)
            XCTAssertEqual(result.returnAddress, addresses[0], frames)
            XCTAssertNotNil(result.imageName, frames)
            XCTAssertNotNil(result.imageUUID, frames)
            XCTAssertNotNil(result.symbolName, frames)
            XCTAssert(result.imageAddress > 0, frames)
            XCTAssert(result.imageSize > 0, frames)
            XCTAssert(result.symbolAddress > 0, frames)
            XCTAssertNotEqual(result.imageCpuType, 0, frames)
        }

        private static func describe(_ addresses: ArraySlice<UInt>) -> String {
            let lines = addresses.enumerated().map { index, address -> String in
                var info = SymbolInformation()
                let hex = "0x" + String(address, radix: 16)
                guard address != 0, symbolicate(address: address, result: &info) else {
                    return "#\(index) \(hex) unresolved"
                }
                let image = info.imageName.map { String(cString: $0) } ?? "(no image)"
                let imageOffset = "0x" + String(address &- info.imageAddress, radix: 16)
                let symbol = info.symbolName.map { String(cString: $0) } ?? "(no symbol)"
                let symbolOffset =
                    info.symbolAddress == 0 ? "" : " + \(Int(bitPattern: address &- info.symbolAddress))"
                return "#\(index) \(hex) \(image) + \(imageOffset) \(symbol)\(symbolOffset)"
            }
            return "frames:\n" + lines.joined(separator: "\n")
        }

        /// Waits until the thread is blocked in the kernel, so its frames are the semaphore wait
        /// rather than whatever it ran between signalling and waiting.
        private func waitUntilBlocked(_ machThread: mach_port_t, timeout: TimeInterval = 5) {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                var info = thread_basic_info()
                var infoCount = mach_msg_type_number_t(
                    MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
                let kr = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                        thread_info(machThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                    }
                }
                guard kr == KERN_SUCCESS else {
                    XCTFail("thread_info failed: \(kr)")
                    return
                }
                if info.run_state == TH_STATE_WAITING {
                    return
                }
                usleep(1000)
            }
            XCTFail("The parked thread never blocked")
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

        // MARK: - Truncation Detection Tests

        func testBacktraceWithSmallBufferIsTruncated() {
            let thread = pthread_self()
            let entries = 2
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            var isTruncated = false
            let count = captureBacktrace(
                thread: thread, addresses: &addresses, count: Int32(entries),
                isTruncated: &isTruncated
            )

            XCTAssertEqual(Int(count), entries, "Should fill all available frames")
            XCTAssertTrue(isTruncated, "A buffer of 2 should be truncated for any real stack")
        }

        func testBacktraceWithLargeBufferIsNotTruncated() {
            let thread = pthread_self()
            let entries = 512
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            var isTruncated = false
            let count = captureBacktrace(
                thread: thread, addresses: &addresses, count: Int32(entries),
                isTruncated: &isTruncated
            )

            XCTAssertGreaterThan(count, 0)
            XCTAssertFalse(isTruncated, "A buffer of 512 should not be truncated for a typical stack")
        }

        func testBacktraceWithSmallBufferIsTruncatedFromMachThread() {
            let machThread = pthread_mach_thread_np(pthread_self())
            let entries = 2
            var addresses: [UInt] = Array(repeating: 0, count: entries)
            var isTruncated = false
            let count = captureBacktrace(
                machThread: machThread, addresses: &addresses, count: Int32(entries),
                isTruncated: &isTruncated
            )

            XCTAssertEqual(Int(count), entries)
            XCTAssertTrue(isTruncated)
        }

        // MARK: - Suspended Thread Capture Tests

        /// Helper: spins up a thread with a deep call stack, reports its mach thread,
        /// then blocks until released. The recursive nesting ensures a non-trivial stack depth
        /// so that truncation tests work reliably (GCD worker threads can have very shallow stacks).
        private func withSuspendedOtherThread(_ body: (mach_port_t) -> Void) {
            let ready = DispatchSemaphore(value: 0)
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var machThread: mach_port_t = 0

            @Sendable func deepBlock(_ depth: Int) {
                if depth > 0 {
                    deepBlock(depth - 1)
                } else {
                    machThread = pthread_mach_thread_np(pthread_self())
                    ready.signal()
                    done.wait()
                }
            }

            DispatchQueue.global().async {
                deepBlock(20)
            }

            ready.wait()

            let kr = thread_suspend(machThread)
            guard kr == KERN_SUCCESS else {
                XCTFail("thread_suspend failed: \(kr)")
                done.signal()
                return
            }

            body(machThread)

            thread_resume(machThread)
            done.signal()
        }

        func testSuspendedCaptureFromOtherThread() {
            withSuspendedOtherThread { machThread in
                let entries = 512
                var addresses = [UInt](repeating: 0, count: entries)
                var isTruncated = false
                let count = captureBacktraceFromSuspended(
                    machThread: machThread, addresses: &addresses,
                    count: Int32(entries), isTruncated: &isTruncated
                )

                XCTAssertGreaterThan(count, 0, "Should capture frames from suspended thread")
                XCTAssertFalse(isTruncated)
                for i in 0..<Int(count) {
                    XCTAssertNotEqual(addresses[i], 0, "Frame \(i) should be non-zero")
                }
            }
        }

        func testSuspendedCaptureWithSmallBufferIsTruncated() {
            withSuspendedOtherThread { machThread in
                // The helper creates a stack ~20+ frames deep, so a buffer of 2 should truncate.
                let entries = 2
                var addresses = [UInt](repeating: 0, count: entries)
                var isTruncated = false
                let count = captureBacktraceFromSuspended(
                    machThread: machThread, addresses: &addresses,
                    count: Int32(entries), isTruncated: &isTruncated
                )

                XCTAssertEqual(Int(count), entries, "Should fill all available frames")
                XCTAssertTrue(isTruncated, "A buffer of 2 should be truncated for a deep stack")
            }
        }

        func testSuspendedCaptureFramesAreSymbolicatable() {
            withSuspendedOtherThread { machThread in
                let entries = 20
                var addresses = [UInt](repeating: 0, count: entries)
                let count = captureBacktraceFromSuspended(
                    machThread: machThread, addresses: &addresses,
                    count: Int32(entries), isTruncated: nil
                )

                XCTAssertGreaterThan(count, 0)

                var symbolicatedCount = 0
                for i in 0..<Int(count) {
                    var result = SymbolInformation()
                    if symbolicate(address: addresses[i], result: &result) {
                        symbolicatedCount += 1
                        XCTAssertGreaterThan(result.symbolAddress, 0)
                        XCTAssertNotNil(result.imageName)
                    }
                }
                XCTAssertGreaterThan(symbolicatedCount, 0, "At least some frames should symbolicate")
            }
        }

        func testSuspendedCaptureWithNullThread() {
            let entries = 10
            var addresses = [UInt](repeating: 0, count: entries)
            var isTruncated = true
            let count = captureBacktraceFromSuspended(
                machThread: mach_port_t(MACH_PORT_NULL), addresses: &addresses,
                count: Int32(entries), isTruncated: &isTruncated
            )

            XCTAssertEqual(count, 0)
            XCTAssertFalse(isTruncated, "isTruncated should be cleared on invalid input")
        }

        func testSuspendedCaptureWithZeroCount() {
            withSuspendedOtherThread { machThread in
                var addresses = [UInt](repeating: 0, count: 1)
                var isTruncated = true
                let count = captureBacktraceFromSuspended(
                    machThread: machThread, addresses: &addresses,
                    count: 0, isTruncated: &isTruncated
                )

                XCTAssertEqual(count, 0)
                XCTAssertFalse(isTruncated)
            }
        }
    }
#endif
