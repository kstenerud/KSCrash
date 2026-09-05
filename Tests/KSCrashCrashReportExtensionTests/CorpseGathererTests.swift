//
//  CorpseGathererTests.swift
//
//  Created by Alexander Cohen on 2026-06-28.
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
import Foundation
import KSCrashReportModel
import XCTest

@testable import KSCrashCrashReportExtension

final class CorpseGathererTests: XCTestCase {

    // Gathering against our own task exercises every task_info read the corpse path uses. The kcdata
    // is the one piece that needs a real corpse (a live task exposes none), so crashInfo is nil here.
    func testGatherFromOwnTask() {
        let snapshot = CorpseGatherer.gather(corpse: mach_task_self_, exception: EXC_BAD_ACCESS, images: [])

        XCTAssertEqual(snapshot.exception, .EXC_BAD_ACCESS)
        XCTAssertNil(snapshot.crashInfo, "a live task has no corpse kcdata")

        XCTAssertNotNil(snapshot.vmInfo)
        XCTAssertGreaterThan(snapshot.vmInfo?.residentSize ?? 0, 0)
        XCTAssertNotNil(snapshot.basicInfo)
        XCTAssertNotNil(snapshot.events)
        XCTAssertNotNil(snapshot.power)
        // kstaskrole_forTask is a platform stub on tvOS and watchOS (KSTaskRole.c), so the
        // gatherer records nil there by design.
        #if !os(tvOS) && !os(watchOS)
            XCTAssertNotNil(snapshot.taskRole)
        #endif
        // kcdata-sourced sections need a real corpse, like crashInfo above.
        XCTAssertNil(snapshot.rusage)
        XCTAssertNil(snapshot.ledgers)
    }

    func testSnapshotEncodesAndRoundTrips() throws {
        let image = CorpseSnapshot.Image(
            path: "/usr/lib/libfoo.dylib", uuid: "11111111-2222-3333-4444-555555555555",
            baseAddress: 0x1_0000, size: 0x4000, cpuType: 0x0100_000C, cpuSubType: 0)
        let snapshot = CorpseGatherer.gather(corpse: mach_task_self_, exception: EXC_CRASH, images: [image])

        let data = try JSONEncoder().encode(snapshot)
        XCTAssertGreaterThan(data.count, 0)

        let decoded = try JSONDecoder().decode(CorpseSnapshot.self, from: data)
        XCTAssertEqual(decoded.exception, .EXC_CRASH)
        XCTAssertEqual(decoded.images.count, 1)
        XCTAssertEqual(decoded.images.first?.path, "/usr/lib/libfoo.dylib")
        XCTAssertEqual(decoded.vmInfo?.residentSize, snapshot.vmInfo?.residentSize)
    }
}
