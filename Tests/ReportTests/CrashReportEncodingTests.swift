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

@testable import Report

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
        let report = BasicCrashReport(
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
            crash: BasicCrashReport.Crash(
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
                    BasicCrashReport.Thread(
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
                    BasicCrashReport.Thread(
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
        let report = BasicCrashReport(
            crash: BasicCrashReport.Crash(
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

    func testRoundTripMinimalReport() throws {
        let report = BasicCrashReport(
            crash: BasicCrashReport.Crash(
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
        let report = BasicCrashReport(
            crash: BasicCrashReport.Crash(
                error: CrashError(type: .mach),
                threads: [
                    BasicCrashReport.Thread(
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

    // MARK: - Encoding Key Verification

    func testEncodingUsesSnakeCaseKeys() throws {
        let report = BasicCrashReport(
            binaryImages: [
                BinaryImage(
                    cpuSubtype: 1,
                    cpuType: 12,
                    imageAddr: 0x1000,
                    imageSize: 4096,
                    name: "test"
                )
            ],
            crash: BasicCrashReport.Crash(
                error: CrashError(type: .mach),
                threads: [
                    BasicCrashReport.Thread(
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
                crashedThread: BasicCrashReport.Thread(
                    crashed: true,
                    currentThread: true,
                    index: 0
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
    }

    // MARK: - Helpers

    private func roundTrip(_ report: BasicCrashReport) throws -> (
        original: BasicCrashReport, roundTripped: BasicCrashReport
    ) {
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let decoded = try JSONDecoder().decode(BasicCrashReport.self, from: data)
        return (report, decoded)
    }

    private func assertExampleReportRoundTrips(_ name: String, file: StaticString = #filePath, line: UInt = #line)
        throws
    {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        let originalData = try Data(contentsOf: url)
        let report = try JSONDecoder().decode(BasicCrashReport.self, from: originalData)

        // Encode back to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedData = try encoder.encode(report)

        // Decode the encoded JSON
        let roundTripped = try JSONDecoder().decode(BasicCrashReport.self, from: encodedData)

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
