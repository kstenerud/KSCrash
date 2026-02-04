//
//  KSCrashMonitor_MetricKit_Tests.swift
//
//  Created by Alexander Cohen on 2026-01-31.
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

import KSCrashRecording
import Report
import XCTest

@testable import Monitors

final class KSCrashMonitor_MetricKit_Tests: XCTestCase {

    // MARK: - Monitor API Lifecycle

    func testMonitorId() {
        let api = MetricKitMonitor.api.pointee
        let monitorId = api.monitorId()
        XCTAssertNotNil(monitorId)
        XCTAssertEqual(String(cString: monitorId!), "MetricKit")
    }

    func testMonitorFlags() {
        let api = MetricKitMonitor.api.pointee
        let flags = api.monitorFlags()
        XCTAssertEqual(flags.rawValue, 0)
    }

    func testEnableDisable() {
        let api = MetricKitMonitor.api.pointee
        XCTAssertFalse(api.isEnabled())

        api.setEnabled(true)
        XCTAssertTrue(api.isEnabled())

        api.setEnabled(false)
        XCTAssertFalse(api.isEnabled())
    }

    func testIdempotentEnable() {
        let api = MetricKitMonitor.api.pointee
        api.setEnabled(true)
        api.setEnabled(true)
        XCTAssertTrue(api.isEnabled())

        api.setEnabled(false)
        api.setEnabled(false)
        XCTAssertFalse(api.isEnabled())
    }

    func testMonitorPlugin() {
        let plugin = Monitors.metricKit
        XCTAssertEqual(plugin.api, MetricKitMonitor.api)
    }

    // MARK: - Call Stack Tree Flattening

    #if os(iOS) || os(macOS)
        private typealias Frame = CallStackTreeRepresentation.Frame

        func testFlattenFrames() {
            let frames: [Frame] = [
                Frame(
                    address: 0x1000,
                    binaryUUID: "ABC-123",
                    binaryName: "MyApp",
                    offsetIntoBinaryTextSegment: 0x100,
                    subFrames: [
                        Frame(
                            address: 0x2000,
                            binaryUUID: "ABC-123",
                            binaryName: "MyApp",
                            offsetIntoBinaryTextSegment: 0x100,
                            subFrames: [
                                Frame(
                                    address: 0x3000,
                                    binaryUUID: "DEF-456",
                                    binaryName: "Foundation",
                                    offsetIntoBinaryTextSegment: 0x200,
                                    subFrames: nil
                                )
                            ]
                        )
                    ]
                )
            ]

            let flattened = flattenFrames(frames)
            XCTAssertEqual(flattened.count, 3)
            XCTAssertEqual(flattened[0].address, 0x1000)
            XCTAssertEqual(flattened[1].address, 0x2000)
            XCTAssertEqual(flattened[2].address, 0x3000)
        }

        func testFlattenFramesDeduplication() {
            let frames: [Frame] = [
                Frame(
                    address: 0x1000, binaryUUID: "ABC-123", binaryName: "MyApp", offsetIntoBinaryTextSegment: 0x100,
                    subFrames: nil),
                Frame(
                    address: 0x2000, binaryUUID: "ABC-123", binaryName: "MyApp", offsetIntoBinaryTextSegment: 0x100,
                    subFrames: nil),
                Frame(
                    address: 0x5000, binaryUUID: "DEF-456", binaryName: "Foundation",
                    offsetIntoBinaryTextSegment: 0x200, subFrames: nil),
            ]

            let flattened = flattenFrames(frames)
            XCTAssertEqual(flattened.count, 3)

            XCTAssertEqual(flattened[0].binaryUUID, "ABC-123")
            XCTAssertEqual(flattened[1].binaryUUID, "ABC-123")
            XCTAssertEqual(flattened[2].binaryUUID, "DEF-456")
        }

        func testFlattenEmptyFrames() {
            let flattened = flattenFrames([Frame]())
            XCTAssertTrue(flattened.isEmpty)
        }

