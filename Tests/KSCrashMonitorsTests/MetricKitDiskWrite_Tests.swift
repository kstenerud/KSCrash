//
//  MetricKitDiskWrite_Tests.swift
//
//  Created by Alexander Cohen on 2026-11-01.
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

@testable import KSCrashMonitors

#if KSCRASH_HAS_METRICKIT_LEGACY

    // The report a disk write exception becomes, built without storing it.
    final class MetricKitDiskWriteTests: XCTestCase {

        // The tree of a disk write exception iOS 27.2 delivered on an iPhone 17 Pro, as the stream
        // adapter turns it into a representation: one merged thread, seven frames, root first, every
        // frame in all twelve samples.
        private func deliveredTree() -> CallStackTreeRepresentation {
            let pthread = ("libsystem_pthread.dylib", "32E28303-2AAD-3166-9D11-70E8BCF8E076")
            let dispatch = ("libdispatch.dylib", "84B7E81D-B830-384F-A103-96323C6F5189")
            let kernel = ("libsystem_kernel.dylib", "26FFA906-5ACA-39BF-8F7C-94FE9AB8C657")
            let path: [(UInt64, (String, String), UInt64)] = [
                (6_587_906_320, pthread, 2319),
                (6_587_908_604, pthread, 4603),
                (7_370_445_028, dispatch, 86243),
                (7_370_443_104, dispatch, 84319),
                (7_370_473_396, dispatch, 114_611),
                (7_370_366_156, dispatch, 7371),
                (9_742_097_760, kernel, 28000),
            ]
            var frame: CallStackTreeRepresentation.Frame?
            for (address, binary, offset) in path.reversed() {
                frame = CallStackTreeRepresentation.Frame(
                    address: address, binaryUUID: binary.1, binaryName: binary.0,
                    offsetIntoBinaryTextSegment: offset, sampleCount: 12, subFrames: frame.map { [$0] })
            }
            return CallStackTreeRepresentation(callStacks: [.init(threadAttributed: nil, callStackRootFrames: [frame!])]
            )
        }

        func testDiskWriteBecomesADiskWritesProfile() throws {
            let error = try XCTUnwrap(
                MetricKitMonitor.makeDiskWriteError(
                    callStackTree: deliveredTree(),
                    totalBytesWritten: Measurement(value: 1074.716672, unit: .megabytes)))

            XCTAssertEqual(error.type, .profile)
            XCTAssertEqual(error.subtype, .diskWrites)
            XCTAssertEqual(error.isFatal, false)

            let profile = try XCTUnwrap(error.profile)
            XCTAssertEqual(profile.name, "com.kscrash.profile.disk_writes")
            XCTAssertNil(profile.duration)
            XCTAssertNil(profile.timeStartEpoch)
            XCTAssertEqual(profile.frames.count, 7)
            XCTAssertEqual(profile.frames.first?.objectName, "libsystem_pthread.dylib")
            XCTAssertEqual(profile.frames.last?.objectName, "libsystem_kernel.dylib")

            let thread = try XCTUnwrap(profile.threads.first)
            XCTAssertEqual(profile.threads.count, 1)
            XCTAssertTrue(thread.primary)
            XCTAssertEqual(thread.samples.count, 1)
            XCTAssertEqual(thread.samples.first?.count, 12)
            XCTAssertEqual(thread.samples.first?.frames, [6, 5, 4, 3, 2, 1, 0])

            XCTAssertEqual(
                try error.monitorData(DiskWriteMonitorData.self, for: MetricKitMonitor.id),
                DiskWriteMonitorData(kind: "disk_write_exception", totalBytesWritten: 1_074_716_672))
        }

        func testDiskWriteErrorRoundTrips() throws {
            let error = try XCTUnwrap(
                MetricKitMonitor.makeDiskWriteError(
                    callStackTree: deliveredTree(),
                    totalBytesWritten: Measurement(value: 1074.716672, unit: .megabytes)))
            let decoded = try JSONDecoder().decode(CrashError.self, from: JSONEncoder().encode(error))

            XCTAssertEqual(decoded.subtype, .diskWrites)
            XCTAssertEqual(decoded.profile, error.profile)
            XCTAssertEqual(
                try decoded.monitorData(DiskWriteMonitorData.self, for: MetricKitMonitor.id)?.totalBytesWritten,
                1_074_716_672)
        }

        func testUnmeasurableBytesLeaveTheTotalOut() throws {
            let error = try XCTUnwrap(
                MetricKitMonitor.makeDiskWriteError(
                    callStackTree: deliveredTree(), totalBytesWritten: Measurement(value: .nan, unit: .bytes)))
            let data = try XCTUnwrap(try error.monitorData(DiskWriteMonitorData.self, for: MetricKitMonitor.id))
            XCTAssertEqual(data.kind, "disk_write_exception")
            XCTAssertNil(data.totalBytesWritten)
        }
    }

    // Which MetricKit reports carry this app's device hash.
    final class MetricKitDeviceHashTests: XCTestCase {

        private let appHash = "da39a3ee5e6b4b0d3255bfef95601890afd80709"

        func testDeviceHashGoesOnTheAppsOwnDiagnostics() {
            XCTAssertEqual(
                deviceAppHash(forDiagnosticBundleID: "com.example.app", appBundleID: "com.example.app", hash: appHash),
                appHash)
        }

        func testDeviceHashStaysOffAnotherBundlesDiagnostic() {
            // An app extension's diagnostic delivered to its app: the app's hash would name the wrong runs.
            XCTAssertNil(
                deviceAppHash(
                    forDiagnosticBundleID: "com.example.app.widget", appBundleID: "com.example.app", hash: appHash))
        }

        func testDeviceHashGoesOnADiagnosticThatNamesNoBundle() {
            XCTAssertEqual(
                deviceAppHash(forDiagnosticBundleID: nil, appBundleID: "com.example.app", hash: appHash), appHash)
            XCTAssertEqual(
                deviceAppHash(forDiagnosticBundleID: "", appBundleID: "com.example.app", hash: appHash), appHash)
        }
    }

#endif
