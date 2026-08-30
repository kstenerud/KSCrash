//
//  CrashReportDecodingTests.swift
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

import Foundation
import XCTest

@testable import KSCrashReportModel

final class CrashReportDecodingTests: XCTestCase {

    // A degenerate or older profile frame can lack `instruction_addr`. It must decode with a nil
    // address rather than failing the whole report (which is index-referenced and can't drop frames).
    func testStackFrameDecodesWithoutInstructionAddr() throws {
        let json = """
            {
                "object_name": "App",
                "object_addr": 4096,
                "symbol_name": "foo"
            }
            """
        let frame = try JSONDecoder().decode(StackFrame.self, from: Data(json.utf8))
        XCTAssertNil(frame.instructionAddr)
        XCTAssertEqual(frame.objectAddr, 4096)
        XCTAssertEqual(frame.objectName, "App")
        XCTAssertEqual(frame.symbolName, "foo")
    }

    func testStackFrameDecodesWithInstructionAddr() throws {
        let json = """
            { "instruction_addr": 8192 }
            """
        let frame = try JSONDecoder().decode(StackFrame.self, from: Data(json.utf8))
        XCTAssertEqual(frame.instructionAddr, 8192)
    }

    func testDecodeMinimalReport() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": {
                        "type": "mach",
                        "mach": {
                            "code": 1,
                            "exception": 1
                        }
                    },
                    "threads": []
                },
                "report": {
                    "id": "\(testReportID("test-id"))"
                },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)

        XCTAssertEqual(report.report.id, testReportID("test-id"))
        XCTAssertEqual(report.crash.error.type, .mach)
        XCTAssertEqual(report.crash.error.mach?.code, 1)
        XCTAssertEqual(report.crash.error.mach?.exception, 1)
        XCTAssertTrue(report.binaryImages?.isEmpty ?? true)
        XCTAssertTrue(report.crash.threads?.isEmpty ?? true)
    }

    func testDecodeBinaryImage() throws {
        let json = """
            {
                "binary_images": [
                    {
                        "cpu_subtype": 9,
                        "cpu_type": 12,
                        "image_addr": 32768,
                        "image_size": 282624,
                        "name": "/path/to/App.app/App",
                        "uuid": "99E112D2-0CB4-3F73-BDA6-BCFC1F190724"
                    }
                ],
                "crash": {
                    "error": { "type": "mach" },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)

        XCTAssertEqual(report.binaryImages?.count, 1)
        let image = report.binaryImages![0]
        XCTAssertEqual(image.cpuSubtype, 9)
        XCTAssertEqual(image.cpuType, 12)
        XCTAssertEqual(image.imageAddr, 32768)
        XCTAssertEqual(image.imageSize, 282624)
        XCTAssertEqual(image.name, "/path/to/App.app/App")
        XCTAssertEqual(image.uuid, "99E112D2-0CB4-3F73-BDA6-BCFC1F190724")
    }

    func testDecodeNSException() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "diagnosis": "Application threw exception NSInvalidArgumentException",
                    "error": {
                        "type": "nsexception",
                        "nsexception": {
                            "name": "NSInvalidArgumentException",
                            "reason": "-[__NSArrayI objectForKey:]: unrecognized selector"
                        },
                        "mach": {
                            "code": 0,
                            "exception": 10,
                            "exception_name": "EXC_CRASH"
                        },
                        "signal": {
                            "code": 0,
                            "name": "SIGABRT",
                            "signal": 6
                        }
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)

        XCTAssertEqual(report.crash.error.type, .nsexception)
        XCTAssertEqual(report.crash.error.nsexception?.name, "NSInvalidArgumentException")
        XCTAssertEqual(report.crash.error.nsexception?.reason, "-[__NSArrayI objectForKey:]: unrecognized selector")
        XCTAssertEqual(report.crash.error.mach?.exceptionName, "EXC_CRASH")
        XCTAssertEqual(report.crash.error.signal?.name, "SIGABRT")
    }

    func testDecodeThread() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": { "type": "mach" },
                    "threads": [
                        {
                            "backtrace": {
                                "contents": [
                                    {
                                        "instruction_addr": 827844157,
                                        "object_addr": 827195392,
                                        "object_name": "CoreFoundation",
                                        "symbol_addr": 827844060,
                                        "symbol_name": "__exceptionPreprocess"
                                    }
                                ],
                                "skipped": 0
                            },
                            "crashed": true,
                            "current_thread": true,
                            "dispatch_queue": "apple.main-thread",
                            "index": 0
                        }
                    ]
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)

        XCTAssertEqual(report.crash.threads?.count, 1)
        let thread = report.crash.threads![0]
        XCTAssertTrue(thread.crashed)
        XCTAssertTrue(thread.currentThread)
        XCTAssertEqual(thread.dispatchQueue, "apple.main-thread")
        XCTAssertEqual(thread.index, 0)

        XCTAssertEqual(thread.backtrace?.contents.count, 1)
        let frame = thread.backtrace!.contents[0]
        XCTAssertEqual(frame.instructionAddr, 827_844_157)
        XCTAssertEqual(frame.objectName, "CoreFoundation")
        XCTAssertEqual(frame.symbolName, "__exceptionPreprocess")
    }

    func testDecodeLastExceptionBacktrace() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": {
                        "type": "nsexception",
                        "nsexception": {
                            "name": "NSInvalidArgumentException"
                        }
                    },
                    "threads": [],
                    "last_exception_backtrace": {
                        "contents": [
                            {
                                "instruction_addr": 100,
                                "object_addr": 0,
                                "object_name": "CoreFoundation",
                                "symbol_name": "__exceptionPreprocess"
                            },
                            {
                                "instruction_addr": 200,
                                "object_addr": 0,
                                "object_name": "libobjc.A.dylib",
                                "symbol_name": "objc_exception_throw"
                            }
                        ],
                        "skipped": 0
                    }
                },
                "report": { "id": "\(testReportID("test-last-exception-bt"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)

        XCTAssertNotNil(report.crash.lastExceptionBacktrace)
        XCTAssertEqual(report.crash.lastExceptionBacktrace?.contents.count, 2)
        XCTAssertEqual(report.crash.lastExceptionBacktrace?.contents[0].symbolName, "__exceptionPreprocess")
        XCTAssertEqual(report.crash.lastExceptionBacktrace?.contents[1].symbolName, "objc_exception_throw")
        XCTAssertEqual(report.crash.lastExceptionBacktrace?.skipped, 0)
    }

    func testDecodeAbsentLastExceptionBacktrace() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": { "type": "mach" },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertNil(report.crash.lastExceptionBacktrace)
    }

    func testDecodeSystemInfo() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": { "type": "mach" },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {
                    "CFBundleExecutable": "MyApp",
                    "CFBundleIdentifier": "com.example.myapp",
                    "CFBundleVersion": "1.0",
                    "cpu_arch": "arm64",
                    "machine": "iPhone14,2",
                    "system_name": "iOS",
                    "system_version": "17.0",
                    "memory": {
                        "free": 133308416,
                        "size": 527433728,
                        "usable": 440909824
                    }
                }
            }
            """

        let report = try Report.decode(from: json)

        XCTAssertEqual(report.system?.cfBundleExecutable, "MyApp")
        XCTAssertEqual(report.system?.cfBundleIdentifier, "com.example.myapp")
        XCTAssertEqual(report.system?.cfBundleVersion, "1.0")
        XCTAssertEqual(report.system?.cpuArch, "arm64")
        XCTAssertEqual(report.system?.machine, "iPhone14,2")
        XCTAssertEqual(report.system?.systemName, "iOS")
        XCTAssertEqual(report.system?.systemVersion, "17.0")
        XCTAssertEqual(report.system?.memory?.free, 133_308_416)
        XCTAssertEqual(report.system?.memory?.size, 527_433_728)
    }

    func testDecodeResourceFields() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": { "type": "mach" },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {
                    "battery_level": 72,
                    "battery_state": 2,
                    "low_power_mode_enabled": true,
                    "cpu_core_count": 6,
                    "cpu_usage_user": 1500,
                    "cpu_usage_system": 200,
                    "cpu_state": "warning",
                    "cpu_average_usage_permil": 520,
                    "cpu_time_in_window": 95.0,
                    "cpu_wall_time_in_window": 180.0,
                    "thermal_state": 1,
                    "thread_count": 42,
                    "data_protection_active": true
                }
            }
            """

        let report = try Report.decode(from: json)

        XCTAssertEqual(report.system?.batteryLevel, 72)
        XCTAssertEqual(report.system?.batteryState, .charging)
        XCTAssertEqual(report.system?.lowPowerModeEnabled, true)
        XCTAssertEqual(report.system?.cpuCoreCount, 6)
        XCTAssertEqual(report.system?.cpuUsageUser, 1500)
        XCTAssertEqual(report.system?.cpuUsageSystem, 200)
        XCTAssertEqual(report.system?.cpuState, .warning)
        XCTAssertEqual(report.system?.cpuAverageUsagePermil, 520)
        XCTAssertEqual(report.system?.cpuTimeInWindow, 95.0)
        XCTAssertEqual(report.system?.cpuWallTimeInWindow, 180.0)
        XCTAssertEqual(report.system?.thermalState, .fair)
        XCTAssertEqual(report.system?.threadCount, 42)
        XCTAssertEqual(report.system?.dataProtectionActive, true)
    }

    func testDecodeResourceFieldsAbsent() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": { "type": "mach" },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)

        XCTAssertNil(report.system?.batteryLevel)
        XCTAssertNil(report.system?.batteryState)
        XCTAssertNil(report.system?.lowPowerModeEnabled)
        XCTAssertNil(report.system?.cpuCoreCount)
        XCTAssertNil(report.system?.cpuState)
        XCTAssertNil(report.system?.cpuTimeInWindow)
        XCTAssertNil(report.system?.cpuWallTimeInWindow)
        XCTAssertNil(report.system?.thermalState)
        XCTAssertNil(report.system?.threadCount)
        XCTAssertNil(report.system?.dataProtectionActive)
    }

    func testDecodeBatteryStateValues() throws {
        for (rawValue, expected): (Int, BatteryState) in [
            (0, .unknown), (1, .unplugged), (2, .charging), (3, .full),
        ] {
            let json = """
                {
                    "crash": { "error": { "type": "mach" }, "threads": [] },
                    "report": { "id": "\(testReportID("test"))" },
                    "system": { "battery_state": \(rawValue) }
                }
                """
            let report = try Report.decode(from: json)
            XCTAssertEqual(report.system?.batteryState, expected, "battery_state \(rawValue)")
        }
    }

    func testDecodeThermalStateValues() throws {
        for (rawValue, expected): (Int, ThermalState) in [
            (0, .nominal), (1, .fair), (2, .serious), (3, .critical),
        ] {
            let json = """
                {
                    "crash": { "error": { "type": "mach" }, "threads": [] },
                    "report": { "id": "\(testReportID("test"))" },
                    "system": { "thermal_state": \(rawValue) }
                }
                """
            let report = try Report.decode(from: json)
            XCTAssertEqual(report.system?.thermalState, expected, "thermal_state \(rawValue)")
        }
    }

    func testDecodeCPUStateValues() throws {
        for (rawValue, expected): (String, CPUState) in [
            ("normal", .normal), ("warning", .warning), ("critical", .critical),
        ] {
            let json = """
                {
                    "crash": { "error": { "type": "mach" }, "threads": [] },
                    "report": { "id": "\(testReportID("test"))" },
                    "system": { "cpu_state": "\(rawValue)" }
                }
                """
            let report = try Report.decode(from: json)
            XCTAssertEqual(report.system?.cpuState, expected, "cpu_state \(rawValue)")
        }
    }

    func testDecodeUserData() throws {
        struct TestUserData: Codable, Equatable {
            let key1: String
            let key2: Int
            let key3: Bool
            let key4: NestedData

            struct NestedData: Codable, Equatable {
                let nested: String
            }
        }

        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": { "type": "mach" },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {},
                "user": {
                    "key1": "string value",
                    "key2": 42,
                    "key3": true,
                    "key4": {
                        "nested": "value"
                    }
                }
            }
            """

        let data = json.data(using: .utf8)!
        let report = try JSONDecoder().decode(Report.self, from: data)

        let metadata = try XCTUnwrap(report.metadata)
        XCTAssertEqual(metadata.value(forKey: "key1"), "string value")
        XCTAssertEqual(metadata.value(forKey: "key2"), 42)
        XCTAssertEqual(metadata.value(forKey: "key3"), true)
        XCTAssertEqual(
            try metadata.decoded(as: TestUserData.self),
            TestUserData(
                key1: "string value", key2: 42, key3: true,
                key4: TestUserData.NestedData(nested: "value")))
    }

    func testDecodeCustomMonitorErrorSections() throws {
        let json = """
            {
                "crash": {
                    "error": {
                        "type": "my_monitor",
                        "monitor_data": {
                            "my_monitor": { "transaction_id": "tx-123", "count": 2 },
                            "other_monitor": { "flag": true }
                        }
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """

        let error = try JSONDecoder().decode(Report.self, from: Data(json.utf8)).crash.error
        XCTAssertEqual(error.type, .unknown("my_monitor"))

        XCTAssertEqual(error.monitorData?.count, 2)
        XCTAssertEqual(error.monitorData?["my_monitor"]?.value(forKey: "transaction_id"), "tx-123")
        XCTAssertEqual(error.monitorData?["other_monitor"]?.value(forKey: "flag"), true)

        struct MyMonitorData: Codable, Equatable {
            let transactionId: String
            let count: Int
            enum CodingKeys: String, CodingKey {
                case transactionId = "transaction_id"
                case count
            }
        }
        XCTAssertEqual(
            try error.monitorData(MyMonitorData.self, for: "my_monitor"),
            MyMonitorData(transactionId: "tx-123", count: 2))
        XCTAssertNil(try error.monitorData(MyMonitorData.self, for: "absent"))
        XCTAssertThrowsError(try error.monitorData(MyMonitorData.self, for: "other_monitor"))
    }

    func testMonitorSectionsKeepTheirNulls() throws {
        // monitor_data and memory_termination reuse Metadata for its typed
        // reads, but they are JSON a monitor wrote, not the app-owned bag
        // where null means absence. Dropping a null here re-indexes the array
        // holding it and erases the difference between a member set to null
        // and one that was never written.
        let json = """
            {
                "crash": {
                    "error": {
                        "type": "my_monitor",
                        "memory_termination": { "memory_level": null },
                        "monitor_data": {
                            "my_monitor": { "samples": [1, null, 3], "threshold": null }
                        }
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """

        struct MyMonitorData: Codable, Equatable {
            let samples: [Int?]
            let threshold: Int?
        }
        struct Termination: Codable, Equatable {
            let memoryLevel: String?
            enum CodingKeys: String, CodingKey { case memoryLevel = "memory_level" }
        }

        let error = try JSONDecoder().decode(Report.self, from: Data(json.utf8)).crash.error
        XCTAssertEqual(
            try error.monitorData(MyMonitorData.self, for: "my_monitor"),
            MyMonitorData(samples: [1, nil, 3], threshold: nil))
        XCTAssertEqual(try error.memoryTermination?.decoded(as: Termination.self), Termination(memoryLevel: nil))

        // The section a consumer reads is the section the monitor wrote, so a
        // decode and re-encode of one gives back what it was given.
        let section = try XCTUnwrap(error.monitorData?["my_monitor"])
        let encoded = try JSONEncoder().encode(section)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: encoded) as? NSDictionary,
            ["samples": [1, NSNull(), 3], "threshold": NSNull()] as NSDictionary)
    }

    /// Unknown keys under crash.error are schema evolution, not sections:
    /// ignored on decode, like any other unknown key in the model.
    func testDecodeIgnoresUnknownKeysUnderCrashError() throws {
        let json = """
            {
                "crash": {
                    "error": { "type": "mach", "future_field": 42, "future_section": { "a": 1 } },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """

        let error = try JSONDecoder().decode(Report.self, from: Data(json.utf8)).crash.error
        XCTAssertNil(error.monitorData)
    }

    /// A section must be an object in both namespaces; anything else fails
    /// the report's decode so the violation is loud, not silently dropped.
    func testDecodeNonObjectMonitorSectionFailsTheReport() throws {
        let inError = """
            {
                "crash": {
                    "error": { "type": "mach", "monitor_data": { "my_monitor": 42 } },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """
        XCTAssertThrowsError(try JSONDecoder().decode(Report.self, from: Data(inError.utf8)))

        let atRoot = """
            {
                "crash": { "error": { "type": "mach" }, "threads": [] },
                "report": { "id": "\(testReportID("test"))" },
                "monitor_data": { "my_monitor": "not an object" }
            }
            """
        XCTAssertThrowsError(try JSONDecoder().decode(Report.self, from: Data(atRoot.utf8)))
    }

    func testDecodeLegacyMemoryTermination() throws {
        let json = """
            {
                "crash": {
                    "error": {
                        "type": "memory_termination",
                        "memory_termination": { "memory_pressure": "critical", "memory_level": "warn" }
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """

        let error = try JSONDecoder().decode(Report.self, from: Data(json.utf8)).crash.error
        XCTAssertEqual(error.type, .termination)
        XCTAssertEqual(error.memoryTermination?.value(forKey: "memory_pressure"), "critical")
        XCTAssertNil(error.monitorData)

        // And it survives a round trip.
        let reencoded = try JSONDecoder().decode(
            Report.self, from: JSONEncoder().encode(JSONDecoder().decode(Report.self, from: Data(json.utf8))))
        XCTAssertEqual(reencoded.crash.error.memoryTermination?.value(forKey: "memory_level"), "warn")
    }

    func testDecodeMonitorDataNamespace() throws {
        let json = """
            {
                "crash": { "error": { "type": "mach" }, "threads": [] },
                "report": { "id": "\(testReportID("test"))" },
                "monitor_data": {
                    "my_monitor": { "transaction_id": "tx-123" }
                }
            }
            """

        let report = try JSONDecoder().decode(Report.self, from: Data(json.utf8))
        XCTAssertEqual(report.monitorData?["my_monitor"]?.value(forKey: "transaction_id"), "tx-123")

        struct MyMonitorData: Codable, Equatable {
            let transactionId: String
            enum CodingKeys: String, CodingKey {
                case transactionId = "transaction_id"
            }
        }
        XCTAssertEqual(
            try report.monitorData(MyMonitorData.self, for: "my_monitor")?.transactionId, "tx-123")
        XCTAssertNil(try report.monitorData(MyMonitorData.self, for: "absent"))
    }

    func testDecodeWithoutMonitorData() throws {
        let json = """
            {
                "crash": { "error": { "type": "mach" }, "threads": [] },
                "report": { "id": "\(testReportID("test"))" }
            }
            """
        let report = try JSONDecoder().decode(Report.self, from: Data(json.utf8))
        XCTAssertNil(report.monitorData)
        XCTAssertNil(report.crash.error.monitorData)
    }

    func testDecodeWithoutUserData() throws {
        let json = """
            {
                "crash": {
                    "error": { "type": "mach" },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """

        let report = try JSONDecoder().decode(Report.self, from: json.data(using: .utf8)!)
        XCTAssertNil(report.metadata)
    }

    func testDecodeRealNSExceptionReport() throws {
        let url = Bundle.module.url(forResource: "NSException", withExtension: "json")!
        let report = try Report.decode(from: url)

        // Verify top-level structure
        XCTAssertEqual(report.report.id, testReportID("1DFC2552-8F7C-4D14-B0A8-5FE04E5AE35E"))
        XCTAssertEqual(report.report.type, .standard)
        XCTAssertEqual(report.report.version?.major, 2)
        XCTAssertEqual(report.report.version?.minor, 0)

        // Verify crash info
        XCTAssertEqual(report.crash.error.type, .nsexception)
        XCTAssertEqual(report.crash.error.nsexception?.name, "NSInvalidArgumentException")
        XCTAssertNotNil(report.crash.error.nsexception?.reason)

        // Verify system info
        XCTAssertEqual(report.system?.cfBundleExecutable, "Crash-Tester")
        XCTAssertEqual(report.system?.cfBundleIdentifier, "org.stenerud.Crash-Tester")
        XCTAssertEqual(report.system?.cpuArch, "armv7")
        XCTAssertEqual(report.system?.machine, "iPhone3,1")

        // Verify threads
        XCTAssertFalse(report.crash.threads?.isEmpty ?? true)
        let crashedThread = report.crash.threads?.first { $0.crashed }
        XCTAssertNotNil(crashedThread)
        XCTAssertNotNil(crashedThread?.backtrace)
        XCTAssertFalse(crashedThread?.backtrace?.contents.isEmpty ?? true)

        // Verify binary images
        XCTAssertFalse(report.binaryImages?.isEmpty ?? true)
        let mainImage = report.binaryImages?.first { $0.name.contains("Crash-Tester.app/Crash-Tester") }
        XCTAssertNotNil(mainImage)
        XCTAssertEqual(mainImage?.uuid, "99E112D2-0CB4-3F73-BDA6-BCFC1F190724")
    }

    // MARK: - Example Reports

    private func decodeExampleReport(_ name: String) throws -> Report {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try Report.decode(from: url)
    }

    func testDecodeExampleAbort() throws {
        let report = try decodeExampleReport("Abort")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .signal)
        XCTAssertEqual(report.crash.error.signal?.name, "SIGABRT")
    }

    func testDecodeExampleBadPointer() throws {
        let report = try decodeExampleReport("BadPointer")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .mach)
    }

    func testDecodeExampleCorruptMemory() throws {
        let report = try decodeExampleReport("CorruptMemory")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .signal)
    }

    func testDecodeExampleCorruptObject() throws {
        let report = try decodeExampleReport("CorruptObject")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .mach)
    }

    func testDecodeExampleCrashInHandler() throws {
        let report = try decodeExampleReport("CrashInHandler")
        XCTAssertNotNil(report.report.id)
        XCTAssertNotNil(report.recrashReport)
    }

    func testDecodeExampleMainThreadDeadlock() throws {
        let report = try decodeExampleReport("MainThreadDeadlock")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .deadlock)
    }

    func testDecodeExampleNSException() throws {
        let report = try decodeExampleReport("NSException")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .nsexception)
        XCTAssertEqual(report.crash.error.nsexception?.name, "NSInvalidArgumentException")
    }

    func testDecodeExampleStackOverflow() throws {
        let report = try decodeExampleReport("StackOverflow")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .mach)
    }

    func testDecodeExampleZombie() throws {
        let report = try decodeExampleReport("Zombie")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .mach)
    }

    func testDecodeExampleZombieNSException() throws {
        let report = try decodeExampleReport("ZombieNSException")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .mach)
    }

    func testDecodeExampleWatchdogTimeout() throws {
        let report = try decodeExampleReport("WatchdogTimeout")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .mach)

        // Verify hang info
        XCTAssertNotNil(report.crash.error.hang)
        XCTAssertEqual(report.crash.error.hang?.hangStartNanos, 896_794_983_811_166)
        XCTAssertEqual(report.crash.error.hang?.hangStartRole, .foregroundApplication)
        XCTAssertEqual(report.crash.error.hang?.hangEndNanos, 896_795_233_899_208)
        XCTAssertEqual(report.crash.error.hang?.hangEndRole, .foregroundApplication)

        // Verify exit reason (0x8badf00d = "ate bad food" watchdog termination)
        XCTAssertNotNil(report.crash.error.exitReason)
        XCTAssertEqual(report.crash.error.exitReason?.code, 0x8bad_f00d)
    }

    func testDecodeExampleHang() throws {
        let report = try decodeExampleReport("Hang")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .hang)

        // Verify hang info
        XCTAssertNotNil(report.crash.error.hang)
        XCTAssertEqual(report.crash.error.hang?.hangStartNanos, 897_133_713_870_375)
        XCTAssertEqual(report.crash.error.hang?.hangStartRole, .foregroundApplication)
        XCTAssertEqual(report.crash.error.hang?.hangEndNanos, 897_141_715_985_666)
        XCTAssertEqual(report.crash.error.hang?.hangEndRole, .foregroundApplication)
    }

    func testDecodeExampleProfile() throws {
        let report = try decodeExampleReport("Profile")
        XCTAssertNotNil(report.report.id)
        XCTAssertEqual(report.crash.error.type, .profile)

        // Verify profile info
        let profile = report.crash.error.profile
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.name, "startup")
        XCTAssertEqual(profile?.id, "D839BCD7-0A1B-49C9-A5C0-3550507EBE84")
        XCTAssertEqual(profile?.timeUnits, "nanoseconds")
        XCTAssertEqual(profile?.duration, 262_253_917)

        // Verify frames exist
        let frames = profile?.frames ?? []
        XCTAssertFalse(frames.isEmpty)

        // A time profile is one primary thread with samples.
        let threads = profile?.threads ?? []
        XCTAssertEqual(threads.count, 1)
        XCTAssertTrue(threads[0].primary)
        let samples = threads[0].samples
        XCTAssertFalse(samples.isEmpty)

        // Verify each sample's frame indexes reference valid frames
        for (sampleIndex, sample) in samples.enumerated() {
            XCTAssertEqual(sample.count, 1)
            for frameIndex in sample.frames {
                XCTAssertTrue(
                    frameIndex >= 0 && frameIndex < frames.count,
                    "Sample \(sampleIndex) has invalid frame index \(frameIndex), frames count is \(frames.count)"
                )
            }
        }
    }

    func testDecodeCompactFormatWithObjectUUID() throws {
        let json = """
            {
                "crash": {
                    "error": {
                        "type": "mach",
                        "mach": {
                            "code": 1,
                            "exception": 1
                        }
                    },
                    "threads": [
                        {
                            "backtrace": {
                                "contents": [
                                    {
                                        "instruction_addr": 827844157,
                                        "object_addr": 827195392,
                                        "object_name": "CoreFoundation",
                                        "object_uuid": "AABBCCDD-1122-3344-5566-778899AABBCC",
                                        "symbol_addr": 827844060,
                                        "symbol_name": "__exceptionPreprocess"
                                    }
                                ],
                                "skipped": 0
                            },
                            "crashed": true,
                            "current_thread": true,
                            "index": 0
                        }
                    ]
                },
                "report": { "id": "\(testReportID("compact-test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)

        // binary_images is absent, so it should be nil
        XCTAssertNil(report.binaryImages)

        // Frames should have both object_uuid and object_addr
        let frame = report.crash.threads?[0].backtrace?.contents[0]
        XCTAssertEqual(frame?.objectUUID, "AABBCCDD-1122-3344-5566-778899AABBCC")
        XCTAssertEqual(frame?.objectAddr, 827_195_392)
        XCTAssertEqual(frame?.objectName, "CoreFoundation")
        XCTAssertEqual(frame?.symbolName, "__exceptionPreprocess")
    }

    func testDecodeCompactReportOnlyReferencedImages() throws {
        // Simulates a compact-mode report: binary_images only contains images
        // that are referenced by backtrace frames (plus crash_info images).
        let json = """
            {
                "binary_images": [
                    {
                        "cpu_subtype": 9,
                        "cpu_type": 12,
                        "image_addr": 4294967296,
                        "image_size": 65536,
                        "name": "/usr/lib/system/libsystem_kernel.dylib",
                        "uuid": "11111111-1111-1111-1111-111111111111"
                    },
                    {
                        "cpu_subtype": 9,
                        "cpu_type": 12,
                        "image_addr": 4295032832,
                        "image_size": 32768,
                        "name": "/path/to/App",
                        "uuid": "22222222-2222-2222-2222-222222222222"
                    }
                ],
                "crash": {
                    "error": {
                        "type": "mach",
                        "mach": { "code": 1, "exception": 1 }
                    },
                    "threads": [
                        {
                            "backtrace": {
                                "contents": [
                                    {
                                        "instruction_addr": 4294967400,
                                        "object_addr": 4294967296,
                                        "object_name": "libsystem_kernel.dylib",
                                        "object_uuid": "11111111-1111-1111-1111-111111111111",
                                        "symbol_name": "__pthread_kill"
                                    },
                                    {
                                        "instruction_addr": 4295032900,
                                        "object_addr": 4295032832,
                                        "object_name": "App",
                                        "object_uuid": "22222222-2222-2222-2222-222222222222",
                                        "symbol_name": "main"
                                    }
                                ],
                                "skipped": 0
                            },
                            "crashed": true,
                            "current_thread": true,
                            "index": 0
                        }
                    ]
                },
                "report": { "id": "\(testReportID("compact-referenced-only"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)

        // In compact mode, binary_images should only contain referenced images
        XCTAssertEqual(report.binaryImages?.count, 2)

        // Every frame's object_addr should have a matching binary image
        let imageAddrs = Set(report.binaryImages?.map(\.imageAddr) ?? [])
        let frames = report.crash.threads?[0].backtrace?.contents ?? []
        for frame in frames {
            if let objectAddr = frame.objectAddr {
                XCTAssertTrue(
                    imageAddrs.contains(objectAddr),
                    "Frame object_addr \(objectAddr) should have a matching binary image"
                )
            }
        }

        // Every frame should have object_uuid
        for frame in frames {
            XCTAssertNotNil(frame.objectUUID, "Every frame should have object_uuid in compact mode")
        }

        // object_uuid on frame should match the corresponding binary image uuid
        let imagesByAddr = Dictionary(
            uniqueKeysWithValues: (report.binaryImages ?? []).map { ($0.imageAddr, $0) })
        for frame in frames {
            guard let addr = frame.objectAddr, let image = imagesByAddr[addr] else { continue }
            XCTAssertEqual(frame.objectUUID, image.uuid)
        }
    }

    func testDecodeCompactReportWithNoBinaryImages() throws {
        // Edge case: compact report where binary_images is absent entirely.
        // Frames still carry object_uuid for self-contained symbolication.
        let json = """
            {
                "crash": {
                    "error": { "type": "signal", "signal": { "signal": 6, "code": 0, "name": "SIGABRT" } },
                    "threads": [
                        {
                            "backtrace": {
                                "contents": [
                                    {
                                        "instruction_addr": 100,
                                        "object_addr": 0,
                                        "object_uuid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
                                    }
                                ],
                                "skipped": 0
                            },
                            "crashed": true,
                            "current_thread": true,
                            "index": 0
                        }
                    ]
                },
                "report": { "id": "\(testReportID("no-binary-images"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertNil(report.binaryImages)
        XCTAssertEqual(
            report.crash.threads?[0].backtrace?.contents[0].objectUUID,
            "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )
    }

    func testDecodeProfileFramesWithObjectUUID() throws {
        // Profile reports should also carry object_uuid on frames
        let json = """
            {
                "crash": {
                    "error": {
                        "type": "profile",
                        "profile": {
                            "name": "test-profile",
                            "id": "PROFILE-UUID",
                            "time_start_epoch": 1000000,
                            "time_start_uptime": 500000,
                            "time_end_uptime": 600000,
                            "expected_sample_interval": 10000,
                            "duration": 100000,
                            "time_units": "nanoseconds",
                            "frames": [
                                {
                                    "instruction_addr": 4294967400,
                                    "object_addr": 4294967296,
                                    "object_name": "libsystem_pthread.dylib",
                                    "object_uuid": "AABB1122-3344-5566-7788-99AABBCCDDEE",
                                    "symbol_name": "pthread_setspecific",
                                    "symbol_addr": 4294967350
                                },
                                {
                                    "instruction_addr": 4295032900,
                                    "object_addr": 4295032832,
                                    "object_name": "App",
                                    "object_uuid": "FFEEDDCC-BBAA-9988-7766-554433221100",
                                    "symbol_name": "main",
                                    "symbol_addr": 4295032832
                                }
                            ],
                            "threads": [
                                {
                                    "index": 0,
                                    "primary": true,
                                    "samples": [
                                        {
                                            "count": 1,
                                            "time_start_uptime": 500000,
                                            "time_end_uptime": 510000,
                                            "duration": 10000,
                                            "frames": [0, 1]
                                        }
                                    ]
                                }
                            ]
                        }
                    }
                },
                "report": { "id": "\(testReportID("profile-uuid-test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)

        let profile = report.crash.error.profile
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.frames.count, 2)

        // Verify object_uuid is decoded on profile frames
        XCTAssertEqual(profile?.frames[0].objectUUID, "AABB1122-3344-5566-7788-99AABBCCDDEE")
        XCTAssertEqual(profile?.frames[0].objectName, "libsystem_pthread.dylib")
        XCTAssertEqual(profile?.frames[1].objectUUID, "FFEEDDCC-BBAA-9988-7766-554433221100")
        XCTAssertEqual(profile?.frames[1].objectName, "App")
    }

    func testDecodeIsFatalTrue() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": {
                        "type": "signal",
                        "is_fatal": true
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertEqual(report.crash.error.isFatal, true)
    }

    func testDecodeIsFatalFalse() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": {
                        "type": "signal",
                        "is_fatal": false
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertEqual(report.crash.error.isFatal, false)
    }

    func testDecodeIsFatalAbsent() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": {
                        "type": "signal"
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertNil(report.crash.error.isFatal)
    }

    func testDecodeIsCleanExitTrue() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": {
                        "type": "signal",
                        "is_clean_exit": true
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertEqual(report.crash.error.isCleanExit, true)
    }

    func testDecodeIsCleanExitFalse() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": {
                        "type": "signal",
                        "is_clean_exit": false
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertEqual(report.crash.error.isCleanExit, false)
    }

    func testDecodeTermination() throws {
        let json = """
            {
                "crash": {
                    "error": {
                        "type": "termination",
                        "termination_reason": "memory_limit",
                        "is_fatal": true,
                        "is_clean_exit": false,
                        "signal": { "signal": 9, "code": 0, "name": "SIGKILL" }
                    }
                },
                "report": {
                    "id": "\(testReportID("test-termination"))",
                    "run_id": "0C1D2E3F-4A5B-4C6D-8E7F-A0B1C2D3E4F5",
                    "session_id": "prev-session-id",
                    "type": "standard",
                    "monitor_id": "Termination"
                }
            }
            """

        let report = try Report.decode(from: json)

        XCTAssertEqual(report.crash.error.type, .termination)
        XCTAssertEqual(report.crash.error.terminationReason, .memoryLimit)
        XCTAssertEqual(report.crash.error.isFatal, true)
        XCTAssertEqual(report.crash.error.isCleanExit, false)
        XCTAssertEqual(report.crash.error.signal?.signal, 9)
        XCTAssertEqual(report.crash.error.signal?.name, "SIGKILL")
        XCTAssertEqual(report.report.runId, RunSummary.ID("0C1D2E3F-4A5B-4C6D-8E7F-A0B1C2D3E4F5"))
        XCTAssertEqual(report.report.sessionId, "prev-session-id")
        XCTAssertEqual(report.report.monitorId, "Termination")
    }

    func testDecodeLegacyResourceTerminationType() throws {
        let json = """
            {
                "crash": {
                    "error": {
                        "type": "resource_termination",
                        "termination_reason": "thermal"
                    }
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """
        let report = try Report.decode(from: json)
        XCTAssertEqual(report.crash.error.type, .termination)
    }

    func testDecodeLegacyMemoryTerminationType() throws {
        let json = """
            {
                "crash": {
                    "error": { "type": "memory_termination" }
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """
        let report = try Report.decode(from: json)
        XCTAssertEqual(report.crash.error.type, .termination)
    }

    func testDecodeTerminationFieldsAbsent() throws {
        let json = """
            {
                "crash": {
                    "error": { "type": "signal" }
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertNil(report.crash.error.terminationReason)
    }

    func testDecodeAllTerminationReasons() throws {
        for (raw, expected): (String, TerminationReason) in [
            ("none", .none),
            ("clean", .clean),
            ("crash", .crash),
            ("hang", .hang),
            ("first_launch", .firstLaunch),
            ("low_battery", .lowBattery),
            ("memory_limit", .memoryLimit),
            ("memory_pressure", .memoryPressure),
            ("thermal", .thermal),
            ("cpu", .cpu),
            ("os_upgrade", .osUpgrade),
            ("app_upgrade", .appUpgrade),
            ("reboot", .reboot),
            ("unexplained", .unexplained),
        ] {
            let json = """
                {
                    "crash": {
                        "error": {
                            "type": "termination",
                            "termination_reason": "\(raw)"
                        }
                    },
                    "report": { "id": "\(testReportID("test"))" }
                }
                """
            let report = try Report.decode(from: json)
            XCTAssertEqual(report.crash.error.terminationReason, expected, "termination_reason \(raw)")
        }
    }

    func testDecodeAllMemoryStates() throws {
        for (raw, expected): (String, MemoryState) in [
            ("normal", .normal),
            ("warn", .warn),
            ("urgent", .urgent),
            ("critical", .critical),
            ("terminal", .terminal),
        ] {
            let json = """
                {
                    "crash": { "error": { "type": "signal" } },
                    "system": {
                        "app_memory": {
                            "memory_level": "\(raw)",
                            "memory_pressure": "\(raw)"
                        }
                    },
                    "report": { "id": "\(testReportID("test"))" }
                }
                """
            let report = try Report.decode(from: json)
            XCTAssertEqual(report.system?.appMemory?.memoryLevel, expected, "memory_level \(raw)")
            XCTAssertEqual(report.system?.appMemory?.memoryPressure, expected, "memory_pressure \(raw)")
        }
    }

    func testDecodeUnknownMemoryState() throws {
        let json = """
            {
                "crash": { "error": { "type": "signal" } },
                "system": {
                    "app_memory": {
                        "memory_level": "future_state"
                    }
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertEqual(report.system?.appMemory?.memoryLevel, .unknown("future_state"))
        XCTAssertEqual(report.system?.appMemory?.memoryLevel?.isUnknown, true)
    }

    func testDecodeAppMemoryAppTransitionStateIsTyped() throws {
        // AppMemoryInfo.appTransitionState used to be String?; verifying it now decodes
        // into the typed AppTransitionState enum, matching ApplicationStats.appTransitionState.
        let json = """
            {
                "crash": { "error": { "type": "signal" } },
                "system": {
                    "app_memory": {
                        "app_transition_state": "active"
                    }
                },
                "report": { "id": "\(testReportID("test"))" }
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertEqual(report.system?.appMemory?.appTransitionState, .active)
    }

    func testDecodeIsCleanExitAbsent() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": {
                        "type": "signal"
                    },
                    "threads": []
                },
                "report": { "id": "\(testReportID("test"))" },
                "system": {}
            }
            """

        let report = try Report.decode(from: json)
        XCTAssertNil(report.crash.error.isCleanExit)
    }

    func testAllExampleReportsDecodeWithKnownErrorType() throws {
        let resourceURL = Bundle.module.resourceURL!
        let jsonFiles = try FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        XCTAssertFalse(jsonFiles.isEmpty, "No JSON files found in resources")

        for fileURL in jsonFiles {
            let report = try Report.decode(from: fileURL)
            XCTAssertFalse(
                report.crash.error.type.isUnknown,
                "File \(fileURL.lastPathComponent) has unknown error type: \(report.crash.error.type.rawValue)"
            )
        }
    }
}