        func testFlattenFramesPreservesUUID() {
            let frames: [Frame] = [
                Frame(
                    address: 0x1000, binaryUUID: "ABC-123", binaryName: "MyApp",
                    offsetIntoBinaryTextSegment: 0x100,
                    subFrames: [
                        Frame(
                            address: 0x2000, binaryUUID: "DEF-456", binaryName: "Foundation",
                            offsetIntoBinaryTextSegment: 0x200, subFrames: nil)
                    ]),
                Frame(
                    address: 0x3000, binaryUUID: nil, binaryName: "Unknown",
                    offsetIntoBinaryTextSegment: nil, subFrames: nil),
            ]

            let flattened = flattenFrames(frames)
            XCTAssertEqual(flattened.count, 3)
            XCTAssertEqual(flattened[0].binaryUUID, "ABC-123")
            XCTAssertEqual(flattened[1].binaryUUID, "DEF-456")
            XCTAssertNil(flattened[2].binaryUUID)
        }

        // MARK: - Exit Code Parsing

        func testParseExitCodeHex() {
            let code = parseExitCode(from: "Namespace SIGNAL, Code 0xb")
            XCTAssertEqual(code, 0xb)
        }

        func testParseExitCodeHexUpperCase() {
            let code = parseExitCode(from: "Namespace SIGNAL, Code 0X8badf00d")
            XCTAssertEqual(code, 0x8bad_f00d)
        }

        func testParseExitCodeDecimal() {
            let code = parseExitCode(from: "Namespace SIGNAL, Code 5 Trace/BPT trap: 5")
            XCTAssertEqual(code, 5)
        }

        func testParseExitCodeDecimalAtEnd() {
            let code = parseExitCode(from: "Namespace CODESIGNING, Code 1")
            XCTAssertEqual(code, 1)
        }

        func testParseExitCodeNoCode() {
            let code = parseExitCode(from: "Some random termination reason")
            XCTAssertNil(code)
        }

        func testParseExitCodeEmpty() {
            let code = parseExitCode(from: "")
            XCTAssertNil(code)
        }

        // MARK: - Exit Code Parsing (RBSTerminateContext)

        func testParseExitCodeRBSTerminateContext() {
            let code = parseExitCode(
                from:
                    "<RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update-watchdog processVisibility:Foreground>"
            )
            XCTAssertEqual(code, 0x8BAD_F00D)
        }

        func testParseExitCodeRBSTerminateContextWithPrefix() {
            let code = parseExitCode(
                from:
                    "FRONTBOARD 2343432205 <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update-watchdog>"
            )
            XCTAssertEqual(code, 0x8BAD_F00D)
        }

        func testParseExitCodeRBSTerminateContextDecimal() {
            let code = parseExitCode(
                from: "<RBSTerminateContext| domain:10 code:42 explanation:test>"
            )
            XCTAssertEqual(code, 42)
        }

        func testParseExitCodeRBSTerminateContextLowerHex() {
            let code = parseExitCode(
                from: "<RBSTerminateContext| domain:10 code:0xdead>"
            )
            XCTAssertEqual(code, 0xDEAD)
        }

        // MARK: - VM Region Address Parsing

        func testParseVMRegionAddressZero() {
            let addr = parseVMRegionAddress(
                from:
                    "0 is not in any region. Bytes before following region: 4000000000 REGION TYPE START - END"
            )
            XCTAssertEqual(addr, 0)
        }

        func testParseVMRegionAddressHex() {
            let addr = parseVMRegionAddress(from: "0x1234 is not in any region.")
            XCTAssertEqual(addr, 0x1234)
        }

        func testParseVMRegionAddressDecimal() {
            let addr = parseVMRegionAddress(from: "4096 is not in any region.")
            XCTAssertEqual(addr, 4096)
        }

        func testParseVMRegionAddressEmpty() {
            let addr = parseVMRegionAddress(from: "")
            XCTAssertNil(addr)
        }

        // MARK: - OS Version Parsing

