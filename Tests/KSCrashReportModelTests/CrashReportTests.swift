//
//  CrashReportTests.swift
//
//  Created by Alexander Cohen on 2024-12-09.
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

import KSCrashReportModel
import XCTest

final class CrashReportTests: XCTestCase {
    func testCrashErrorTypeRawValues() {
        XCTAssertEqual(CrashErrorType.mach.rawValue, "mach")
        XCTAssertEqual(CrashErrorType.signal.rawValue, "signal")
        XCTAssertEqual(CrashErrorType.nsexception.rawValue, "nsexception")
        XCTAssertEqual(CrashErrorType.cppException.rawValue, "cpp_exception")
        XCTAssertEqual(CrashErrorType.deadlock.rawValue, "deadlock")
        XCTAssertEqual(CrashErrorType.user.rawValue, "user")
        XCTAssertEqual(CrashErrorType.termination.rawValue, "termination")
        XCTAssertEqual(CrashErrorType(rawValue: "memory_termination"), .termination)
        XCTAssertEqual(CrashErrorType(rawValue: "resource_termination"), .termination)
        XCTAssertEqual(CrashErrorType.hang.rawValue, "hang")
        XCTAssertEqual(CrashErrorType.profile.rawValue, "profile")
    }

    func testTerminationReasonRawValues() {
        XCTAssertEqual(TerminationReason.none.rawValue, "none")
        XCTAssertEqual(TerminationReason.clean.rawValue, "clean")
        XCTAssertEqual(TerminationReason.crash.rawValue, "crash")
        XCTAssertEqual(TerminationReason.hang.rawValue, "hang")
        XCTAssertEqual(TerminationReason.firstLaunch.rawValue, "first_launch")
        XCTAssertEqual(TerminationReason.lowBattery.rawValue, "low_battery")
        XCTAssertEqual(TerminationReason.memoryLimit.rawValue, "memory_limit")
        XCTAssertEqual(TerminationReason.memoryPressure.rawValue, "memory_pressure")
        XCTAssertEqual(TerminationReason.thermal.rawValue, "thermal")
        XCTAssertEqual(TerminationReason.cpu.rawValue, "cpu")
        XCTAssertEqual(TerminationReason.osUpgrade.rawValue, "os_upgrade")
        XCTAssertEqual(TerminationReason.appUpgrade.rawValue, "app_upgrade")
        XCTAssertEqual(TerminationReason.reboot.rawValue, "reboot")
        XCTAssertEqual(TerminationReason.unexplained.rawValue, "unexplained")
    }

    func testTerminationReasonUnknown() {
        let unknown = TerminationReason(rawValue: "some_future_reason")
        XCTAssertEqual(unknown.rawValue, "some_future_reason")
        XCTAssertTrue(unknown.isUnknown)
        XCTAssertFalse(TerminationReason.memoryLimit.isUnknown)
    }

    func testCrashErrorTypeUnknown() {
        let unknown = CrashErrorType(rawValue: "some_future_type")
        XCTAssertEqual(unknown.rawValue, "some_future_type")
    }

    func testCrashErrorSubtypeRawValues() {
        XCTAssertEqual(CrashErrorSubtype.hang.rawValue, "hang")
        XCTAssertEqual(CrashErrorSubtype(rawValue: "hang"), .hang)
    }

    func testCrashErrorSubtypeUnknown() {
        let unknown = CrashErrorSubtype(rawValue: "some_future_subtype")
        XCTAssertEqual(unknown.rawValue, "some_future_subtype")
        XCTAssertTrue(unknown.isUnknown)
        XCTAssertFalse(CrashErrorSubtype.hang.isUnknown)
    }

    func testCrashErrorSubtypeRoundTrips() throws {
        let error = CrashError(type: .profile, subtype: .hang, isFatal: false)
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(CrashError.self, from: data)
        XCTAssertEqual(decoded.type, .profile)
        XCTAssertEqual(decoded.subtype, .hang)
        XCTAssertEqual(decoded.isFatal, false)
    }

    func testCrashErrorWithoutSubtypeDecodesNil() throws {
        let error = CrashError(type: .signal)
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(CrashError.self, from: data)
        XCTAssertNil(decoded.subtype)
    }

    func testMultiThreadProfileRoundTrips() throws {
        let profile = ProfileInfo(
            name: "com.kscrash.profile.hang",
            id: "11111111-2222-3333-4444-555555555555",
            duration: 1_000_000_000,
            frames: [
                StackFrame(instructionAddr: 0x1000, objectAddr: 0xF00, objectName: "dyld", objectUUID: nil),
                StackFrame(instructionAddr: 0x2000, objectAddr: 0x1E00, objectName: "App", objectUUID: nil),
            ],
            threads: [
                ProfileThread(
                    index: 0, primary: true, name: nil,
                    samples: [ProfileSample(count: 3, frames: [1, 0])]),
                ProfileThread(
                    index: 1, primary: false, name: nil,
                    samples: [ProfileSample(count: 1, frames: [0])]),
            ]
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ProfileInfo.self, from: data)
        XCTAssertEqual(decoded, profile)

        // A hang sample carries a count and no timing.
        let sample = try XCTUnwrap(decoded.threads.first?.samples.first)
        XCTAssertEqual(sample.count, 3)
        XCTAssertNil(sample.timeStartUptime)
        XCTAssertNil(sample.duration)
    }

    func testSingleThreadProfileUsesOneThread() throws {
        // A live time profile is one thread with timed, count-1 samples.
        let profile = ProfileInfo(
            name: "startup",
            id: "AAAA",
            timeStartUptime: 100,
            timeEndUptime: 200,
            duration: 100,
            frames: [StackFrame(instructionAddr: 0x1000)],
            threads: [
                ProfileThread(
                    index: 0, primary: true, name: nil,
                    samples: [ProfileSample(timeStartUptime: 100, timeEndUptime: 110, duration: 10, frames: [0])])
            ]
        )
        let decoded = try JSONDecoder().decode(ProfileInfo.self, from: try JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.threads.count, 1)
        XCTAssertTrue(decoded.threads[0].primary)
        let sample = try XCTUnwrap(decoded.threads[0].samples.first)
        XCTAssertEqual(sample.count, 1)
        XCTAssertEqual(sample.duration, 10)
    }

    func testReportTypeRawValues() {
        XCTAssertEqual(ReportType.standard.rawValue, "standard")
        XCTAssertEqual(ReportType.minimal.rawValue, "minimal")
        XCTAssertEqual(ReportType.custom.rawValue, "custom")
    }

    func testBuildTypeRawValues() {
        XCTAssertEqual(BuildType.simulator.rawValue, "simulator")
        XCTAssertEqual(BuildType.debug.rawValue, "debug")
        XCTAssertEqual(BuildType.release.rawValue, "release")
        XCTAssertEqual(BuildType.test.rawValue, "test")
        XCTAssertEqual(BuildType.appStore.rawValue, "app store")
        XCTAssertEqual(BuildType(rawValue: "something").rawValue, "something")
    }
}
