//
//  MetricKitMemoryParsing_Tests.swift
//
//  Created by Alexander Cohen on 2026-06-21.
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

import KSCrashReportModel
import XCTest

@testable import KSCrashMonitors

// Pure, platform-independent tests for the call-stack parsing hardening that backs the iOS 27
// memory exception path. These do not need MetricKit: they exercise the shared
// CallStackTreeRepresentation extraction directly. The typed CallStackTree adapter itself is
// covered separately under Xcode 27 (see the guarded section at the bottom).
final class MetricKitMemoryParsingTests: XCTestCase {

    private typealias Frame = CallStackTreeRepresentation.Frame

    // MARK: - objectBaseAddress underflow guard

    func testObjectBaseAddressSubtractsOffset() {
        let frame = Frame(address: 0x1000, offsetIntoBinaryTextSegment: 0x100)
        XCTAssertEqual(objectBaseAddress(of: frame), 0x1000 - 0x100)
    }

    func testObjectBaseAddressNilWhenNoOffset() {
        let frame = Frame(address: 0x1000)
        XCTAssertNil(objectBaseAddress(of: frame))
    }

    func testObjectBaseAddressZeroWhenOffsetEqualsAddress() {
        let frame = Frame(address: 0x100, offsetIntoBinaryTextSegment: 0x100)
        XCTAssertEqual(objectBaseAddress(of: frame), 0)
    }

    func testObjectBaseAddressNilWhenOffsetExceedsAddress() {
        // A frame with no address (mapped to 0 by the iOS 27 adapter) but a real offset would
        // underflow UInt64 if subtracted directly. The guard must return nil, not trap.
        let frame = Frame(address: 0, offsetIntoBinaryTextSegment: 0x100)
        XCTAssertNil(objectBaseAddress(of: frame))
    }

    // MARK: - buildCallStackData hardening

    func testCrashExtractionComputesObjectAddrAndImage() throws {
        let tree = CallStackTreeRepresentation(callStacks: [
            .init(
                threadAttributed: true,
                callStackRootFrames: [
                    Frame(
                        address: 0x2000,
                        binaryUUID: "BBBBBBBB-0000-0000-0000-000000000000",
                        binaryName: "App",
                        offsetIntoBinaryTextSegment: 0x200)
                ])
        ])

        let data = buildCallStackData(from: tree)

        XCTAssertEqual(data.threads.count, 1)
        XCTAssertEqual(data.crashedThreadIndex, 0)

        let frame = try XCTUnwrap(data.threads.first?.backtrace?.contents.first)
        XCTAssertEqual(frame.instructionAddr, 0x2000)
        XCTAssertEqual(frame.objectAddr, 0x2000 - 0x200)
        XCTAssertEqual(frame.objectName, "App")

        XCTAssertEqual(data.binaryImages.count, 1)
        XCTAssertEqual(data.binaryImages.first?.imageAddr, 0x2000 - 0x200)
    }

    func testCrashExtractionDoesNotTrapOnUnderflowFrame() throws {
        // address 0 with a non-nil offset is reachable via the iOS 27 adapter when
        // CallStackFrame.address is absent. Extraction must not trap on `0 - offset`.
        let tree = CallStackTreeRepresentation(callStacks: [
            .init(
                threadAttributed: true,
                callStackRootFrames: [
                    Frame(
                        address: 0,
                        binaryUUID: "CCCCCCCC-0000-0000-0000-000000000000",
                        binaryName: "Broken",
                        offsetIntoBinaryTextSegment: 0x100)
                ])
        ])

        let data = buildCallStackData(from: tree)

        let frame = try XCTUnwrap(data.threads.first?.backtrace?.contents.first)
        XCTAssertEqual(frame.instructionAddr, 0)
        // No base could be computed, so objectAddr is nil rather than an underflowed value.
        XCTAssertNil(frame.objectAddr)
        // The image address falls back to the frame address (0) instead of underflowing.
        XCTAssertEqual(data.binaryImages.first?.imageAddr, 0)
    }
}

// MARK: - Typed CallStackTree Adapter (iOS 27+)

// The adapter lives behind the same gate as the production code. Decode a CallStackTree from
// its Codable JSON form (the shape MetricKit vends) and assert the mapping into the shared
// representation, including binary-name resolution from the separate binaryInfo table and the
// nil-address safety rule.
#if compiler(>=6.4) && os(iOS) && !targetEnvironment(macCatalyst)

    import MetricKit

    @available(iOS 27.0, *)
    final class MetricKitCallStackTreeAdapterTests: XCTestCase {

        // Two frames: one fully populated, one whose address is absent (so the adapter must drop
        // the offset to avoid an underflow downstream). Binary names come from `binaryInfo`.
        private let fixture = """
            {
              "callStackPerThread": true,
              "binaryInfo": [
                { "name": "App", "uuid": "BBBBBBBB-0000-0000-0000-000000000000" }
              ],
              "callStackThreads": [
                {
                  "threadAttributed": true,
                  "rootFrames": [
                    {
                      "address": 8192,
                      "binaryUUID": "BBBBBBBB-0000-0000-0000-000000000000",
                      "offsetIntoBinaryTextSegment": 512,
                      "sampleCount": 1,
                      "subFrames": [
                        {
                          "offsetIntoBinaryTextSegment": 256,
                          "sampleCount": 1,
                          "subFrames": []
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """

        func testAdapterMapsTypedTreeIntoRepresentation() throws {
            try XCTSkipUnless(
                ProcessInfo.processInfo.isOperatingSystemAtLeast(
                    OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)),
                "Requires iOS 27 runtime for MetricKit.CallStackTree")

            let tree = try JSONDecoder().decode(CallStackTree.self, from: Data(fixture.utf8))
            let rep = tree.callStackRepresentation

            XCTAssertEqual(rep.callStacks.count, 1)
            XCTAssertEqual(rep.callStacks[0].threadAttributed, true)

            let root = try XCTUnwrap(rep.callStacks[0].callStackRootFrames?.first)
            XCTAssertEqual(root.address, 8192)
            XCTAssertEqual(root.offsetIntoBinaryTextSegment, 512)
            // Name resolved from the separate binaryInfo table.
            XCTAssertEqual(root.binaryName, "App")
            XCTAssertEqual(root.binaryUUID, "BBBBBBBB-0000-0000-0000-000000000000")

            // The child frame had no address: it maps to 0 and, crucially, drops its offset so
            // the shared extraction never computes `0 - offset`.
            let child = try XCTUnwrap(root.subFrames?.first)
            XCTAssertEqual(child.address, 0)
            XCTAssertNil(child.offsetIntoBinaryTextSegment)

            // End to end, extraction stays underflow-safe.
            let data = buildCallStackData(from: rep)
            XCTAssertEqual(data.crashedThreadIndex, 0)
        }
    }

#endif