        func testParseOSVersionFull() {
            let info = parseOSVersion("iPhone OS 26.2.1 (23C71)")
            XCTAssertEqual(info.name, "iPhone OS")
            XCTAssertEqual(info.version, "26.2.1")
            XCTAssertEqual(info.build, "23C71")
        }

        func testParseOSVersionMacOS() {
            let info = parseOSVersion("macOS 15.1 (24B83)")
            XCTAssertEqual(info.name, "macOS")
            XCTAssertEqual(info.version, "15.1")
            XCTAssertEqual(info.build, "24B83")
        }

        func testParseOSVersionUnparseable() {
            let info = parseOSVersion("17.0")
            XCTAssertNil(info.name)
            XCTAssertEqual(info.version, "17.0")
            XCTAssertNil(info.build)
        }

        func testParseOSVersionEmpty() {
            let info = parseOSVersion("")
            XCTAssertNil(info.name)
            XCTAssertEqual(info.version, "")
            XCTAssertNil(info.build)
        }

        // MARK: - MetricKitRunIdHandler Hash Tests

        func testComputeHashReturnsNonZero() {
            let addresses: [NSNumber] = [0x1000, 0x2000, 0x3000]
            let hash = MetricKitRunIdHandler.computeHash(from: addresses)
            XCTAssertNotEqual(hash, 0)
        }

        func testComputeHashIsConsistent() {
            let addresses: [NSNumber] = [0x1000, 0x2000, 0x3000]
            let hash1 = MetricKitRunIdHandler.computeHash(from: addresses)
            let hash2 = MetricKitRunIdHandler.computeHash(from: addresses)
            XCTAssertEqual(hash1, hash2)
        }

        func testComputeHashDiffersForDifferentAddresses() {
            let addresses1: [NSNumber] = [0x1000, 0x2000, 0x3000]
            let addresses2: [NSNumber] = [0x1000, 0x2000, 0x4000]
            let hash1 = MetricKitRunIdHandler.computeHash(from: addresses1)
            let hash2 = MetricKitRunIdHandler.computeHash(from: addresses2)
            XCTAssertNotEqual(hash1, hash2)
        }

        func testComputeHashDiffersForDifferentOrder() {
            let addresses1: [NSNumber] = [0x1000, 0x2000, 0x3000]
            let addresses2: [NSNumber] = [0x3000, 0x2000, 0x1000]
            let hash1 = MetricKitRunIdHandler.computeHash(from: addresses1)
            let hash2 = MetricKitRunIdHandler.computeHash(from: addresses2)
            XCTAssertNotEqual(hash1, hash2)
        }

        func testComputeHashEmptyArray() {
            let hash = MetricKitRunIdHandler.computeHash(from: [])
            XCTAssertEqual(hash, 0)
        }

        func testComputeHashSingleAddress() {
            let hash = MetricKitRunIdHandler.computeHash(from: [0xDEAD_BEEF])
            XCTAssertNotEqual(hash, 0)
        }

        func testComputeHashLargeAddresses() {
            let addresses: [NSNumber] = [
                NSNumber(value: UInt64.max),
                NSNumber(value: UInt64.max - 1),
                NSNumber(value: UInt64.max - 2),
            ]
            let hash = MetricKitRunIdHandler.computeHash(from: addresses)
            XCTAssertNotEqual(hash, 0)
        }

        // MARK: - MetricKitRunIdHandler Encode Tests

        func testEncodeWritesSidecarFile() {
            let handler = MetricKitRunIdHandler()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            var writtenURL: URL?
            let success = handler.encode(runId: "550e8400e29b41d4a716446655440000") { name, ext in
                let url = tempDir.appendingPathComponent("\(name).\(ext)")
                writtenURL = url
                return url
            }

            XCTAssertTrue(success)
            XCTAssertNotNil(writtenURL)
            if let url = writtenURL {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                let contents = try? String(contentsOf: url, encoding: .utf8)
                XCTAssertEqual(contents, "550e8400e29b41d4a716446655440000")
            }
        }

