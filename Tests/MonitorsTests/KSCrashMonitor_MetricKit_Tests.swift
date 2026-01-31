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
    #endif
}
