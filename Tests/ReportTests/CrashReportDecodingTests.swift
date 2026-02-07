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

@testable import Report

final class CrashReportDecodingTests: XCTestCase {

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
                    "id": "test-id"
                },
                "system": {}
            }
            """

        let report = try CrashReport.decode(from: json)

        XCTAssertEqual(report.report.id, "test-id")
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
                "report": { "id": "test" },
                "system": {}
            }
            """

        let report = try CrashReport.decode(from: json)

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
                "report": { "id": "test" },
                "system": {}
            }
            """

        let report = try CrashReport.decode(from: json)

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
                "report": { "id": "test" },
                "system": {}
            }
            """

        let report = try CrashReport.decode(from: json)

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

    func testDecodeSystemInfo() throws {
        let json = """
            {
                "binary_images": [],
                "crash": {
                    "error": { "type": "mach" },
                    "threads": []
                },
                "report": { "id": "test" },
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

        let report = try CrashReport.decode(from: json)

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

    func testDecodeUserData() throws {
        struct TestUserData: Codable, Sendable {
            let key1: String
            let key2: Int
            let key3: Bool
            let key4: NestedData

            struct NestedData: Codable, Sendable {
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
                "report": { "id": "test" },
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
        let report = try JSONDecoder().decode(CrashReport<TestUserData>.self, from: data)

        XCTAssertNotNil(report.user)
        XCTAssertEqual(report.user?.key1, "string value")
        XCTAssertEqual(report.user?.key2, 42)
        XCTAssertEqual(report.user?.key3, true)
        XCTAssertEqual(report.user?.key4.nested, "value")
    }

    func testDecodeRealNSExceptionReport() throws {
        let url = Bundle.module.url(forResource: "NSException", withExtension: "json")!
        let report = try CrashReport.decode(from: url)

        // Verify top-level structure
        XCTAssertEqual(report.report.id, "1DFC2552-8F7C-4D14-B0A8-5FE04E5AE35E")
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

    private func decodeExampleReport(_ name: String) throws -> CrashReport<NoUserData> {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try CrashReport.decode(from: url)
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
        XCTAssertEqual(report.crash.error.hang?.hangStartRole, "FOREGROUND_APPLICATION")
        XCTAssertEqual(report.crash.error.hang?.hangEndNanos, 896_795_233_899_208)
        XCTAssertEqual(report.crash.error.hang?.hangEndRole, "FOREGROUND_APPLICATION")

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
        XCTAssertEqual(report.crash.error.hang?.hangStartRole, "FOREGROUND_APPLICATION")
        XCTAssertEqual(report.crash.error.hang?.hangEndNanos, 897_141_715_985_666)
        XCTAssertEqual(report.crash.error.hang?.hangEndRole, "FOREGROUND_APPLICATION")
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

        // Verify samples exist
        let samples = profile?.samples ?? []
        XCTAssertFalse(samples.isEmpty)

        // Verify each sample's frame indexes reference valid frames
        for (sampleIndex, sample) in samples.enumerated() {
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
                "report": { "id": "compact-test" },
                "system": {}
            }
            """

        let report = try CrashReport.decode(from: json)

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
                "report": { "id": "compact-referenced-only" },
                "system": {}
            }
            """

        let report = try CrashReport.decode(from: json)

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
                "report": { "id": "no-binary-images" },
                "system": {}
            }
            """

        let report = try CrashReport.decode(from: json)
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
                            "samples": [
                                {
                                    "time_start_uptime": 500000,
                                    "time_end_uptime": 510000,
                                    "duration": 10000,
                                    "frames": [0, 1]
                                }
                            ]
                        }
                    }
                },
                "report": { "id": "profile-uuid-test" },
                "system": {}
            }
            """

        let report = try CrashReport.decode(from: json)

        let profile = report.crash.error.profile
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.frames.count, 2)

        // Verify object_uuid is decoded on profile frames
        XCTAssertEqual(profile?.frames[0].objectUUID, "AABB1122-3344-5566-7788-99AABBCCDDEE")
        XCTAssertEqual(profile?.frames[0].objectName, "libsystem_pthread.dylib")
        XCTAssertEqual(profile?.frames[1].objectUUID, "FFEEDDCC-BBAA-9988-7766-554433221100")
        XCTAssertEqual(profile?.frames[1].objectName, "App")
    }

    func testAllExampleReportsDecodeWithKnownErrorType() throws {
        let resourceURL = Bundle.module.resourceURL!
        let jsonFiles = try FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        XCTAssertFalse(jsonFiles.isEmpty, "No JSON files found in resources")

        for fileURL in jsonFiles {
            let report = try CrashReport.decode(from: fileURL)
            XCTAssertFalse(
                report.crash.error.type.isUnknown,
                "File \(fileURL.lastPathComponent) has unknown error type: \(report.crash.error.type.rawValue)"
            )
        }
    }
}