        func testEncodeStripsHyphens() {
            let handler = MetricKitRunIdHandler()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            var writtenURL: URL?
            let success = handler.encode(runId: "550e8400-e29b-41d4-a716-446655440000") { name, ext in
                let url = tempDir.appendingPathComponent("\(name).\(ext)")
                writtenURL = url
                return url
            }

            XCTAssertTrue(success)
            if let url = writtenURL {
                let contents = try? String(contentsOf: url, encoding: .utf8)
                // The stored runId should be the original with hyphens
                XCTAssertEqual(contents, "550e8400-e29b-41d4-a716-446655440000")
            }
        }

        func testEncodeFailsWhenPathProviderReturnsNil() {
            let handler = MetricKitRunIdHandler()

            let success = handler.encode(runId: "abc123") { _, _ in
                nil
            }

            XCTAssertFalse(success)
        }

        func testEncodeCreatesFileWithStacksymExtension() {
            let handler = MetricKitRunIdHandler()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            var receivedExtension: String?
            _ = handler.encode(runId: UUID().uuidString) { _, ext in
                receivedExtension = ext
                return tempDir.appendingPathComponent("test.\(ext)")
            }

            XCTAssertEqual(receivedExtension, "stacksym")
        }

        func testEncodeUsesHexHashAsFilename() {
            let handler = MetricKitRunIdHandler()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            var receivedName: String?
            _ = handler.encode(runId: UUID().uuidString) { name, ext in
                receivedName = name
                return tempDir.appendingPathComponent("\(name).\(ext)")
            }

            XCTAssertNotNil(receivedName)
            // Name should be a 16-character hex string (64-bit hash)
            if let name = receivedName {
                XCTAssertEqual(name.count, 16)
                XCTAssertTrue(name.allSatisfy { $0.isHexDigit })
            }
        }

        // MARK: - Round Trip Tests

        func testEncodeProducesConsistentHash() {
            let handler = MetricKitRunIdHandler()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            var name1: String?
            var name2: String?

            _ = handler.encode(runId: "550e8400e29b41d4a716446655440000") { name, ext in
                name1 = name
                return tempDir.appendingPathComponent("\(name).\(ext)")
            }

            _ = handler.encode(runId: "550e8400e29b41d4a716446655440000") { name, ext in
                name2 = name
                return tempDir.appendingPathComponent("\(name).\(ext)")
            }

            XCTAssertEqual(name1, name2, "Same run ID should produce same hash filename")
        }

        func testEncodeFailsWithWrongLengthRunId() {
            let handler = MetricKitRunIdHandler()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Too short (not 32 chars after stripping hyphens)
            let success1 = handler.encode(runId: "abc123") { name, ext in
                return tempDir.appendingPathComponent("\(name).\(ext)")
            }
            XCTAssertFalse(success1, "Should fail with run ID shorter than 32 chars")

            // Too long
            let success2 = handler.encode(runId: "550e8400e29b41d4a716446655440000extra") { name, ext in
                return tempDir.appendingPathComponent("\(name).\(ext)")
            }
            XCTAssertFalse(success2, "Should fail with run ID longer than 32 chars")
        }

        func testExpectedFrameCountMatchesUUIDLength() {
            // UUID without hyphens is 32 hex characters
            let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            XCTAssertEqual(uuid.count, MetricKitRunIdHandler.expectedDataFrameCount)
        }

