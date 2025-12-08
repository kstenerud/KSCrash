//
//  CrashReportDecodingTests.swift
//
//  Created by KSCrash on 2024.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import XCTest

@testable import KSCrashDecoding

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
        XCTAssertEqual(report.crash.error.type, "mach")
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

        XCTAssertEqual(report.crash.error.type, "nsexception")
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

        XCTAssertEqual(report.system.cfBundleExecutable, "MyApp")
        XCTAssertEqual(report.system.cfBundleIdentifier, "com.example.myapp")
        XCTAssertEqual(report.system.cfBundleVersion, "1.0")
        XCTAssertEqual(report.system.cpuArch, "arm64")
        XCTAssertEqual(report.system.machine, "iPhone14,2")
        XCTAssertEqual(report.system.systemName, "iOS")
        XCTAssertEqual(report.system.systemVersion, "17.0")
        XCTAssertEqual(report.system.memory?.free, 133_308_416)
        XCTAssertEqual(report.system.memory?.size, 527_433_728)
    }

    func testDecodeUserData() throws {
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

        let report = try CrashReport.decode(from: json)

        XCTAssertNotNil(report.user)
        XCTAssertEqual(report.user?["key1"]?.stringValue, "string value")
        XCTAssertEqual(report.user?["key2"]?.intValue, 42)
        XCTAssertEqual(report.user?["key3"]?.boolValue, true)
        XCTAssertNotNil(report.user?["key4"]?.dictionaryValue)
    }

    func testDecodeRealNSExceptionReport() throws {
        let url = Bundle.module.url(forResource: "NSException", withExtension: "json")!
        let report = try CrashReport.decode(from: url)

        // Verify top-level structure
        XCTAssertEqual(report.report.id, "1DFC2552-8F7C-4D14-B0A8-5FE04E5AE35E")
        XCTAssertEqual(report.report.type, "standard")
        XCTAssertEqual(report.report.version?.major, 2)
        XCTAssertEqual(report.report.version?.minor, 0)

        // Verify crash info
        XCTAssertEqual(report.crash.error.type, "nsexception")
        XCTAssertEqual(report.crash.error.nsexception?.name, "NSInvalidArgumentException")
        XCTAssertNotNil(report.crash.error.nsexception?.reason)

        // Verify system info
        XCTAssertEqual(report.system.cfBundleExecutable, "Crash-Tester")
        XCTAssertEqual(report.system.cfBundleIdentifier, "org.stenerud.Crash-Tester")
        XCTAssertEqual(report.system.cpuArch, "armv7")
        XCTAssertEqual(report.system.machine, "iPhone3,1")

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
}
