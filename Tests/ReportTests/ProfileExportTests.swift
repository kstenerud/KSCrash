//
//  ProfileExportTests.swift
//
//  Created by Alexander Cohen on 2025-01-06.
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

import Report
import XCTest

final class ProfileExportTests: XCTestCase {

    // MARK: - Test Data

    private func makeTestProfileJSON() -> Data {
        let json = """
            {
                "name": "TestProfile",
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "time_start_epoch": 1704067200000000000,
                "time_start_uptime": 1000000000,
                "time_end_uptime": 1100000000,
                "expected_sample_interval": 10000000,
                "duration": 100000000,
                "time_units": "nanoseconds",
                "frames": [
                    {
                        "instruction_addr": 4295000064,
                        "object_addr": 4294967296,
                        "object_name": "TestApp",
                        "symbol_addr": 4295000000,
                        "symbol_name": "main"
                    },
                    {
                        "instruction_addr": 4295001024,
                        "object_addr": 4294967296,
                        "object_name": "TestApp",
                        "symbol_addr": 4295001000,
                        "symbol_name": "doWork"
                    },
                    {
                        "instruction_addr": 4295002048,
                        "object_addr": 4294967296,
                        "object_name": "libsystem",
                        "symbol_addr": 4295002000,
                        "symbol_name": "sleep"
                    }
                ],
                "samples": [
                    {
                        "time_start_uptime": 1010000000,
                        "time_end_uptime": 1010000100,
                        "duration": 100,
                        "frames": [0, 1]
                    },
                    {
                        "time_start_uptime": 1020000000,
                        "time_end_uptime": 1020000100,
                        "duration": 100,
                        "frames": [0, 1, 2]
                    },
                    {
                        "time_start_uptime": 1030000000,
                        "time_end_uptime": 1030000100,
                        "duration": 100,
                        "frames": [0, 1]
                    }
                ]
            }
            """
        return json.data(using: .utf8)!
    }

    private func decodeTestProfile() throws -> ProfileInfo {
        let data = makeTestProfileJSON()
        return try JSONDecoder().decode(ProfileInfo.self, from: data)
    }

    // MARK: - Speedscope Structure Tests

    func testSpeedscopeValueUnitRawValues() {
        XCTAssertEqual(Speedscope.ValueUnit.bytes.rawValue, "bytes")
        XCTAssertEqual(Speedscope.ValueUnit.microseconds.rawValue, "microseconds")
        XCTAssertEqual(Speedscope.ValueUnit.milliseconds.rawValue, "milliseconds")
        XCTAssertEqual(Speedscope.ValueUnit.nanoseconds.rawValue, "nanoseconds")
        XCTAssertEqual(Speedscope.ValueUnit.none.rawValue, "none")
        XCTAssertEqual(Speedscope.ValueUnit.seconds.rawValue, "seconds")
    }

    func testSpeedscopeProfileTypeRawValues() {
        XCTAssertEqual(Speedscope.ProfileType.evented.rawValue, "evented")
        XCTAssertEqual(Speedscope.ProfileType.sampled.rawValue, "sampled")
    }

    // MARK: - ProfileInfo Export Tests

    func testToSpeedscopeStructure() throws {
        let profile = try decodeTestProfile()
        let speedscope = profile.toSpeedscope()

        XCTAssertEqual(speedscope.name, "TestProfile")
        XCTAssertEqual(speedscope.exporter, "KSCrash Profiler")
        XCTAssertEqual(speedscope.schema, "https://www.speedscope.app/file-format-schema.json")
        XCTAssertEqual(speedscope.activeProfileIndex, 0)
        XCTAssertEqual(speedscope.profiles.count, 1)
    }