        func testDecodeFindsEncodedRunId() {
            let handler = MetricKitRunIdHandler()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            let runId = UUID().uuidString
            let strippedRunId = runId.replacingOccurrences(of: "-", with: "")

            // Use a separate threadcrumb to get addresses for the same message
            let threadcrumb = KSCrashThreadcrumb(identifier: "test")
            let addresses = threadcrumb.log(strippedRunId)

            XCTAssertEqual(addresses.count, MetricKitRunIdHandler.expectedDataFrameCount)

            // Compute hash and write sidecar manually (simulating what encode does)
            let hash = MetricKitRunIdHandler.computeHash(from: addresses)
            let name = String(format: "%016llx", hash)
            let sidecarURL = tempDir.appendingPathComponent("\(name).stacksym")
            try? runId.write(to: sidecarURL, atomically: true, encoding: .utf8)

            // Create mock CallStackData with 39 frames (4 overhead + 32 data + 3 overhead)
            // Stack layout: indices 0-3 overhead, 4-35 data, 36-38 overhead
            var stackFrames: [StackFrame] = []

            // 4 overhead frames at top (indices 0-3)
            for i in 0..<4 {
                stackFrames.append(
                    StackFrame(
                        instructionAddr: UInt64(0xF000 + i),
                        objectAddr: nil,
                        objectName: "libsystem",
                        objectUUID: "OVERHEAD-UUID"
                    ))
            }

            // 32 data frames (indices 4-35)
            for addr in addresses {
                stackFrames.append(
                    StackFrame(
                        instructionAddr: addr.uint64Value,
                        objectAddr: nil,
                        objectName: "TestBinary",
                        objectUUID: "TEST-UUID-1234"
                    ))
            }

            // 3 overhead frames at bottom (indices 36-38)
            for i in 0..<3 {
                stackFrames.append(
                    StackFrame(
                        instructionAddr: UInt64(0xE000 + i),
                        objectAddr: nil,
                        objectName: "libpthread",
                        objectUUID: "PTHREAD-UUID"
                    ))
            }

            XCTAssertEqual(stackFrames.count, MetricKitRunIdHandler.expectedTotalFrameCount)

            let backtrace = Backtrace(contents: stackFrames, skipped: 0)
            let thread = BasicCrashReport.Thread(
                backtrace: backtrace,
                crashed: false,
                currentThread: false,
                index: 0
            )
            let callStackData = CallStackData(
                threads: [thread],
                crashedThreadIndex: 0,
                binaryImages: []
            )

            // Decode should find the run ID
            let decoded = handler.decode(from: callStackData) { name, ext in
                return tempDir.appendingPathComponent("\(name).\(ext)")
            }

            XCTAssertEqual(decoded, runId, "Decode should return the encoded run ID")
        }

        func testDecodeReturnsNilWhenNoMatchingFrames() {
            let handler = MetricKitRunIdHandler()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create CallStackData with random addresses (no matching sidecar)
            let stackFrames = (0..<32).map { i in
                StackFrame(
                    instructionAddr: UInt64(0x1000 + i),
                    objectAddr: nil,
                    objectName: "TestBinary",
                    objectUUID: "TEST-UUID-1234"
                )
            }
            let backtrace = Backtrace(contents: stackFrames, skipped: 0)
            let thread = BasicCrashReport.Thread(
                backtrace: backtrace,
                crashed: false,
                currentThread: false,
                index: 0
            )
            let callStackData = CallStackData(
                threads: [thread],
                crashedThreadIndex: 0,
                binaryImages: []
            )

            let decoded = handler.decode(from: callStackData) { name, ext in
                return tempDir.appendingPathComponent("\(name).\(ext)")
            }

            XCTAssertNil(decoded, "Decode should return nil when no matching sidecar exists")
        }

        func testDecodeReturnsNilWhenNotEnoughFrames() {
            let handler = MetricKitRunIdHandler()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Create CallStackData with fewer than expectedFrameCount frames
            let stackFrames = (0..<10).map { i in
                StackFrame(
                    instructionAddr: UInt64(0x1000 + i),
                    objectAddr: nil,
                    objectName: "TestBinary",
                    objectUUID: "TEST-UUID-1234"
                )
            }
            let backtrace = Backtrace(contents: stackFrames, skipped: 0)
            let thread = BasicCrashReport.Thread(
                backtrace: backtrace,
                crashed: false,
                currentThread: false,
                index: 0
            )
            let callStackData = CallStackData(
                threads: [thread],
                crashedThreadIndex: 0,
                binaryImages: []
            )

            let decoded = handler.decode(from: callStackData) { name, ext in
                return tempDir.appendingPathComponent("\(name).\(ext)")
            }

            XCTAssertNil(decoded, "Decode should return nil when not enough frames")
        }
    #endif
}
