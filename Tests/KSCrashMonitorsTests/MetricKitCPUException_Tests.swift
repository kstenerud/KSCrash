//
//  MetricKitCPUException_Tests.swift
//
//  Created by Alexander Cohen on 2026-11-02.
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

    // The report a CPU exception becomes, built without storing it.
    final class MetricKitCPUExceptionTests: XCTestCase {

        // The shape of the CPU exception iOS 27.2 delivered on an iPhone 17 Pro, cut to two of its
        // seven app leaves: one merged thread whose root sits in every sample and whose leaves split
        // them. The app's own binary is missing from binaryInfo, so its frames have no name.
        private func deliveredTree() -> CallStackTreeRepresentation {
            let pthread = ("libsystem_pthread.dylib", "32E28303-2AAD-3166-9D11-70E8BCF8E076")
            func frame(
                _ address: UInt64, _ uuid: String, _ name: String?, _ offset: UInt64, _ count: Int,
                _ sub: [CallStackTreeRepresentation.Frame]? = nil
            ) -> CallStackTreeRepresentation.Frame {
                CallStackTreeRepresentation.Frame(
                    address: address, binaryUUID: uuid, binaryName: name, offsetIntoBinaryTextSegment: offset,
                    sampleCount: count, subFrames: sub)
            }
            let app = "0BCBEA7D-D37A-3F51-807F-510C6B7DA69B"
            let root = frame(
                6_587_906_320, pthread.1, pthread.0, 2319, 111,
                [
                    frame(4_369_502_320, app, nil, 2_461_808, 80),
                    frame(4_369_502_340, app, nil, 2_461_828, 31),
                ])
            return CallStackTreeRepresentation(callStacks: [.init(threadAttributed: nil, callStackRootFrames: [root])])
        }

        // The delivered diagnostic's range, which it shares with the watchdog crash delivered beside
        // it: it starts 18 s into the run and ends 37 s after the run did.
        private let timeRange = MetricKitTimeRange(
            begin: Date(timeIntervalSinceReferenceDate: 815_281_485.484),
            end: Date(timeIntervalSinceReferenceDate: 815_281_599.725))

        private func makeError(cpu: Double = 90.002322208, sampled: Double = 97.388729833) throws -> CrashError {
            try XCTUnwrap(
                MetricKitMonitor.makeCPUExceptionError(
                    callStackTree: deliveredTree(),
                    totalCPUTime: Measurement(value: cpu, unit: .seconds),
                    totalSampledTime: Measurement(value: sampled, unit: .seconds),
                    timeRange: timeRange))
        }

        func testCPUExceptionBecomesACPUUsageProfile() throws {
            let error = try makeError()
            XCTAssertEqual(error.type, .profile)
            XCTAssertEqual(error.subtype, .cpuUsage)
            XCTAssertEqual(error.isFatal, false)

            let profile = try XCTUnwrap(error.profile)
            XCTAssertEqual(profile.name, "com.kscrash.profile.cpu_usage")
            XCTAssertNil(profile.timeStartEpoch)
            XCTAssertEqual(profile.duration, 97_388_729_833)
            XCTAssertEqual(profile.frames.count, 3)
            XCTAssertEqual(profile.threads.count, 1)
            let counts = try XCTUnwrap(profile.threads.first).samples.map(\.count)
            XCTAssertEqual(counts.sorted(), [31, 80])
        }

        func testCPUExceptionMonitorDataCarriesTheTotalsAndRange() throws {
            let data = try XCTUnwrap(
                try makeError().monitorData(CPUExceptionMonitorData.self, for: MetricKitMonitor.id))
            XCTAssertEqual(data.kind, "cpu_exception")
            XCTAssertEqual(data.totalCPUTimeNs, 90_002_322_208)
            XCTAssertEqual(data.totalSampledTimeNs, 97_388_729_833)
            XCTAssertEqual(
                data.timeRange.end.timeIntervalSince1970, timeRange.end.timeIntervalSince1970, accuracy: 0.001)
        }

        func testUnmeasurableTimesLeaveThemOut() throws {
            let error = try makeError(cpu: .nan, sampled: -1)
            XCTAssertNil(error.profile?.duration)
            let data = try XCTUnwrap(try error.monitorData(CPUExceptionMonitorData.self, for: MetricKitMonitor.id))
            XCTAssertNil(data.totalCPUTimeNs)
            XCTAssertNil(data.totalSampledTimeNs)
        }
    }

    final class MetricKitTimeRangeTests: XCTestCase {

        // Milliseconds since 1970, so a backend compares them with a run summary's started_at_ms
        // and ended_at_ms as they are.
        func testEncodesBothEndsAsEpochMilliseconds() throws {
            let range = MetricKitTimeRange(
                begin: Date(timeIntervalSinceReferenceDate: 815_281_485.484),
                end: Date(timeIntervalSinceReferenceDate: 815_281_599.725))
            let object = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(range)) as? [String: Any])
            XCTAssertEqual(object["begin_ms"] as? Int64, 1_793_588_685_484)
            XCTAssertEqual(object["end_ms"] as? Int64, 1_793_588_799_725)
        }
    }

#endif