    func testToSpeedscopeFrames() throws {
        let profile = try decodeTestProfile()
        let speedscope = profile.toSpeedscope()

        XCTAssertEqual(speedscope.shared.frames.count, 3)

        XCTAssertEqual(speedscope.shared.frames[0].name, "main")
        XCTAssertEqual(speedscope.shared.frames[0].file, "TestApp")

        XCTAssertEqual(speedscope.shared.frames[1].name, "doWork")
        XCTAssertEqual(speedscope.shared.frames[1].file, "TestApp")

        XCTAssertEqual(speedscope.shared.frames[2].name, "sleep")
        XCTAssertEqual(speedscope.shared.frames[2].file, "libsystem")
    }

    func testToSpeedscopeProfile() throws {
        let profile = try decodeTestProfile()
        let speedscope = profile.toSpeedscope()

        let speedscopeProfile = speedscope.profiles[0]

        XCTAssertEqual(speedscopeProfile.type, .sampled)
        XCTAssertEqual(speedscopeProfile.name, "TestProfile")
        XCTAssertEqual(speedscopeProfile.unit, .nanoseconds)
        XCTAssertEqual(speedscopeProfile.startValue, 1_000_000_000)
        XCTAssertEqual(speedscopeProfile.endValue, 1_100_000_000)
    }

    func testToSpeedscopeSamples() throws {
        let profile = try decodeTestProfile()
        let speedscope = profile.toSpeedscope()

        let speedscopeProfile = speedscope.profiles[0]

        XCTAssertEqual(speedscopeProfile.samples.count, 3)
        // Frames are reversed for proper Speedscope stack representation (root at index 0)
        XCTAssertEqual(speedscopeProfile.samples[0], [1, 0])
        XCTAssertEqual(speedscopeProfile.samples[1], [2, 1, 0])
        XCTAssertEqual(speedscopeProfile.samples[2], [1, 0])

        XCTAssertEqual(speedscopeProfile.weights.count, 3)
        // All weights should be expectedSampleInterval (10000000 ns)
        XCTAssertEqual(speedscopeProfile.weights[0], 10_000_000)
        XCTAssertEqual(speedscopeProfile.weights[1], 10_000_000)
        XCTAssertEqual(speedscopeProfile.weights[2], 10_000_000)
    }

    func testExportToSpeedscopeJSON() throws {
        let profile = try decodeTestProfile()
        let data = try profile.exportToSpeedscope()

        XCTAssertFalse(data.isEmpty)

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)

        // Verify schema
        XCTAssertEqual(json?["$schema"] as? String, "https://www.speedscope.app/file-format-schema.json")

        // Verify name
        XCTAssertEqual(json?["name"] as? String, "TestProfile")
    }

    func testExportToFormat() throws {
        let profile = try decodeTestProfile()
        let data = try profile.export(to: .speedscope)

        XCTAssertFalse(data.isEmpty)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["name"] as? String, "TestProfile")
    }

    func testFrameWithoutSymbolNameUsesAddress() throws {
        let json = """
            {
                "name": "TestProfile",
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "time_start_epoch": 1704067200000000000,
                "time_start_uptime": 1000000000,
                "time_end_uptime": 1100000000,
                "expected_sample_interval": 10000000,
                "duration": 100000000,
                "time_units": "nanoseconds",
                "frames": [
                    {
                        "instruction_addr": 4295000064,
                        "object_addr": 4294967296,
                        "object_name": "TestApp"
                    }
                ],
                "samples": [
                    {
                        "time_start_uptime": 1010000000,
                        "time_end_uptime": 1010000100,
                        "duration": 100,
                        "frames": [0]
                    }
                ]
            }
            """
        let data = json.data(using: .utf8)!
        let profile = try JSONDecoder().decode(ProfileInfo.self, from: data)
        let speedscope = profile.toSpeedscope()

        // Frame should use hex address when symbol name is nil
        XCTAssertEqual(speedscope.shared.frames[0].name, "0x100008000")
        XCTAssertEqual(speedscope.shared.frames[0].file, "TestApp")
    }
}
