//
//  CrashReportEncodingTests.swift
//
//  Created by Alexander Cohen on 2026-01-31.
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

final class CrashReportEncodingTests: XCTestCase {

    // MARK: - Round-Trip: Example Reports

    func testRoundTripExampleAbort() throws {
        try assertExampleReportRoundTrips("Abort")
    }

    func testRoundTripExampleBadPointer() throws {
        try assertExampleReportRoundTrips("BadPointer")
    }

    func testRoundTripExampleCorruptMemory() throws {
        try assertExampleReportRoundTrips("CorruptMemory")
    }

    func testRoundTripExampleCorruptObject() throws {
        try assertExampleReportRoundTrips("CorruptObject")
    }

    func testRoundTripExampleCrashInHandler() throws {
        try assertExampleReportRoundTrips("CrashInHandler")
    }

    func testRoundTripExampleMainThreadDeadlock() throws {
        try assertExampleReportRoundTrips("MainThreadDeadlock")
    }

    func testRoundTripExampleNSException() throws {
        try assertExampleReportRoundTrips("NSException")
    }

    func testRoundTripExampleStackOverflow() throws {
        try assertExampleReportRoundTrips("StackOverflow")
    }

    func testRoundTripExampleZombie() throws {
        try assertExampleReportRoundTrips("Zombie")
    }

    func testRoundTripExampleZombieNSException() throws {
        try assertExampleReportRoundTrips("ZombieNSException")
    }

    func testRoundTripExampleWatchdogTimeout() throws {
        try assertExampleReportRoundTrips("WatchdogTimeout")
    }

    func testRoundTripExampleHang() throws {
        try assertExampleReportRoundTrips("Hang")
    }

    func testRoundTripExampleProfile() throws {
        try assertExampleReportRoundTrips("Profile")
    }

    // MARK: - Round-Trip: Constructed Reports

    func testRoundTripConstructedMachReport() throws {
        let report = Report(
            binaryImages: [
                BinaryImage(
                    cpuSubtype: 9,
                    cpuType: 12,
                    imageAddr: 0x8000,
                    imageSize: 282624,
                    name: "/path/to/App",
                    uuid: "ABC-123"
                )
            ],
            crash: Report.Crash(
                diagnosis: "Test diagnosis",
                error: CrashError(
                    address: 0xDEAD,
                    mach: MachError(
                        code: 1,
                        codeName: "KERN_INVALID_ADDRESS",
                        exception: 1,
                        exceptionName: "EXC_BAD_ACCESS",
                        subcode: 0x42
                    ),
                    signal: SignalError(
                        code: 0,
                        codeName: "SEGV_MAPERR",
                        name: "SIGSEGV",
                        signal: 11
                    ),
                    type: .mach
                ),
                threads: [
                    Report.Thread(
                        backtrace: Backtrace(
                            contents: [
                                StackFrame(
                                    instructionAddr: 0x1000,
                                    objectAddr: 0x8000,
                                    objectName: "App",
                                    objectUUID: "ABC-123",
                                    symbolAddr: 0x0FF0,
                                    symbolName: "main"
                                ),
                                StackFrame(
                                    instructionAddr: 0x2000,
                                    objectAddr: 0x8000,
                                    objectName: "App"
                                ),
                            ],
                            skipped: 0
                        ),
                        crashed: true,
                        currentThread: true,
                        index: 0
                    ),
                    Report.Thread(
                        crashed: false,
                        currentThread: false,
                        index: 1,
                        name: "worker-thread"
                    ),
                ]
            ),
            report: ReportInfo(
                id: "test-constructed-id",
                processName: "TestApp",
                type: .standard,
                version: ReportVersion(major: 3, minor: 8, patch: 0),
                monitorId: "MetricKit"
            ),
            system: SystemInfo(
                cfBundleExecutable: "TestApp",
                cfBundleIdentifier: "com.test.app",
                cfBundleShortVersionString: "1.0",
                cpuArch: "arm64",
                machine: "iPhone14,2",
                systemName: "iOS",
                systemVersion: "17.0"
            )
        )

        let (original, roundTripped) = try roundTrip(report)

        // Verify report info
        XCTAssertEqual(roundTripped.report.id, "test-constructed-id")
        XCTAssertEqual(roundTripped.report.processName, "TestApp")
        XCTAssertEqual(roundTripped.report.type, .standard)
        XCTAssertEqual(roundTripped.report.version?.major, 3)
        XCTAssertEqual(roundTripped.report.version?.minor, 8)
        XCTAssertEqual(roundTripped.report.version?.patch, 0)
        XCTAssertEqual(roundTripped.report.monitorId, "MetricKit")

        // Verify crash error
        XCTAssertEqual(roundTripped.crash.error.type, original.crash.error.type)
        XCTAssertEqual(roundTripped.crash.error.address, 0xDEAD)
        XCTAssertEqual(roundTripped.crash.error.mach?.code, 1)
        XCTAssertEqual(roundTripped.crash.error.mach?.codeName, "KERN_INVALID_ADDRESS")
        XCTAssertEqual(roundTripped.crash.error.mach?.exception, 1)
        XCTAssertEqual(roundTripped.crash.error.mach?.exceptionName, "EXC_BAD_ACCESS")
        XCTAssertEqual(roundTripped.crash.error.mach?.subcode, 0x42)
        XCTAssertEqual(roundTripped.crash.error.signal?.signal, 11)
        XCTAssertEqual(roundTripped.crash.error.signal?.name, "SIGSEGV")
        XCTAssertEqual(roundTripped.crash.diagnosis, "Test diagnosis")

        // Verify threads
        XCTAssertEqual(roundTripped.crash.threads?.count, 2)
        let thread0 = roundTripped.crash.threads?[0]
        XCTAssertEqual(thread0?.crashed, true)
        XCTAssertEqual(thread0?.currentThread, true)
        XCTAssertEqual(thread0?.index, 0)
        XCTAssertEqual(thread0?.backtrace?.contents.count, 2)
        XCTAssertEqual(thread0?.backtrace?.contents[0].instructionAddr, 0x1000)
        XCTAssertEqual(thread0?.backtrace?.contents[0].objectUUID, "ABC-123")
        XCTAssertEqual(thread0?.backtrace?.contents[0].symbolName, "main")
        XCTAssertNil(thread0?.backtrace?.contents[1].objectUUID)
        XCTAssertEqual(thread0?.backtrace?.skipped, 0)

        let thread1 = roundTripped.crash.threads?[1]
        XCTAssertEqual(thread1?.crashed, false)
        XCTAssertEqual(thread1?.name, "worker-thread")

        // Verify binary images
        XCTAssertEqual(roundTripped.binaryImages?.count, 1)
        XCTAssertEqual(roundTripped.binaryImages?[0].cpuSubtype, 9)
        XCTAssertEqual(roundTripped.binaryImages?[0].cpuType, 12)
        XCTAssertEqual(roundTripped.binaryImages?[0].imageAddr, 0x8000)
        XCTAssertEqual(roundTripped.binaryImages?[0].imageSize, 282624)
        XCTAssertEqual(roundTripped.binaryImages?[0].uuid, "ABC-123")

        // Verify system info
        XCTAssertEqual(roundTripped.system?.cfBundleExecutable, "TestApp")
        XCTAssertEqual(roundTripped.system?.cfBundleIdentifier, "com.test.app")
        XCTAssertEqual(roundTripped.system?.cpuArch, "arm64")
        XCTAssertEqual(roundTripped.system?.machine, "iPhone14,2")
        XCTAssertEqual(roundTripped.system?.systemVersion, "17.0")
    }

