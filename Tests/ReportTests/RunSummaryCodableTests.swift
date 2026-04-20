//
//  RunSummaryCodableTests.swift
//
//  Created by Alexander Cohen on 2026-04-19.
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
import KSCrashRecording
import XCTest

@testable import Report

final class RunSummaryCodableTests: XCTestCase {
    // MARK: - Helpers

    private func makeSummary(
        userID: String? = "bob",
        userIDsPerceptible: [String] = ["alice", "bob"],
        userIDsImperceptible: [String] = ["bob"],
        terminationReason: KSCrashRecording.TerminationReason = .clean,
        hostKind: RunSummary.HostKind = .app
    ) -> RunSummary {
        let outcome = RunSummary.Outcome(
            terminationReason: terminationReason,
            cleanShutdown: true,
            fatalReported: false,
            userPerceptible: true)
        let durations = RunSummary.Durations(activeMs: 123_456, backgroundMs: 45_678)
        let sessions = RunSummary.Sessions(perceptibleCount: 3, imperceptibleCount: 2)
        let userIDs = RunSummary.UserIDs(perceptible: userIDsPerceptible, imperceptible: userIDsImperceptible)
        let app = RunSummary.App(
            bundleID: "com.acme.app",
            version: "2.6.0.1234",
            shortVersion: "2.6.0",
            hostKind: hostKind)
        let os = RunSummary.OS(name: "iOS", version: "18.0", build: "22A348")
        let device = RunSummary.Device(
            model: "iPhone17,1",
            modelFamily: "iPhone",
            architecture: "arm64e",
            binaryArchitecture: "arm64e",
            isTranslated: false,
            isJailbroken: false)
        return RunSummary(
            schemaVersion: 1,
            sdkVersion: "2.6.0-beta.1",
            runID: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            deviceID: "0123456789abcdef",
            userID: userID,
            userIDs: userIDs,
            startedAtMs: 1_744_000_000_000,
            endedAtMs: 1_744_000_180_000,
            outcome: outcome,
            durations: durations,
            sessions: sessions,
            app: app,
            os: os,
            device: device)
    }

    private func asJSONObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Roundtrip

    func test_roundtrip_preservesAllFields() throws {
        let original = makeSummary()
        let data = try original.jsonData()
        let decoded = try RunSummary.decode(from: data)

        XCTAssertEqual(decoded.schemaVersion, original.schemaVersion)
        XCTAssertEqual(decoded.sdkVersion, original.sdkVersion)
        XCTAssertEqual(decoded.runID, original.runID)
        XCTAssertEqual(decoded.deviceID, original.deviceID)
        XCTAssertEqual(decoded.userID, original.userID)
        XCTAssertEqual(decoded.userIDs.perceptible, original.userIDs.perceptible)
        XCTAssertEqual(decoded.userIDs.imperceptible, original.userIDs.imperceptible)
        XCTAssertEqual(decoded.startedAtMs, original.startedAtMs)
        XCTAssertEqual(decoded.endedAtMs, original.endedAtMs)
        XCTAssertEqual(decoded.outcome.terminationReason, original.outcome.terminationReason)
        XCTAssertEqual(decoded.outcome.cleanShutdown, original.outcome.cleanShutdown)
        XCTAssertEqual(decoded.outcome.fatalReported, original.outcome.fatalReported)
        XCTAssertEqual(decoded.outcome.userPerceptible, original.outcome.userPerceptible)
        XCTAssertEqual(decoded.durations.activeMs, original.durations.activeMs)
        XCTAssertEqual(decoded.durations.backgroundMs, original.durations.backgroundMs)
        XCTAssertEqual(decoded.sessions.perceptibleCount, original.sessions.perceptibleCount)
        XCTAssertEqual(decoded.sessions.imperceptibleCount, original.sessions.imperceptibleCount)
        XCTAssertEqual(decoded.app.bundleID, original.app.bundleID)
        XCTAssertEqual(decoded.app.version, original.app.version)
        XCTAssertEqual(decoded.app.shortVersion, original.app.shortVersion)
        XCTAssertEqual(decoded.app.hostKind, original.app.hostKind)
        XCTAssertEqual(decoded.os.name, original.os.name)
        XCTAssertEqual(decoded.os.version, original.os.version)
        XCTAssertEqual(decoded.os.build, original.os.build)
        XCTAssertEqual(decoded.device.model, original.device.model)
        XCTAssertEqual(decoded.device.modelFamily, original.device.modelFamily)
        XCTAssertEqual(decoded.device.architecture, original.device.architecture)
        XCTAssertEqual(decoded.device.binaryArchitecture, original.device.binaryArchitecture)
        XCTAssertEqual(decoded.device.isTranslated, original.device.isTranslated)
        XCTAssertEqual(decoded.device.isJailbroken, original.device.isJailbroken)
    }

    func test_roundtrip_nilUserID() throws {
        let original = makeSummary(userID: nil)
        let data = try original.jsonData()
        let decoded = try RunSummary.decode(from: data)
        XCTAssertNil(decoded.userID)
    }

