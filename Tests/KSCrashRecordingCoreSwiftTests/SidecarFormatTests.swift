//
//  SidecarFormatTests.swift
//
//  Created by Alexander Cohen on 2026-09-28.
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

import Foundation
import KSCrashRecordingCore
import XCTest

/// The sidecar structs and readers as Swift sees them: the same layout the C writers produce, and
/// a file written through `ksfu_mmap` reads back through the typed reader.
final class SidecarFormatTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLayoutMatchesTheCStructs() {
        XCTAssertEqual(MemoryLayout<KSSidecarHeader>.size, 5)
        XCTAssertEqual(MemoryLayout<KSCrash_LifecycleData>.size, 112)
        XCTAssertEqual(MemoryLayout<KSCrash_ResourceData>.size, 136)
        XCTAssertEqual(MemoryLayout<KSCrash_SystemData>.size, 2992)
        XCTAssertEqual(MemoryLayout<KSCrash_HangData>.size, 40)
        XCTAssertEqual(MemoryLayout<KSCrash_LifecycleData>.offset(of: \.cleanExit), 5)
        XCTAssertEqual(MemoryLayout<KSCrash_HangData>.offset(of: \.startTimestamp), 8)
    }

    func testLifecycleRoundTrip() throws {
        let read = try roundTrip(
            KSCrash_LifecycleData.self, magic: 0x6b73_6c63, version: 3, read: kssidecar_readLifecycle
        ) {
            $0.sessionsSinceLaunch = 4
            $0.hostKind = 1
        }
        XCTAssertEqual(read.sessionsSinceLaunch, 4)
        XCTAssertEqual(read.hostKind, 1)
    }

    func testResourceRoundTrip() throws {
        let read = try roundTrip(
            KSCrash_ResourceData.self, magic: 0x6b73_7273, version: 2, read: kssidecar_readResource
        ) {
            $0.memoryFootprint = 1234
            $0.memoryHeadroom = 2
        }
        XCTAssertEqual(read.memoryFootprint, 1234)
        XCTAssertEqual(read.memoryHeadroom, 2)
    }

    func testSystemRoundTrip() throws {
        let read = try roundTrip(KSCrash_SystemData.self, magic: 0x6b73_7973, version: 2, read: kssidecar_readSystem) {
            $0.processID = 77
            $0.isBeingDebugged = 1
        }
        XCTAssertEqual(read.processID, 77)
        XCTAssertEqual(read.isBeingDebugged, 1)
    }

    func testHangRoundTrip() throws {
        let read = try roundTrip(KSCrash_HangData.self, magic: 0x6b73_6873, version: 1, read: kssidecar_readHang) {
            $0.startTimestamp = 99
            $0.recovered = 1
        }
        XCTAssertEqual(read.startTimestamp, 99)
        XCTAssertEqual(read.recovered, 1)
    }

    func testWrongMagicReadsAsUnrecoverable() throws {
        let path = try write(KSCrash_HangData.self, magic: 0x1234_5678, version: 1) { _ in }
        var out = KSCrash_HangData()
        XCTAssertEqual(kssidecar_readHang(path, &out), KSCrashSidecarReadUnrecoverable)
    }

    // MARK: - Helpers

    private struct MapFailed: Error {}

    /// Writes the struct the way a monitor does, through `ksfu_mmap`, and returns its path.
    private func write<T>(_ type: T.Type, magic: Int32, version: UInt8, fill: (inout T) -> Void) throws -> String {
        let path = directory.appendingPathComponent(UUID().uuidString).path
        guard let raw = ksfu_mmap(path, MemoryLayout<T>.size) else { throw MapFailed() }
        let pointer = raw.bindMemory(to: T.self, capacity: 1)
        fill(&pointer.pointee)
        raw.storeBytes(of: KSSidecarHeader(magic: magic, version: version), as: KSSidecarHeader.self)
        ksfu_munmap(raw, MemoryLayout<T>.size)
        return path
    }

    private func roundTrip<T>(
        _ type: T.Type, magic: Int32, version: UInt8,
        read: (UnsafePointer<CChar>?, UnsafeMutablePointer<T>?) -> KSCrashSidecarReadResult,
        fill: (inout T) -> Void
    ) throws -> T {
        let path = try write(type, magic: magic, version: version, fill: fill)
        let out = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { out.deallocate() }
        XCTAssertEqual(read(path, out), KSCrashSidecarReadOK)
        return out.pointee
    }
}
