//
//  BinaryImageTests.swift
//
//  Created by Gleb Linnik on 2025-04-11.
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
import IntegrationTestsHelper
import XCTest

final class BinaryImageTests: IntegrationTestBase {
    func testBinaryImagesPresent() throws {
        try launchAndCrash(.nsException_genericNSException)

        let rawReport = try readPartialCrashReport()
        try rawReport.validate()

        let binaryImages = rawReport.binary_images ?? rawReport.report?.binary_images
        XCTAssertNotNil(binaryImages, "Binary images section should be present in the crash report")
        XCTAssertGreaterThan(binaryImages?.count ?? 0, 0, "Binary images list should not be empty")

        let mainExecutable = binaryImages?.first(where: { $0.name?.contains("Sample") ?? false })
        XCTAssertNotNil(mainExecutable, "Main executable should be present in binary images")

        let anyImage = binaryImages?.first
        XCTAssertNotNil(anyImage?.image_addr, "Binary image should have image_addr")
        XCTAssertNotNil(anyImage?.image_size, "Binary image should have image_size")
        XCTAssertNotNil(anyImage?.name, "Binary image should have name")
        XCTAssertNotNil(anyImage?.uuid, "Binary image should have uuid")
    }

    func testBinaryImagesContent() throws {
        try launchAndCrash(.nsException_genericNSException)

        let rawReport = try readPartialCrashReport()
        try rawReport.validate()

        let binaryImages = rawReport.binary_images ?? rawReport.report?.binary_images
        guard let images = binaryImages else {
            XCTFail("Binary images should be present")
            return
        }

        // Check critical frameworks that should be present
        let systemFrameworks = ["Foundation", "CoreFoundation", "libobjc.A.dylib", "libSystem"]
        let foundFrameworks = systemFrameworks.filter { framework in
            images.contains { image in
                image.name?.contains(framework) ?? false
            }
        }

        XCTAssertEqual(
            foundFrameworks.count, systemFrameworks.count,
            "All essential system frameworks should be in binary images: \(systemFrameworks)")

        for image in images {
            if let addr = image.image_addr {
                XCTAssertNotEqual(addr, 0, "Image address should not be zero")
            }

            if let size = image.image_size {
                XCTAssertGreaterThan(
                    size, 0, "Image size should be greater than 0 for \(image.name ?? "unknown")")
            }

            if let uuid = image.uuid, !uuid.isEmpty {
                XCTAssertTrue(
                    uuid.count > 8,
                    "UUID should be properly formatted for \(image.name ?? "unknown")")
            }
        }
    }
}
