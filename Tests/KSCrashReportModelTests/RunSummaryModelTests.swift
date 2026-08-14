//
//  RunSummaryModelTests.swift
//
//  Created by Alexander Cohen on 2026-08-02.
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
import KSCrashReportModel
import XCTest

// Both modules export a `RunSummary`, so qualify by module.
private typealias SwiftRunSummary = KSCrashReportModel.RunSummary
final class RunSummaryModelTests: XCTestCase {
    // MARK: - Helpers

    private func makeSwiftSummary(
        userID: String? = "bob",
        isBeingDebugged: Bool = false,
        terminationReason: KSCrashReportModel.TerminationReason = .clean,
        hostKind: SwiftRunSummary.HostKind = .app,
        records: [SwiftRunSummary.Session] = []
    ) -> SwiftRunSummary {
        SwiftRunSummary(
            schemaVersion: 1,
            sdkVersion: "2.6.0-beta.1",
            runID: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            deviceID: "0123456789abcdef",
            userID: userID,
            startedAtMs: 1_744_000_000_000,
            endedAtMs: 1_744_000_180_000,
            isBeingDebugged: isBeingDebugged,
            outcome: .init(terminationReason: terminationReason, userPerceptible: true),
            durations: .init(activeMs: 123_456, backgroundMs: 45_678),
            sessions: .init(records: records),
            app: .init(
                bundleID: "com.acme.app",
                version: "2.6.0.1234",
                shortVersion: "2.6.0",
                hostKind: hostKind,
                buildType: .appStore),
            os: .init(name: "iOS", version: "18.0", build: "22A348"),
            device: .init(
                model: "iPhone17,1",
                modelFamily: "iPhone",
                architecture: "arm64e",
                binaryArchitecture: "arm64e",
                isTranslated: false,
                isJailbroken: false))
    }

    private func asJSONObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Roundtrip

    func test_roundtrip_preservesAllFields() throws {
        let original = makeSwiftSummary(records: [
            .init(
                sessionID: "F0E1D2C3-B4A5-6879-8A9B-0C1D2E3F4A5B",
                userID: "bob",
                perceptible: true,
                startedAtMs: 1_744_000_000_000,
                endedAtMs: 1_744_000_090_000),
            .init(
                sessionID: "11111111-2222-3333-4444-555555555555",
                userID: nil,
                perceptible: false,
                startedAtMs: 1_744_000_090_000,
                endedAtMs: 1_744_000_180_000),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SwiftRunSummary.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_roundtrip_nilUserID() throws {
        let original = makeSwiftSummary(userID: nil)
        let data = try JSONEncoder().encode(original)
        // Absence is an omitted key, never an empty string.
        let json = try asJSONObject(data)
        XCTAssertNil(json["user_id"])
        let decoded = try JSONDecoder().decode(SwiftRunSummary.self, from: data)
        XCTAssertNil(decoded.userID)
    }

    // MARK: - Wire format

    func test_wireFormat_usesSnakeCaseKeys() throws {
        let data = try JSONEncoder().encode(makeSwiftSummary())
        let json = try asJSONObject(data)

        XCTAssertNotNil(json["schema_version"])
        XCTAssertNotNil(json["sdk_version"])
        XCTAssertNotNil(json["run_id"])
        XCTAssertNotNil(json["device_id"])
        XCTAssertNotNil(json["started_at_ms"])
        XCTAssertNotNil(json["ended_at_ms"])
        XCTAssertNotNil(json["is_being_debugged"])
        XCTAssertNotNil(json["durations_ms"])

        let outcome = try XCTUnwrap(json["outcome"] as? [String: Any])
        XCTAssertNotNil(outcome["termination_reason"])
        XCTAssertNotNil(outcome["user_perceptible"])

        let app = try XCTUnwrap(json["app"] as? [String: Any])
        XCTAssertNotNil(app["bundle_id"])
        XCTAssertNotNil(app["short_version"])
        XCTAssertNotNil(app["host_kind"])

        let device = try XCTUnwrap(json["device"] as? [String: Any])
        XCTAssertNotNil(device["model_family"])
        XCTAssertNotNil(device["binary_architecture"])
        XCTAssertNotNil(device["is_translated"])
        XCTAssertNotNil(device["is_jailbroken"])
    }

    func test_encode_omitsEmptyRecords() throws {
        let data = try JSONEncoder().encode(makeSwiftSummary(records: []))
        let json = try asJSONObject(data)
        let sessions = try XCTUnwrap(json["sessions"] as? [String: Any])
        XCTAssertNil(sessions["records"])
    }

    // MARK: - Absence tolerance and forward compatibility

    private func decode(_ json: String) throws -> SwiftRunSummary {
        try JSONDecoder().decode(SwiftRunSummary.self, from: Data(json.utf8))
    }

    private let minimalJSON = """
        {
          "schema_version": 1,
          "sdk_version": "2.6.0-beta.1",
          "run_id": "r",
          "device_id": "d",
          "started_at_ms": 0,
          "ended_at_ms": 0,
          "outcome": { "termination_reason": "clean", "user_perceptible": false },
          "durations_ms": { "active": 0, "background": 0 },
          "sessions": {},
          "app": { "bundle_id": "x", "version": "1", "short_version": "1", "host_kind": "app" },
          "os": { "name": "iOS", "version": "18", "build": "X" },
          "device": {
            "model": "x", "model_family": "x",
            "architecture": "arm64", "binary_architecture": "arm64",
            "is_translated": false, "is_jailbroken": false
          }
        }
        """

    func test_decode_isBeingDebuggedAbsentDefaultsFalse() throws {
        let decoded = try decode(minimalJSON)
        XCTAssertFalse(decoded.isBeingDebugged)
    }

    func test_decode_recordsAbsentDefaultsEmpty() throws {
        let decoded = try decode(minimalJSON)
        XCTAssertTrue(decoded.sessions.records.isEmpty)
    }

    func test_decode_missingUserIDIsNil() throws {
        let decoded = try decode(minimalJSON)
        XCTAssertNil(decoded.userID)
    }

    func test_decode_missingBuildTypeIsNil() throws {
        let decoded = try decode(minimalJSON)
        XCTAssertNil(decoded.app.buildType)
    }

    func test_decode_buildType() throws {
        let json = minimalJSON.replacingOccurrences(
            of: "\"host_kind\": \"app\"",
            with: "\"host_kind\": \"app\", \"build_type\": \"app store\"")
        let decoded = try decode(json)
        XCTAssertEqual(decoded.app.buildType, .appStore)
    }

    func test_decode_unknownHostKindFallsBack() throws {
        let json = minimalJSON.replacingOccurrences(of: "\"host_kind\": \"app\"", with: "\"host_kind\": \"future\"")
        let decoded = try decode(json)
        XCTAssertEqual(decoded.app.hostKind, .unknown("future"))
    }

    func test_decode_unknownTerminationReasonPreservesValue() throws {
        let json = minimalJSON.replacingOccurrences(
            of: "\"termination_reason\": \"clean\"",
            with: "\"termination_reason\": \"some_future_reason\"")
        let decoded = try decode(json)
        XCTAssertEqual(decoded.outcome.terminationReason, .unknown("some_future_reason"))
    }
}