    // MARK: - Wire format

    func test_wireFormat_usesSnakeCaseKeys() throws {
        let data = try makeSummary().jsonData()
        let json = try asJSONObject(data)

        XCTAssertNotNil(json["schema_version"])
        XCTAssertNotNil(json["sdk_version"])
        XCTAssertNotNil(json["run_id"])
        XCTAssertNotNil(json["device_id"])
        XCTAssertNotNil(json["user_id"])
        XCTAssertNotNil(json["user_ids"])
        XCTAssertNotNil(json["started_at_ms"])
        XCTAssertNotNil(json["ended_at_ms"])
        XCTAssertNotNil(json["durations_ms"])

        let outcome = try XCTUnwrap(json["outcome"] as? [String: Any])
        XCTAssertNotNil(outcome["termination_reason"])
        XCTAssertNotNil(outcome["clean_shutdown"])
        XCTAssertNotNil(outcome["fatal_reported"])
        XCTAssertNotNil(outcome["user_perceptible"])

        let sessions = try XCTUnwrap(json["sessions"] as? [String: Any])
        XCTAssertNotNil(sessions["perceptible_count"])
        XCTAssertNotNil(sessions["imperceptible_count"])

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

    func test_wireFormat_terminationReasonIsSnakeCaseString() throws {
        let data = try makeSummary(terminationReason: .osUpgrade).jsonData()
        let json = try asJSONObject(data)
        let outcome = try XCTUnwrap(json["outcome"] as? [String: Any])
        XCTAssertEqual(outcome["termination_reason"] as? String, "os_upgrade")
    }

    func test_wireFormat_hostKindIsLowercaseString() throws {
        let data = try makeSummary(hostKind: .extension).jsonData()
        let json = try asJSONObject(data)
        let app = try XCTUnwrap(json["app"] as? [String: Any])
        XCTAssertEqual(app["host_kind"] as? String, "extension")
    }

    // MARK: - Anonymous sentinel bridging

    func test_wireFormat_anonymousSentinelSerializesToNull() throws {
        let objcArray = ["alice", KSCrashRunSummaryAnonymousUserID, "bob"]
        let summary = makeSummary(userIDsPerceptible: objcArray, userIDsImperceptible: [])
        let data = try summary.jsonData()
        let json = try asJSONObject(data)
        let userIDs = try XCTUnwrap(json["user_ids"] as? [String: Any])
        let perceptible = try XCTUnwrap(userIDs["perceptible"] as? [Any])

        XCTAssertEqual(perceptible.count, 3)
        XCTAssertEqual(perceptible[0] as? String, "alice")
        XCTAssertTrue(perceptible[1] is NSNull, "Anonymous slot should serialize as JSON null")
        XCTAssertEqual(perceptible[2] as? String, "bob")
    }

    func test_roundtrip_anonymousSentinelPreserved() throws {
        let objcArray = ["alice", KSCrashRunSummaryAnonymousUserID, "bob"]
        let original = makeSummary(userIDsPerceptible: objcArray, userIDsImperceptible: [])
        let data = try original.jsonData()
        let decoded = try RunSummary.decode(from: data)

        XCTAssertEqual(decoded.userIDs.perceptible.count, 3)
        XCTAssertEqual(decoded.userIDs.perceptible[0], "alice")
        // Identity comparison: the decoder should produce the same pointer as the
        // file-level constant, not a fresh equal string.
        XCTAssertTrue(
            decoded.userIDs.perceptible[1] == KSCrashRunSummaryAnonymousUserID,
            "Decoded anonymous slot should be the sentinel constant pointer")
        XCTAssertEqual(decoded.userIDs.perceptible[2], "bob")
    }

    // MARK: - Unknown tolerance

    func test_decode_unknownTerminationReasonFallsBackToNone() throws {
        let jsonString = """
            {
              "schema_version": 1,
              "sdk_version": "2.6.0-beta.1",
              "run_id": "r",
              "device_id": "d",
              "user_id": null,
              "user_ids": { "perceptible": [], "imperceptible": [] },
              "started_at_ms": 0,
              "ended_at_ms": 0,
              "outcome": {
                "termination_reason": "some_future_reason",
                "clean_shutdown": false,
                "fatal_reported": false,
                "user_perceptible": false
              },
              "durations_ms": { "active": 0, "background": 0 },
              "sessions": { "perceptible_count": 0, "imperceptible_count": 0 },
              "app": { "bundle_id": "x", "version": "1", "short_version": "1", "host_kind": "app" },
              "os": { "name": "iOS", "version": "18", "build": "X" },
              "device": {
                "model": "x", "model_family": "x",
                "architecture": "arm64", "binary_architecture": "arm64",
                "is_translated": false, "is_jailbroken": false
              }
            }
            """
        let data = Data(jsonString.utf8)
        let decoded = try RunSummary.decode(from: data)
        XCTAssertEqual(decoded.outcome.terminationReason, .none)
    }
}
