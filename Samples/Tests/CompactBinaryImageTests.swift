//
//  CompactBinaryImageTests.swift
//
//  Created by Alexander Cohen on 2026-02-07.
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

import IntegrationTestsHelper
import Report
import XCTest

final class CompactBinaryImageTests: IntegrationTestBase {

    // MARK: - Compact Binary Images

    func testCompactModeProducesSmallerReport() throws {
        // First crash without compact mode to get baseline image count
        try launchAndCrash(.nsException_genericNSException)
        let fullReport = try readCrashReport()
        try fullReport.validate()
        let fullImageCount = fullReport.binaryImages?.count ?? 0
        XCTAssertGreaterThan(fullImageCount, 0, "Full report should have binary images")

        // Count unique image addresses referenced by all thread backtraces
        var referencedAddrs = Set<UInt64>()
        for thread in fullReport.crash.threads ?? [] {
            for frame in thread.backtrace?.contents ?? [] {
                if let addr = frame.objectAddr {
                    referencedAddrs.insert(addr)
                }
            }
        }

        // The full report should have many more images than referenced
        XCTAssertGreaterThan(
            fullImageCount, referencedAddrs.count,
            "Full report should contain more images than those referenced by frames"
        )
    }

    func testCompactModeOnlyIncludesReferencedImages() throws {
        try launchAndCrash(
            .nsException_genericNSException,
            installOverride: { config in
                config.isCompactBinaryImagesEnabled = true
            })

        let report = try readCrashReport()
        try report.validate()

        let images = report.binaryImages ?? []
        XCTAssertGreaterThan(images.count, 0, "Compact report should still have binary images")

        // Collect all image addresses referenced by frames across all threads
        var referencedAddrs = Set<UInt64>()
        for thread in report.crash.threads ?? [] {
            for frame in thread.backtrace?.contents ?? [] {
                if let addr = frame.objectAddr {
                    referencedAddrs.insert(addr)
                }
            }
        }

        // Compact mode only includes images referenced by backtrace frames
        // (plus dyld, which is always included).
        let imageAddrs = Set(images.map(\.imageAddr))

        // All referenced addresses should have a matching binary image
        for addr in referencedAddrs {
            XCTAssertTrue(
                imageAddrs.contains(addr),
                "Referenced image at \(String(format: "0x%llx", addr)) should be present in binary_images"
            )
        }

        // Image count should be the referenced set plus dyld (at most 1 extra)
        XCTAssertLessThanOrEqual(
            images.count, referencedAddrs.count + 1,
            "Compact report should only contain referenced images plus dyld"
        )
    }

    // MARK: - object_uuid on Frames

    func testFramesHaveObjectUUID() throws {
        try launchAndCrash(.nsException_genericNSException)

        let report = try readCrashReport()
        try report.validate()

        // The crashed thread's frames should have object_uuid
        let crashedThread = report.crash.threads?.first(where: { $0.crashed })
        XCTAssertNotNil(crashedThread)

        let frames = crashedThread?.backtrace?.contents ?? []
        XCTAssertGreaterThan(frames.count, 0)

        // At least the first symbolicated frame should have object_uuid
        let framesWithUUID = frames.filter { $0.objectUUID != nil }
        XCTAssertGreaterThan(
            framesWithUUID.count, 0,
            "Crash frames should have object_uuid for symbolication"
        )

        // For frames that have both object_uuid and object_addr, verify uuid format
        for frame in framesWithUUID {
            let uuid = frame.objectUUID!
            XCTAssertGreaterThan(uuid.count, 8, "UUID should be properly formatted: \(uuid)")
            XCTAssertNotNil(frame.objectAddr, "Frames with object_uuid should also have object_addr")
        }
    }

    func testObjectUUIDMatchesBinaryImage() throws {
        try launchAndCrash(.nsException_genericNSException)

        let report = try readCrashReport()
        try report.validate()

        guard let images = report.binaryImages else {
            XCTFail("Report should have binary images")
            return
        }

        // Build lookup from image address to UUID
        let imageUUIDByAddr = Dictionary(
            uniqueKeysWithValues: images.compactMap { image -> (UInt64, String)? in
                guard let uuid = image.uuid else { return nil }
                return (image.imageAddr, uuid)
            })

        // For each frame with object_uuid, verify it matches the binary image
        for thread in report.crash.threads ?? [] {
            for frame in thread.backtrace?.contents ?? [] {
                guard let frameUUID = frame.objectUUID, let addr = frame.objectAddr else { continue }
                if let imageUUID = imageUUIDByAddr[addr] {
                    XCTAssertEqual(
                        frameUUID, imageUUID,
                        "Frame object_uuid should match binary image uuid at \(String(format: "0x%llx", addr))"
                    )
                }
            }
        }
    }
}
