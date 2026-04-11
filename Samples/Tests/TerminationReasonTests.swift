//
//  TerminationReasonTests.swift
//
//  Created by Alexander Cohen on 2026-03-15.
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
import KSCrashRecording
import XCTest

#if !os(watchOS)

    final class TerminationReasonTests: IntegrationTestBase {

        // MARK: - Lifecycle-based

        func testFirstLaunch() throws {
            try launchAndInstall()
            let state = try readState()
            XCTAssertFalse(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .firstLaunch)
        }

        func testUnexplainedKill() throws {
            try launchAndSigkill()

            try launchAndInstall()
            let state = try readState()
            XCTAssertTrue(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .unexplained)
        }

        // MARK: - Resource-based

        func testMemoryPressureKill() throws {
            try launchAndSigkill(env: [
                "KSCRASH_TEST_MEMORY_PRESSURE": "3"
            ])

            try launchAndInstall()
            let state = try readState()
            XCTAssertTrue(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .memoryPressure)
        }

        func testThermalKill() throws {
            try launchAndSigkill(env: [
                "KSCRASH_TEST_THERMAL_STATE": "3"
            ])

            try launchAndInstall()
            let state = try readState()
            XCTAssertTrue(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .thermal)
        }

        func testCPUKill() throws {
            try launchAndSigkill(env: [
                "KSCRASH_TEST_CPU_STATE": "2",
                "KSCRASH_TEST_CPU_USER": "900",
                "KSCRASH_TEST_CPU_CORES": "1",
            ])

            try launchAndInstall()
            let state = try readState()
            XCTAssertTrue(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .CPU)
        }

        #if os(iOS)
            func testLowBatteryKill() throws {
                try launchAndSigkill(env: [
                    "KSCRASH_TEST_BATTERY_LEVEL": "1",
                    "KSCRASH_TEST_BATTERY_STATE": "1",
                ])

                try launchAndInstall()
                let state = try readState()
                XCTAssertTrue(state.crashedLastLaunch)
                XCTAssertEqual(state.terminationReason, .lowBattery)
            }
        #endif

        // MARK: - System change

        func testOSUpgrade() throws {
            try launchAndSigkill(env: [
                "KSCRASH_TEST_SYSTEM_VERSION": "0.0.0"
            ])

            try launchAndInstall()
            let state = try readState()
            XCTAssertFalse(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .osUpgrade)
        }

        func testAppUpgrade() throws {
            try launchAndSigkill(env: [
                "KSCRASH_TEST_BUNDLE_VERSION": "0.0.0"
            ])

            try launchAndInstall()
            let state = try readState()
            XCTAssertFalse(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .appUpgrade)
        }

        func testReboot() throws {
            try launchAndSigkill(env: [
                "KSCRASH_TEST_BOOT_TIMESTAMP": "1"
            ])

            // The current run also needs a boot timestamp for the comparison.
            // BootTimeMonitor sets it via notifyPostSystemEnable, which runs
            // after ksruncontext_init, so we override it here too with a value
            // that differs by more than the 30s jitter threshold.
            app.launchEnvironment["KSCRASH_TEST_BOOT_TIMESTAMP"] = "1000000"
            try launchAndInstall()
            app.launchEnvironment.removeValue(forKey: "KSCRASH_TEST_BOOT_TIMESTAMP")
            let state = try readState()
            XCTAssertFalse(state.crashedLastLaunch)
            XCTAssertEqual(state.terminationReason, .reboot)
        }
    }

#endif
