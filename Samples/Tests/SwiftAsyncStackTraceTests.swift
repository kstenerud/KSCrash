//
//  SwiftAsyncStackTraceTests.swift
//
//  Created by Gleb Linnik on 28.07.2026.
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

import CrashTriggers
import IntegrationTestsHelper
import KSCrashReportModel
import XCTest

#if !os(watchOS)

    final class SwiftAsyncStackTraceTests: IntegrationTestBase {

        /// With `enableSwiftAsyncStackTraces` on, the suspended async callers of the reporting
        /// function must appear in the captured backtrace. Plain `backtrace()` cannot see them,
        /// because a suspended async caller has no frame on the current stack.
        func testAsyncCallersAppearInBacktrace() throws {
            let backtrace = try captureAsyncBacktrace()
            let symbolNames = backtrace.contents.compactMap(\.symbolName)

            for expected in [
                swiftAsyncInnerFuncName,
                swiftAsyncMiddleFuncName,
                swiftAsyncOuterFuncName,
            ] {
                XCTAssertTrue(
                    symbolNames.contains { $0.contains(expected) },
                    "\(expected) missing from async backtrace. Symbols: \(symbolNames)")
            }
        }

        /// Regression guard for the arm64 continuation off-by-one (see `KSSymbolicator.c`).
        ///
        /// A name-based assertion cannot catch this: the symbol landed on is usually a sibling
        /// funclet of the same Swift function, whose mangled name still contains the source name.
        func testAsyncContinuationFramesResolveToTheirOwnFunclet() throws {
            let backtrace = try captureAsyncBacktrace()

            let asyncCallerNames = [swiftAsyncMiddleFuncName, swiftAsyncOuterFuncName]
            let continuationFrames = backtrace.contents.filter { frame in
                asyncCallerNames.contains { frame.symbolName?.contains($0) ?? false }
            }
            XCTAssertFalse(continuationFrames.isEmpty, "no async caller frames to check")

            for frame in continuationFrames {
                guard let instructionAddr = frame.instructionAddr, let symbolAddr = frame.symbolAddr
                else {
                    XCTFail("async frame is missing addresses: \(frame)")
                    continue
                }
                // The +1 bias puts the reported address one past the funclet start, so a correctly
                // symbolicated continuation sits at offset 1 from its own symbol.
                XCTAssertLessThanOrEqual(
                    instructionAddr - symbolAddr, 1,
                    """
                    Continuation frame \(frame.symbolName ?? "?") resolved \
                    \(instructionAddr - symbolAddr) bytes back — expected ≤1.
                    """)
            }
        }

        // MARK: - Helpers

        private func captureAsyncBacktrace() throws -> Backtrace {
            try launchAndCrash(
                .user_swiftAsync,
                installOverride: { (configuration: inout InstallConfig) in
                    configuration.isSwiftAsyncStackTracesEnabled = true
                })

            let rawReport = try readCrashReport()
            try rawReport.validate()

            let crashedThread = try XCTUnwrap(rawReport.crashedThread)
            return try XCTUnwrap(crashedThread.backtrace)
        }
    }

#endif
