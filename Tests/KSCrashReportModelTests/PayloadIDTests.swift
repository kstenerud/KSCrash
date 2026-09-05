//
//  PayloadIDTests.swift
//
//  Created by Alexander Cohen on 2026-08-22.
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
import XCTest

@testable import KSCrashReportModel

final class PayloadIDTests: XCTestCase {
    private let text = "4C1B2F3E-0000-4000-8000-000000000001"
    private let canonical = "4c1b2f3e-0000-4000-8000-000000000001"

    func test_init_parsesUUIDsInEitherCase() {
        // Runtime strings go through the failable initializer; only literals trap.
        let malformed = "not-a-uuid"
        let empty = ""
        XCTAssertNotNil(RunSummary.ID(text))
        XCTAssertNotNil(RunSummary.ID(text.lowercased()))
        XCTAssertNil(RunSummary.ID(malformed))
        XCTAssertNil(RunSummary.ID(empty))
    }

    func test_stringLiteral_andLosslessConversion() {
        let literal: RunSummary.ID = "4C1B2F3E-0000-4000-8000-000000000001"
        XCTAssertEqual(literal, RunSummary.ID(text))
        XCTAssertEqual(RunSummary.ID(literal.description), literal, "description round-trips losslessly")
        XCTAssertEqual(RunSummary.ID(uuid: literal.uuid), literal)
    }

    func test_description_isTheLowercaseUUID() {
        // Any input case; the canonical wire and on-disk form is lowercase.
        XCTAssertEqual(RunSummary.ID(text)?.description, canonical)
        XCTAssertEqual(Report.ID(text)?.description, canonical)
    }

    func test_codable_roundTripsTheString() throws {
        let id = try XCTUnwrap(RunSummary.ID(text))
        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(canonical)\"")
        XCTAssertEqual(try JSONDecoder().decode(RunSummary.ID.self, from: data), id)
        // Uppercase wire input decodes, and re-encodes canonical.
        let fromUpper = try JSONDecoder().decode(RunSummary.ID.self, from: Data("\"\(text)\"".utf8))
        XCTAssertEqual(fromUpper, id)
        XCTAssertEqual(String(data: try JSONEncoder().encode(fromUpper), encoding: .utf8), "\"\(canonical)\"")
    }

    func test_decode_rejectsAMalformedID() {
        XCTAssertThrowsError(try JSONDecoder().decode(RunSummary.ID.self, from: Data("\"nope\"".utf8))) {
            XCTAssertTrue($0 is DecodingError)
        }
    }

    func test_runSummary_isIdentifiableByItsRunID() throws {
        let id = try XCTUnwrap(RunSummary.ID(text))
        let summary = RunSummary(
            schemaVersion: 1, sdkVersion: "t", id: id, deviceID: "d", startedAtMs: 1, endedAtMs: 2,
            isBeingDebugged: false, outcome: .init(terminationReason: .clean, userPerceptible: false),
            durations: .init(activeMs: 0, backgroundMs: 0), sessions: .init(records: []),
            app: .init(bundleID: "b", version: "1", shortVersion: "1", hostKind: .app),
            os: .init(name: "o", version: "1", build: "1"),
            device: .init(
                model: "m", modelFamily: "f", architecture: "a", binaryArchitecture: "a",
                isTranslated: false, isJailbroken: false))
        let data = try JSONEncoder().encode(summary)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            json["run_id"] as? String, canonical, "the wire key is unchanged; the text is canonical lowercase")
        XCTAssertEqual(try JSONDecoder().decode(RunSummary.self, from: data).id, id)
    }

    func test_runSummary_withAMalformedRunID_failsDecode() {
        let json = #"{"schema_version": 1, "sdk_version": "t", "run_id": "r", "device_id": "d"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(RunSummary.self, from: Data(json.utf8)))
    }

    // MARK: - Report.ID

    func test_reportID_parsesLiteralsAndRuntimeStrings() throws {
        let literal: Report.ID = "4C1B2F3E-0000-4000-8000-000000000001"
        let malformed = "evt1"
        XCTAssertEqual(Report.ID(text), literal)
        XCTAssertEqual(Report.ID(uuid: literal.uuid), literal)
        XCTAssertEqual(Report.ID(literal.description), literal)
        XCTAssertNil(Report.ID(malformed))
    }

    func test_report_isIdentifiableByItsReportID() throws {
        let json = """
            {"crash": {"error": {"type": "signal"}}, "report": {"id": "\(text)"}}
            """
        let report = try JSONDecoder().decode(Report.self, from: Data(json.utf8))
        XCTAssertEqual(report.id, Report.ID(text))
        XCTAssertEqual(report.report.id, report.id)
        let encoded = try JSONEncoder().encode(report)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(
            (object["report"] as? [String: Any])?["id"] as? String, canonical, "the wire text is canonical lowercase")
    }

    func test_report_withAMalformedID_failsDecode() {
        let json = #"{"crash": {"error": {"type": "signal"}}, "report": {"id": "evt1"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Report.self, from: Data(json.utf8))) {
            XCTAssertTrue($0 is DecodingError)
        }
    }
}