    func testRoundTripConstructedSignalReport() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(
                    signal: SignalError(
                        code: 0,
                        name: "SIGABRT",
                        signal: 6
                    ),
                    type: .signal,
                    reason: "abort() called"
                )
            ),
            report: ReportInfo(id: "signal-test")
        )

        let (_, roundTripped) = try roundTrip(report)

        XCTAssertEqual(roundTripped.crash.error.type, .signal)
        XCTAssertEqual(roundTripped.crash.error.signal?.signal, 6)
        XCTAssertEqual(roundTripped.crash.error.signal?.name, "SIGABRT")
        XCTAssertEqual(roundTripped.crash.error.reason, "abort() called")
        XCTAssertNil(roundTripped.crash.error.mach)
    }

    func testRoundTripLastExceptionBacktrace() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(
                    nsexception: ExceptionInfo(name: "NSInvalidArgumentException"),
                    type: .nsexception
                ),
                threads: [
                    Report.Thread(
                        backtrace: Backtrace(
                            contents: [
                                StackFrame(instructionAddr: 0x3000, symbolName: "handleUncaughtException")
                            ],
                            skipped: 0
                        ),
                        crashed: true,
                        currentThread: true,
                        index: 0
                    )
                ],
                lastExceptionBacktrace: Backtrace(
                    contents: [
                        StackFrame(
                            instructionAddr: 0x1000,
                            objectName: "CoreFoundation",
                            symbolName: "__exceptionPreprocess"
                        ),
                        StackFrame(
                            instructionAddr: 0x2000,
                            objectName: "libobjc.A.dylib",
                            symbolName: "objc_exception_throw"
                        ),
                    ],
                    skipped: 0
                )
            ),
            report: ReportInfo(id: "last-exc-bt-test")
        )

        let (_, roundTripped) = try roundTrip(report)

        XCTAssertNotNil(roundTripped.crash.lastExceptionBacktrace)
        XCTAssertEqual(roundTripped.crash.lastExceptionBacktrace?.contents.count, 2)
        XCTAssertEqual(roundTripped.crash.lastExceptionBacktrace?.contents[0].symbolName, "__exceptionPreprocess")
        XCTAssertEqual(roundTripped.crash.lastExceptionBacktrace?.contents[1].symbolName, "objc_exception_throw")
        XCTAssertEqual(roundTripped.crash.lastExceptionBacktrace?.skipped, 0)

        // Thread should have the handler backtrace, not the exception backtrace
        XCTAssertEqual(roundTripped.crash.threads?[0].backtrace?.contents[0].symbolName, "handleUncaughtException")
    }

    func testRoundTripIsFatal() throws {
        let fatal = Report(
            crash: Report.Crash(
                error: CrashError(type: .signal, isFatal: true)
            ),
            report: ReportInfo(id: "fatal-test")
        )
        let (_, roundTrippedFatal) = try roundTrip(fatal)
        XCTAssertEqual(roundTrippedFatal.crash.error.isFatal, true)

        let nonFatal = Report(
            crash: Report.Crash(
                error: CrashError(type: .signal, isFatal: false)
            ),
            report: ReportInfo(id: "non-fatal-test")
        )
        let (_, roundTrippedNonFatal) = try roundTrip(nonFatal)
        XCTAssertEqual(roundTrippedNonFatal.crash.error.isFatal, false)
    }

    func testRoundTripMinimalReport() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(type: .mach)
            ),
            report: ReportInfo(id: "minimal")
        )

        let (_, roundTripped) = try roundTrip(report)

        XCTAssertEqual(roundTripped.report.id, "minimal")
        XCTAssertEqual(roundTripped.crash.error.type, .mach)
        XCTAssertNil(roundTripped.binaryImages)
        XCTAssertNil(roundTripped.system)
        XCTAssertNil(roundTripped.crash.threads)
        XCTAssertNil(roundTripped.crash.diagnosis)
    }

    func testStackFrameObjectUUIDRoundTrip() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(type: .mach),
                threads: [
                    Report.Thread(
                        backtrace: Backtrace(
                            contents: [
                                StackFrame(
                                    instructionAddr: 0x1000,
                                    objectAddr: 0x8000,
                                    objectName: "App",
                                    objectUUID: "AABBCCDD-1122-3344-5566-778899AABBCC"
                                ),
                                StackFrame(
                                    instructionAddr: 0x2000
                                ),
                            ],
                            skipped: 0
                        ),
                        crashed: true,
                        currentThread: true,
                        index: 0
                    )
                ]
            ),
            report: ReportInfo(id: "uuid-test")
        )

        let (_, roundTripped) = try roundTrip(report)

        let frames = roundTripped.crash.threads?[0].backtrace?.contents
        XCTAssertEqual(frames?[0].objectUUID, "AABBCCDD-1122-3344-5566-778899AABBCC")
        XCTAssertEqual(frames?[0].objectName, "App")
        XCTAssertEqual(frames?[0].objectAddr, 0x8000)
        XCTAssertNil(frames?[1].objectUUID)
    }

    func testRoundTripCompactReport() throws {
        // Compact report: only binary images referenced by frames are present.
        // Frames carry object_uuid for self-contained symbolication.
        let appImage = BinaryImage(
            cpuSubtype: 9,
            cpuType: 12,
            imageAddr: 0x100000,
            imageSize: 65536,
            name: "/path/to/App",
            uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )
        let kernelImage = BinaryImage(
            cpuSubtype: 9,
            cpuType: 12,
            imageAddr: 0x200000,
            imageSize: 32768,
            name: "/usr/lib/system/libsystem_kernel.dylib",
            uuid: "11111111-2222-3333-4444-555555555555"
        )

        let report = Report(
            binaryImages: [appImage, kernelImage],
            crash: Report.Crash(
                error: CrashError(type: .mach),
                threads: [
                    Report.Thread(
                        backtrace: Backtrace(
                            contents: [
                                StackFrame(
                                    instructionAddr: 0x100100,
                                    objectAddr: 0x100000,
                                    objectName: "App",
                                    objectUUID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                                    symbolName: "crashFunc"
                                ),
                                StackFrame(
                                    instructionAddr: 0x200080,
                                    objectAddr: 0x200000,
                                    objectName: "libsystem_kernel.dylib",
                                    objectUUID: "11111111-2222-3333-4444-555555555555",
                                    symbolName: "__pthread_kill"
                                ),
                            ],
                            skipped: 0
                        ),
                        crashed: true,
                        currentThread: true,
                        index: 0
                    )
                ]
            ),
            report: ReportInfo(id: "compact-roundtrip")
        )

        let (_, roundTripped) = try roundTrip(report)

        // Verify compact binary images survive round-trip
        XCTAssertEqual(roundTripped.binaryImages?.count, 2)

        // Verify every frame's object_uuid and object_addr survive
        let frames = roundTripped.crash.threads?[0].backtrace?.contents ?? []
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].objectUUID, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(frames[0].objectAddr, 0x100000)
        XCTAssertEqual(frames[1].objectUUID, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(frames[1].objectAddr, 0x200000)

        // Verify the invariant: every frame's object_addr maps to a binary image
        let imageAddrs = Set(roundTripped.binaryImages?.map(\.imageAddr) ?? [])
        for frame in frames {
            if let addr = frame.objectAddr {
                XCTAssertTrue(imageAddrs.contains(addr))
            }
        }
    }

    func testRoundTripResourceFields() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(type: .mach)
            ),
            report: ReportInfo(id: "resource-test"),
            system: SystemInfo(
                batteryLevel: 85,
                batteryState: .charging,
                cpuCoreCount: 8,
                cpuState: .critical,
                cpuTimeInWindow: 48.0,
                cpuWallTimeInWindow: 60.0,
                thermalState: .serious,
                threadCount: 55,
                dataProtectionActive: true
            )
        )

        let (_, roundTripped) = try roundTrip(report)

        XCTAssertEqual(roundTripped.system?.batteryLevel, 85)
        XCTAssertEqual(roundTripped.system?.batteryState, .charging)
        XCTAssertEqual(roundTripped.system?.cpuCoreCount, 8)
        XCTAssertEqual(roundTripped.system?.cpuState, .critical)
        XCTAssertEqual(roundTripped.system?.cpuTimeInWindow, 48.0)
        XCTAssertEqual(roundTripped.system?.cpuWallTimeInWindow, 60.0)
        XCTAssertEqual(roundTripped.system?.thermalState, .serious)
        XCTAssertEqual(roundTripped.system?.threadCount, 55)
        XCTAssertEqual(roundTripped.system?.dataProtectionActive, true)
    }

    func testRoundTripLowPowerMode() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(type: .mach)
            ),
            report: ReportInfo(id: "lpm-test"),
            system: SystemInfo(lowPowerModeEnabled: true)
        )

        let (_, roundTripped) = try roundTrip(report)
        XCTAssertEqual(roundTripped.system?.lowPowerModeEnabled, true)
    }

    func testRoundTripAllBatteryStates() throws {
        for state: BatteryState in [.unknown, .unplugged, .charging, .full] {
            let report = Report(
                crash: Report.Crash(error: CrashError(type: .mach)),
                report: ReportInfo(id: "battery-\(state)"),
                system: SystemInfo(batteryState: state)
            )
            let (_, roundTripped) = try roundTrip(report)
            XCTAssertEqual(roundTripped.system?.batteryState, state, "\(state)")
        }
    }

    func testRoundTripAllThermalStates() throws {
        for state: ThermalState in [.nominal, .fair, .serious, .critical] {
            let report = Report(
                crash: Report.Crash(error: CrashError(type: .mach)),
                report: ReportInfo(id: "thermal-\(state)"),
                system: SystemInfo(thermalState: state)
            )
            let (_, roundTripped) = try roundTrip(report)
            XCTAssertEqual(roundTripped.system?.thermalState, state, "\(state)")
        }
    }

    // MARK: - Encoding Key Verification

    func testEncodingUsesSnakeCaseKeys() throws {
        let report = Report(
            binaryImages: [
                BinaryImage(
                    cpuSubtype: 1,
                    cpuType: 12,
                    imageAddr: 0x1000,
                    imageSize: 4096,
                    name: "test"
                )
            ],
            crash: Report.Crash(
                error: CrashError(type: .mach),
                threads: [
                    Report.Thread(
                        backtrace: Backtrace(
                            contents: [
                                StackFrame(
                                    instructionAddr: 0x1000,
                                    objectUUID: "TEST-UUID"
                                )
                            ],
                            skipped: 0
                        ),
                        crashed: true,
                        currentThread: true,
                        index: 0
                    )
                ],
                crashedThread: Report.Thread(
                    crashed: true,
                    currentThread: true,
                    index: 0
                ),
                lastExceptionBacktrace: Backtrace(
                    contents: [StackFrame(instructionAddr: 0x2000)],
                    skipped: 0
                )
            ),
            report: ReportInfo(
                id: "key-test",
                processName: "Test",
                monitorId: "TestMonitor"
            )
        )

        let data = try JSONEncoder().encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Top-level keys
        XCTAssertNotNil(json["binary_images"])

        // Crash keys
        let crash = json["crash"] as! [String: Any]
        XCTAssertNotNil(crash["crashed_thread"])
        XCTAssertNotNil(crash["last_exception_backtrace"])

        // Thread keys
        let threads = crash["threads"] as! [[String: Any]]
        XCTAssertNotNil(threads[0]["current_thread"])

        // Stack frame keys
        let backtrace = threads[0]["backtrace"] as! [String: Any]
        let frames = backtrace["contents"] as! [[String: Any]]
        XCTAssertNotNil(frames[0]["object_uuid"])
        XCTAssertNotNil(frames[0]["instruction_addr"])

        // Binary image keys
        let images = json["binary_images"] as! [[String: Any]]
        XCTAssertNotNil(images[0]["cpu_subtype"])
        XCTAssertNotNil(images[0]["cpu_type"])
        XCTAssertNotNil(images[0]["image_addr"])
        XCTAssertNotNil(images[0]["image_size"])

        // Report keys
        let reportInfo = json["report"] as! [String: Any]
        XCTAssertNotNil(reportInfo["process_name"])
        XCTAssertNotNil(reportInfo["monitor_id"])

        // Error keys
        let error = crash["error"] as! [String: Any]
        XCTAssertNil(error["isFatal"], "isFatal should be encoded as is_fatal, not isFatal")
        XCTAssertNil(error["isCleanExit"], "isCleanExit should be encoded as is_clean_exit, not isCleanExit")
    }

    func testRoundTripIsCleanExit() throws {
        let clean = Report(
            crash: Report.Crash(
                error: CrashError(type: .signal, isFatal: true, isCleanExit: true)
            ),
            report: ReportInfo(id: "clean-exit-test")
        )
        let (_, roundTrippedClean) = try roundTrip(clean)
        XCTAssertEqual(roundTrippedClean.crash.error.isCleanExit, true)

        let crash = Report(
            crash: Report.Crash(
                error: CrashError(type: .signal, isFatal: true, isCleanExit: false)
            ),
            report: ReportInfo(id: "crash-exit-test")
        )
        let (_, roundTrippedCrash) = try roundTrip(crash)
        XCTAssertEqual(roundTrippedCrash.crash.error.isCleanExit, false)
    }

    func testEncodingIsCleanExitUsesSnakeCaseKey() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(type: .signal, isFatal: true, isCleanExit: true)
            ),
            report: ReportInfo(id: "key-test")
        )

        let data = try JSONEncoder().encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let crashDict = json["crash"] as! [String: Any]
        let error = crashDict["error"] as! [String: Any]
        XCTAssertEqual(error["is_clean_exit"] as? Bool, true)
        XCTAssertNil(error["isCleanExit"], "isCleanExit should be encoded as is_clean_exit, not isCleanExit")
    }

    func testEncodingResourceFieldsUseSnakeCaseKeys() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(type: .mach)
            ),
            report: ReportInfo(id: "key-test"),
            system: SystemInfo(
                lowPowerModeEnabled: false,
                batteryLevel: 50,
                batteryState: .unplugged,
                cpuCoreCount: 4,
                cpuState: .warning,
                cpuTimeInWindow: 95.0,
                cpuWallTimeInWindow: 180.0,
                thermalState: .nominal,
                threadCount: 10,
                dataProtectionActive: false
            )
        )

        let data = try JSONEncoder().encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let system = json["system"] as! [String: Any]

        XCTAssertEqual(system["battery_level"] as? Int, 50)
        XCTAssertEqual(system["battery_state"] as? Int, 1)
        XCTAssertEqual(system["low_power_mode_enabled"] as? Bool, false)
        XCTAssertEqual(system["cpu_core_count"] as? Int, 4)
        XCTAssertEqual(system["cpu_state"] as? String, "warning")
        XCTAssertEqual(system["cpu_time_in_window"] as? Double, 95.0)
        XCTAssertEqual(system["cpu_wall_time_in_window"] as? Double, 180.0)
        XCTAssertEqual(system["thermal_state"] as? Int, 0)
        XCTAssertEqual(system["thread_count"] as? Int, 10)
        XCTAssertEqual(system["data_protection_active"] as? Bool, false)

        // Ensure no camelCase variants leak through
        XCTAssertNil(system["batteryLevel"])
        XCTAssertNil(system["batteryState"])
        XCTAssertNil(system["lowPowerModeEnabled"])
        XCTAssertNil(system["cpuCoreCount"])
        XCTAssertNil(system["cpuState"])
        XCTAssertNil(system["cpuTimeInWindow"])
        XCTAssertNil(system["cpuWallTimeInWindow"])
        XCTAssertNil(system["thermalState"])
        XCTAssertNil(system["threadCount"])
        XCTAssertNil(system["dataProtectionActive"])
    }

    func testRoundTripTermination() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(
                    signal: SignalError(code: 0, name: "SIGKILL", signal: 9),
                    type: .termination,
                    isFatal: true,
                    isCleanExit: false,
                    terminationReason: .memoryLimit
                )
            ),
            report: ReportInfo(
                id: "termination-test",
                type: .standard,
                runId: "prev-run-id",
                monitorId: "Termination"
            )
        )

        let (_, roundTripped) = try roundTrip(report)

        XCTAssertEqual(roundTripped.crash.error.type, .termination)
        XCTAssertEqual(roundTripped.crash.error.terminationReason, .memoryLimit)
        XCTAssertEqual(roundTripped.crash.error.isFatal, true)
        XCTAssertEqual(roundTripped.crash.error.isCleanExit, false)
        XCTAssertEqual(roundTripped.crash.error.signal?.signal, 9)
        XCTAssertEqual(roundTripped.crash.error.signal?.name, "SIGKILL")
        XCTAssertEqual(roundTripped.report.runId, "prev-run-id")
        XCTAssertEqual(roundTripped.report.monitorId, "Termination")
    }

    func testRoundTripSystemChangeTermination() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(
                    type: .termination,
                    isFatal: false,
                    isCleanExit: true,
                    terminationReason: .osUpgrade
                )
            ),
            report: ReportInfo(
                id: "os-upgrade-test",
                type: .standard,
                monitorId: "Termination"
            )
        )

        let (_, roundTripped) = try roundTrip(report)

        XCTAssertEqual(roundTripped.crash.error.type, .termination)
        XCTAssertEqual(roundTripped.crash.error.terminationReason, .osUpgrade)
        XCTAssertEqual(roundTripped.crash.error.isFatal, false)
        XCTAssertEqual(roundTripped.crash.error.isCleanExit, true)
        XCTAssertNil(roundTripped.crash.error.signal)
    }

    func testEncodingTerminationUsesSnakeCaseKeys() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(
                    type: .termination,
                    terminationReason: .thermal
                )
            ),
            report: ReportInfo(id: "key-test")
        )

        let data = try JSONEncoder().encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let crash = json["crash"] as! [String: Any]
        let error = crash["error"] as! [String: Any]

        XCTAssertEqual(error["termination_reason"] as? String, "thermal")
        XCTAssertNil(error["terminationReason"])
    }

    func testEncodingIsFatalUsesSnakeCaseKey() throws {
        let report = Report(
            crash: Report.Crash(
                error: CrashError(type: .signal, isFatal: true)
            ),
            report: ReportInfo(id: "key-test")
        )

        let data = try JSONEncoder().encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let crash = json["crash"] as! [String: Any]
        let error = crash["error"] as! [String: Any]
        XCTAssertEqual(error["is_fatal"] as? Bool, true)
    }

    // MARK: - Helpers

    func testMonitorDataRoundTripsOnBothChannels() throws {
        var section = Metadata()
        section.set("tx-123", forKey: "transaction_id")
        section.set(2, forKey: "count")

        let report = Report(
            crash: .init(
                error: CrashError(
                    type: .unknown("my_monitor"),
                    monitorData: ["my_monitor": section])),
            report: .init(id: "rt"),
            monitorData: ["stitcher": section]
        )

        let (original, roundTripped) = try roundTrip(report)
        XCTAssertEqual(original, roundTripped)

        // The wire keys: both namespaces are named monitor_data, one under
        // the error section and one at the report root.
        let data = try JSONEncoder().encode(report)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil((dict["monitor_data"] as? [String: Any])?["stitcher"])
        let errorDict = try XCTUnwrap(
            ((dict["crash"] as? [String: Any])?["error"] as? [String: Any]))
        XCTAssertNotNil((errorDict["monitor_data"] as? [String: Any])?["my_monitor"])
        XCTAssertEqual(errorDict["type"] as? String, "my_monitor")
    }

    // MARK: - Wire Fidelity

    /// Decode and re-encode is what the send path does to every report, so a key
    /// the model does not carry is a key the consumer never sees. Every non-null
    /// leaf in a fixture must come out the other side.
    func testExampleReportsLoseNoKeys() throws {
        // Shapes the writer no longer emits and the model deliberately normalizes:
        // the pre-3.x {major, minor} version object is re-encoded as a version
        // string, and the pre-3.x backtrace under last_dealloced_nsexception is
        // not modeled because it is not written any more.
        let legacy = [
            "report.version.major", "report.version.minor",
            "recrash_report.report.version.major", "recrash_report.report.version.minor",
            "process.last_dealloced_nsexception.backtrace",
        ]
        let urls = try XCTUnwrap(Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil))
        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            let originalData = try Data(contentsOf: url)
            let report = try JSONDecoder().decode(Report.self, from: originalData)
            let encodedData = try JSONEncoder().encode(report)
            let original = leafPaths(of: try JSONSerialization.jsonObject(with: originalData))
            let reencoded = leafPaths(of: try JSONSerialization.jsonObject(with: encodedData))
            let dropped = original.subtracting(reencoded).filter { path in
                !legacy.contains { path.hasPrefix($0) }
            }
            XCTAssertTrue(dropped.isEmpty, "\(url.lastPathComponent) dropped \(dropped.sorted())")
        }
    }

    func testRoundTripProcessStartTimes() throws {
        let report = Report(
            crash: Report.Crash(error: CrashError(type: .mach)),
            report: ReportInfo(id: "process-start"),
            system: SystemInfo(
                processStartWallClockNs: 1_755_600_000_123_456_789,
                processStartMonotonicNs: 98_765_432_101)
        )

        let (_, roundTripped) = try roundTrip(report)
        XCTAssertEqual(roundTripped.system?.processStartWallClockNs, 1_755_600_000_123_456_789)
        XCTAssertEqual(roundTripped.system?.processStartMonotonicNs, 98_765_432_101)

        let dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        let system = try XCTUnwrap(dict?["system"] as? [String: Any])
        XCTAssertEqual(system["process_start_wall_clock_ns"] as? UInt64, 1_755_600_000_123_456_789)
        XCTAssertEqual(system["process_start_monotonic_ns"] as? UInt64, 98_765_432_101)
    }

    /// The exception register names are per architecture; the model carries
    /// whatever set the writer emitted.
    func testRoundTripExceptionRegistersPerArchitecture() throws {
        let perArchitecture: [[String: UInt64]] = [
            ["exception": 0x1, "esr": 0x9200_0046, "far": 0x10],
            ["exception": 0x1, "fsr": 0x7, "far": 0x10],
            ["trapno": 0xe, "err": 0x4, "faultvaddr": 0x10],
        ]
        for exception in perArchitecture {
            let thread = Report.Thread(
                crashed: true, currentThread: true, index: 0,
                registers: Registers(basic: ["pc": 0x1000], exception: exception))
            let report = Report(
                crash: Report.Crash(error: CrashError(type: .mach), threads: [thread]),
                report: ReportInfo(id: "registers"))

            let (_, roundTripped) = try roundTrip(report)
            XCTAssertEqual(roundTripped.crash.threads?.first?.registers?.exception, exception)
            XCTAssertEqual(roundTripped.crash.threads?.first?.registers?.basic, ["pc": 0x1000])
        }
    }

    func testDecodeMemoryContents() throws {
        let json = """
            {
              "address": 4302217216,
              "type": "objc_object",
              "class": "NSMutableArray",
              "last_deallocated_obj": "NSException",
              "first_object": {
                "address": 4302217300,
                "type": "objc_object",
                "class": "Widget",
                "ivars": {
                  "_count": 3,
                  "_scale": 1.5,
                  "_visible": true,
                  "_name": {
                    "address": 4302217400,
                    "type": "objc_object",
                    "class": "__NSCFString",
                    "value": "hello"
                  },
                  "_delegate": {
                    "address": 0,
                    "type": "null_pointer"
                  }
                }
              }
            }
            """
        let contents = try JSONDecoder().decode(MemoryContents.self, from: Data(json.utf8))

        XCTAssertEqual(contents.address, 4_302_217_216)
        XCTAssertEqual(contents.type, .objcObject)
        XCTAssertEqual(contents.class, "NSMutableArray")
        XCTAssertEqual(contents.lastDeallocatedObject, "NSException")
        XCTAssertNil(contents.value)

        let first = try XCTUnwrap(contents.firstObject)
        XCTAssertEqual(first.class, "Widget")
        XCTAssertEqual(first.ivars?["_count"], .integer(3))
        XCTAssertEqual(first.ivars?["_scale"], .double(1.5))
        XCTAssertEqual(first.ivars?["_visible"], .bool(true))
        XCTAssertEqual(
            first.ivars?["_name"],
            .object([
                "address": .integer(4_302_217_400), "type": .string("objc_object"),
                "class": .string("__NSCFString"), "value": .string("hello"),
            ]))
        XCTAssertEqual(first.ivars?["_delegate"], .object(["address": .integer(0), "type": .string("null_pointer")]))
        XCTAssertNil(first.firstObject)

        // The re-encoded JSON carries every key of the source.
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(contents))
        let source = try JSONSerialization.jsonObject(with: Data(json.utf8))
        XCTAssertEqual(leafPaths(of: reencoded), leafPaths(of: source))
    }

    func testRoundTripMemoryContentsInReport() throws {
        let referenced = MemoryContents(
            address: 0x1000, type: .objcObject, class: "NSString", value: .string("boom"))
        let notable = MemoryContents(
            address: 0x2000, type: .objcObject, class: "Widget",
            firstObject: MemoryContents(address: 0x3000, type: .string, value: .string("first")),
            ivars: ["_count": .integer(2)], lastDeallocatedObject: "Gadget")
        let report = Report(
            crash: Report.Crash(
                error: CrashError(
                    nsexception: ExceptionInfo(name: "NSGenericException", referencedObject: referenced),
                    type: .nsexception),
                threads: [
                    Report.Thread(
                        crashed: true, currentThread: true, index: 0,
                        notableAddresses: ["x0": notable, "x1": referenced])
                ]),
            process: ProcessState(
                lastDeallocedNSException: LastDeallocedNSException(
                    address: 0x4000, name: "NSRangeException", reason: "r", referencedObject: notable)),
            report: ReportInfo(id: "memory-contents"))

        let (original, roundTripped) = try roundTrip(report)
        XCTAssertEqual(original, roundTripped)
        XCTAssertEqual(roundTripped.crash.error.nsexception?.referencedObject, referenced)
        XCTAssertEqual(roundTripped.crash.threads?.first?.notableAddresses?["x0"], notable)
        XCTAssertEqual(
            roundTripped.process?.lastDeallocedNSException?.referencedObject?.firstObject?.value, .string("first"))
    }

    func testMemoryTypeKeepsUnknownWireValues() throws {
        XCTAssertEqual(MemoryType(rawValue: "objc_block"), .objcBlock)
        XCTAssertEqual(MemoryType(rawValue: "unknown"), .unknown)
        XCTAssertEqual(MemoryType(rawValue: "future_kind"), .other("future_kind"))
        XCTAssertEqual(MemoryType.other("future_kind").rawValue, "future_kind")
    }

    /// Dotted paths of every non-null leaf, array elements by index. Nulls are
    /// skipped because the model encodes an absent value as a missing key.
    private func leafPaths(of value: Any, at path: String = "", into paths: inout Set<String>) {
        switch value {
        case let dict as [String: Any]:
            for (key, child) in dict {
                leafPaths(of: child, at: path.isEmpty ? key : path + "." + key, into: &paths)
            }
        case let array as [Any]:
            for (index, child) in array.enumerated() {
                leafPaths(of: child, at: path + "[\(index)]", into: &paths)
            }
        case is NSNull:
            break
        default:
            paths.insert(path)
        }
    }

    private func leafPaths(of value: Any) -> Set<String> {
        var paths = Set<String>()
        leafPaths(of: value, at: "", into: &paths)
        return paths
    }

    private func roundTrip(_ report: Report) throws -> (
        original: Report, roundTripped: Report
    ) {
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let decoded = try JSONDecoder().decode(Report.self, from: data)
        return (report, decoded)
    }

    private func assertExampleReportRoundTrips(_ name: String, file: StaticString = #filePath, line: UInt = #line)
        throws
    {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        let originalData = try Data(contentsOf: url)
        let report = try JSONDecoder().decode(Report.self, from: originalData)

        // Encode back to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedData = try encoder.encode(report)

        // Decode the encoded JSON
        let roundTripped = try JSONDecoder().decode(Report.self, from: encodedData)

        // Verify key fields survive the round trip
        XCTAssertEqual(
            roundTripped.report.id, report.report.id, "Report ID mismatch for \(name)", file: file, line: line)
        XCTAssertEqual(
            roundTripped.crash.error.type, report.crash.error.type, "Error type mismatch for \(name)", file: file,
            line: line)
        XCTAssertEqual(
            roundTripped.crash.threads?.count, report.crash.threads?.count, "Thread count mismatch for \(name)",
            file: file, line: line)
        XCTAssertEqual(
            roundTripped.binaryImages?.count, report.binaryImages?.count, "Binary image count mismatch for \(name)",
            file: file, line: line)
        XCTAssertEqual(
            roundTripped.system?.cfBundleExecutable, report.system?.cfBundleExecutable,
            "Bundle executable mismatch for \(name)", file: file, line: line)
        XCTAssertEqual(
            roundTripped.report.type, report.report.type, "Report type mismatch for \(name)", file: file, line: line)
        XCTAssertEqual(
            roundTripped.report.version?.major, report.report.version?.major, "Version major mismatch for \(name)",
            file: file, line: line)

        // Verify crash details
        XCTAssertEqual(
            roundTripped.crash.error.mach?.exception, report.crash.error.mach?.exception,
            "Mach exception mismatch for \(name)", file: file, line: line)
        XCTAssertEqual(
            roundTripped.crash.error.signal?.signal, report.crash.error.signal?.signal,
            "Signal mismatch for \(name)", file: file, line: line)
        XCTAssertEqual(
            roundTripped.crash.error.nsexception?.name, report.crash.error.nsexception?.name,
            "NSException name mismatch for \(name)", file: file, line: line)

        // Verify thread backtraces
        if let originalThreads = report.crash.threads, let roundTrippedThreads = roundTripped.crash.threads {
            for (i, (orig, rt)) in zip(originalThreads, roundTrippedThreads).enumerated() {
                XCTAssertEqual(
                    rt.crashed, orig.crashed, "Thread \(i) crashed mismatch for \(name)", file: file, line: line)
                XCTAssertEqual(
                    rt.backtrace?.contents.count, orig.backtrace?.contents.count,
                    "Thread \(i) frame count mismatch for \(name)", file: file, line: line)
            }
        }

        // Verify recrash report survives if present
        if report.recrashReport != nil {
            XCTAssertNotNil(roundTripped.recrashReport, "RecrashReport lost for \(name)", file: file, line: line)
        }
    }
}
