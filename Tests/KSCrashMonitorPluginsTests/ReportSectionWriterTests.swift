//
//  ReportSectionWriterTests.swift
//
//  Created by Alexander Cohen on 2026-09-29.
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
import KSCrashMonitorPlugins
import KSCrashRecordingCore
import KSCrashReportModel
import XCTest

final class ReportSectionWriterTests: XCTestCase {

    /// Collects what `encode` hands the C writer. The writer's function pointers must be
    /// non-capturing closures, so the collector travels through the writer's context.
    private final class Collector {
        var json: [String: String] = [:]
    }

    private struct Stamp: Codable, Equatable {
        var at: Date
    }

    func testEncodeWritesDatesAsSecondsSince1970() throws {
        let collector = Collector()
        var writer = ReportWriter()
        writer.context = Unmanaged.passUnretained(collector).toOpaque()
        writer.addJSONElement = { writer, name, json, _ in
            let collector = Unmanaged<Collector>.fromOpaque(writer!.pointee.context).takeUnretainedValue()
            collector.json[String(cString: name!)] = String(cString: json!)
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        try withUnsafePointer(to: &writer) { pointer in
            try XCTUnwrap(ReportSectionWriter(pointer)).encode("stamp", Stamp(at: date))
        }

        let json = try XCTUnwrap(collector.json["stamp"])
        let metadata = try JSONDecoder().decode(Metadata.self, from: Data(json.utf8))
        XCTAssertEqual(try metadata.decoded(as: Stamp.self), Stamp(at: date))
    }
}
