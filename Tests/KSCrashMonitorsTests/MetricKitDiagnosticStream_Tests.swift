//
//  MetricKitDiagnosticStream_Tests.swift
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

#if KSCRASH_HAS_METRICKIT_27_PLUS
    import MetricKit
#endif

// MARK: - Crash error, from either API

final class MetricKitCrashErrorTests: XCTestCase {

    func testMachExceptionKeepsSignalAndFaultAddress() {
        let error = makeCrashError(
            from: CrashDiagnosticFields(
                exceptionType: 1, exceptionCode: 1, signal: 11,
                virtualMemoryRegionInfo: "0x42 is not in any region.  Bytes before following region: 4340465598"),
            fallbackType: .user)
        XCTAssertEqual(error.type, .mach)
        XCTAssertEqual(error.mach?.exception, 1)
        XCTAssertEqual(error.mach?.code, 1)
        XCTAssertEqual(error.signal?.signal, 11)
        XCTAssertEqual(error.address, 0x42)
        XCTAssertNil(error.reason)
        XCTAssertEqual(error.isFatal, true)
        XCTAssertEqual(error.isCleanExit, false)
    }

    func testObjectiveCExceptionWinsOverMachAndSignal() {
        let error = makeCrashError(
            from: CrashDiagnosticFields(
                exceptionType: 10, exceptionCode: 0, signal: 6,
                exceptionName: "NSRangeException", exceptionMessage: "index 3 beyond bounds"),
            fallbackType: .user)
        XCTAssertEqual(error.type, .nsexception)
        XCTAssertEqual(error.nsexception?.name, "NSRangeException")
        XCTAssertEqual(error.nsexception?.reason, "index 3 beyond bounds")
        XCTAssertEqual(error.reason, "index 3 beyond bounds")
        XCTAssertEqual(error.mach?.exception, 10)
        XCTAssertEqual(error.signal?.signal, 6)
    }

    func testSignalWithoutMachException() {
        let error = makeCrashError(from: CrashDiagnosticFields(signal: 6), fallbackType: .user)
        XCTAssertEqual(error.type, .signal)
        XCTAssertNil(error.mach)
        XCTAssertEqual(error.signal?.signal, 6)
    }

    func testNoErrorFieldsKeepsTheFallbackType() {
        let error = makeCrashError(from: CrashDiagnosticFields(), fallbackType: .user)
        XCTAssertEqual(error.type, .user)
        XCTAssertNil(error.mach)
        XCTAssertNil(error.signal)
        XCTAssertNil(error.nsexception)
    }

    func testTerminationReasonCarriesTheExitCode() {
        let reason = "Namespace SPRINGBOARD, Code 0x8badf00d"
        let error = makeCrashError(
            from: CrashDiagnosticFields(exceptionType: 10, signal: 9, terminationReason: reason), fallbackType: .user)
        XCTAssertEqual(error.reason, reason)
        XCTAssertEqual(error.exitReason?.code, 0x8bad_f00d)
    }
}

// MARK: - 27 diagnostic stream

#if KSCRASH_HAS_METRICKIT_LEGACY

    final class MetricKitDiagnosticStreamTests: XCTestCase {

        /// A 27 runtime takes MetricKit data from the streams alone, everything else from the
        /// legacy subscriber alone.
        func testOneAPIPerProcess() {
            let monitor = MetricKitMonitor.plugin(.init()).monitor
            var expected = false
            #if KSCRASH_HAS_METRICKIT_27_PLUS
                if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                    expected = true
                }
            #endif
            XCTAssertEqual(monitor.usesDiagnosticStreams, expected)
        }

        #if KSCRASH_HAS_METRICKIT_27_PLUS

            // Reports the iOS 27.0.1 stream delivered on an iPhone 17 Pro, trimmed to the
            // attributed thread and one other, five frames deep. Fields and encoding are as
            // MetricKit delivered them.
            private static let sigsegvJSON =
                #"{"crashDiagnostic":{"callStackTree":{"binaryInfo":[{"name":"SwiftUI","uuid":"1D2A8243-1E78-3E43-AF2A-428BECD7EDD3"},{"name":"libsystem_kernel.dylib","uuid":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2"},{"name":"libdispatch.dylib","uuid":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE"},{"name":"Sample.debug.dylib","uuid":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36"}],"callStackPerThread":true,"callStackThreads":[{"rootFrames":[{"address":4352069264,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":2444944,"sampleCount":1,"subFrames":[{"address":4352065268,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":2440948,"sampleCount":1,"subFrames":[{"address":4349721468,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":97148,"sampleCount":1,"subFrames":[{"address":7144034696,"binaryUUID":"1D2A8243-1E78-3E43-AF2A-428BECD7EDD3","offsetIntoBinaryTextSegment":3858824,"sampleCount":1,"subFrames":[{"address":7144025612,"binaryUUID":"1D2A8243-1E78-3E43-AF2A-428BECD7EDD3","offsetIntoBinaryTextSegment":3849740,"sampleCount":1,"subFrames":[]}]}]}]}]}],"threadAttributed":true},{"rootFrames":[{"address":10049178704,"binaryUUID":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2","offsetIntoBinaryTextSegment":3152,"sampleCount":1,"subFrames":[{"address":7746488428,"binaryUUID":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE","offsetIntoBinaryTextSegment":14444,"sampleCount":1,"subFrames":[{"address":7746490192,"binaryUUID":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE","offsetIntoBinaryTextSegment":16208,"sampleCount":1,"subFrames":[{"address":4349882632,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":258312,"sampleCount":1,"subFrames":[{"address":4349881312,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":256992,"sampleCount":1,"subFrames":[]}]}]}]}]}],"threadAttributed":false}]},"exceptionCode":1,"exceptionType":1,"signal":11,"terminationCategory":"badAccess","virtualMemoryRegionInfo":"0x42 is not in any region.  Bytes before following region: 4340465598"},"environment":{"applicationBuildVersion":"1","applicationVersion":"1.0","bundleIdentifier":"com.github.kstenerud.KSCrash.Sample","deviceType":"iPhone18,1","isTestFlightApp":false,"lowPowerModeEnabled":false,"osVersion":{"buildNumber":"24A446","number":"27.0.1","platform":"iPhone OS"},"pid":51804,"platformArchitecture":"arm64e","regionFormat":"US","signpostData":[],"states":[]},"timeRange":{"begin":815241279.191,"end":815241279.191},"version":"2.0.0"}"#
            private static let abortJSON =
                #"{"crashDiagnostic":{"callStackTree":{"binaryInfo":[{"name":"libsystem_c.dylib","uuid":"28AF3269-1C11-3E0E-A0DE-3C428D05CEE6"},{"name":"libsystem_kernel.dylib","uuid":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2"},{"name":"libsystem_pthread.dylib","uuid":"694C772A-A9F8-3AC0-9417-7C304043A771"},{"name":"libdispatch.dylib","uuid":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE"},{"name":"Sample.debug.dylib","uuid":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36"}],"callStackPerThread":true,"callStackThreads":[{"rootFrames":[{"address":10049221116,"binaryUUID":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2","offsetIntoBinaryTextSegment":45564,"sampleCount":1,"subFrames":[{"address":6968759388,"binaryUUID":"694C772A-A9F8-3AC0-9417-7C304043A771","offsetIntoBinaryTextSegment":29788,"sampleCount":1,"subFrames":[{"address":7096916292,"binaryUUID":"28AF3269-1C11-3E0E-A0DE-3C428D05CEE6","offsetIntoBinaryTextSegment":497988,"sampleCount":1,"subFrames":[{"address":4376137640,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":2445224,"sampleCount":1,"subFrames":[{"address":4376133588,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":2441172,"sampleCount":1,"subFrames":[]}]}]}]}]}],"threadAttributed":true},{"rootFrames":[{"address":10049178704,"binaryUUID":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2","offsetIntoBinaryTextSegment":3152,"sampleCount":1,"subFrames":[{"address":7746488428,"binaryUUID":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE","offsetIntoBinaryTextSegment":14444,"sampleCount":1,"subFrames":[{"address":7746490192,"binaryUUID":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE","offsetIntoBinaryTextSegment":16208,"sampleCount":1,"subFrames":[{"address":4373950728,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":258312,"sampleCount":1,"subFrames":[{"address":4373944224,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":251808,"sampleCount":1,"subFrames":[]}]}]}]}]}],"threadAttributed":false}]},"exceptionCode":0,"exceptionType":10,"signal":6,"terminationCategory":"abnormal"},"environment":{"applicationBuildVersion":"1","applicationVersion":"1.0","bundleIdentifier":"com.github.kstenerud.KSCrash.Sample","deviceType":"iPhone18,1","isTestFlightApp":false,"lowPowerModeEnabled":false,"osVersion":{"buildNumber":"24A446","number":"27.0.1","platform":"iPhone OS"},"pid":51820,"platformArchitecture":"arm64e","regionFormat":"US","signpostData":[],"states":[]},"timeRange":{"begin":815241317.029,"end":815241317.029},"version":"2.0.0"}"#
            private static let memoryExceptionJSON =
                #"{"environment":{"applicationBuildVersion":"1","applicationVersion":"1.0","bundleIdentifier":"com.github.kstenerud.KSCrash.Sample","deviceType":"iPhone18,1","isTestFlightApp":false,"lowPowerModeEnabled":false,"osVersion":{"buildNumber":"24A446","number":"27.0.1","platform":"iPhone OS"},"pid":51807,"platformArchitecture":"arm64e","regionFormat":"US","signpostData":[],"states":[]},"memoryExceptionDiagnostic":{"callStackTree":{"binaryInfo":[{"name":"libsystem_platform.dylib","uuid":"39AE6F2B-B6BA-3116-9D5B-F97A6D41FF20"},{"name":"libsystem_kernel.dylib","uuid":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2"},{"name":"libdispatch.dylib","uuid":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE"},{"name":"CoreFoundation","uuid":"9426FC9A-B36C-3096-B836-D17D6744A75B"},{"name":"Sample.debug.dylib","uuid":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36"}],"callStackPerThread":true,"callStackThreads":[{"rootFrames":[{"address":10049178836,"binaryUUID":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2","offsetIntoBinaryTextSegment":3284,"sampleCount":1,"subFrames":[{"address":10049192712,"binaryUUID":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2","offsetIntoBinaryTextSegment":17160,"sampleCount":1,"subFrames":[{"address":10049192488,"binaryUUID":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2","offsetIntoBinaryTextSegment":16936,"sampleCount":1,"subFrames":[{"address":10049192052,"binaryUUID":"5A7DC6BE-551B-3B29-A928-A4079A90D4D2","offsetIntoBinaryTextSegment":16500,"sampleCount":1,"subFrames":[{"address":6969762924,"binaryUUID":"9426FC9A-B36C-3096-B836-D17D6744A75B","offsetIntoBinaryTextSegment":242796,"sampleCount":1,"subFrames":[]}]}]}]}]}],"threadAttributed":false},{"rootFrames":[{"address":7168211336,"binaryUUID":"39AE6F2B-B6BA-3116-9D5B-F97A6D41FF20","offsetIntoBinaryTextSegment":2440,"sampleCount":1,"subFrames":[{"address":4307849872,"binaryUUID":"CFEF15B8-240B-36F9-9D5A-D13DBEF22B36","offsetIntoBinaryTextSegment":2445968,"sampleCount":1,"subFrames":[{"address":7746481356,"binaryUUID":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE","offsetIntoBinaryTextSegment":7372,"sampleCount":1,"subFrames":[{"address":7746588596,"binaryUUID":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE","offsetIntoBinaryTextSegment":114612,"sampleCount":1,"subFrames":[{"address":7746558304,"binaryUUID":"8CDF4610-F6A5-39CB-94BF-687FE349A4BE","offsetIntoBinaryTextSegment":84320,"sampleCount":1,"subFrames":[]}]}]}]}]}],"threadAttributed":true}]}},"timeRange":{"begin":815241296.956,"end":815241296.956},"version":"2.0.0"}"#

            private func requireStreamRuntime() throws {
                guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else {
                    throw XCTSkip("the MetricKit 27 types need a 27 runtime")
                }
            }

            @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
            private func decode(_ json: String) throws -> DiagnosticReport {
                try JSONDecoder().decode(DiagnosticReport.self, from: Data(json.utf8))
            }

            @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
            private func crashDiagnostic(_ json: String) throws -> CrashDiagnostic {
                guard case .crash(let diagnostic) = try decode(json).result else {
                    throw XCTSkip("fixture is not a crash")
                }
                return diagnostic
            }

            func testBadAccessCrashFields() throws {
                try requireStreamRuntime()
                guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
                let fields = try crashDiagnostic(Self.sigsegvJSON).fields
                XCTAssertEqual(fields.exceptionType, 1)
                XCTAssertEqual(fields.exceptionCode, 1)
                XCTAssertEqual(fields.signal, 11)
                XCTAssertNil(fields.exceptionMessage)

                let error = makeCrashError(from: fields, fallbackType: .user)
                XCTAssertEqual(error.type, .mach)
                XCTAssertEqual(error.address, 0x42)
            }

            func testAbortCrashFields() throws {
                try requireStreamRuntime()
                guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
                let fields = try crashDiagnostic(Self.abortJSON).fields
                XCTAssertEqual(fields.exceptionType, 10)
                XCTAssertEqual(fields.exceptionCode, 0)
                XCTAssertEqual(fields.signal, 6)

                let error = makeCrashError(from: fields, fallbackType: .user)
                XCTAssertEqual(error.type, .mach)
                XCTAssertEqual(error.signal?.signal, 6)
            }

            func testCrashCallStackKeepsTheAttributedThreadAndBinaryNames() throws {
                try requireStreamRuntime()
                guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
                let tree = try crashDiagnostic(Self.sigsegvJSON).callStackTree.callStackRepresentation
                XCTAssertEqual(tree.callStacks.count, 2)
                XCTAssertEqual(tree.callStacks.first?.threadAttributed, true)
                XCTAssertEqual(tree.callStacks.first?.callStackRootFrames?.first?.binaryName, "Sample.debug.dylib")

                let data = buildCallStackData(from: tree)
                XCTAssertEqual(data.crashedThreadIndex, 0)
                XCTAssertEqual(data.threads.first?.backtrace?.contents.count, 5)
                XCTAssertEqual(
                    Set(data.binaryImages.map(\.name)),
                    ["Sample.debug.dylib", "SwiftUI", "libsystem_kernel.dylib", "libdispatch.dylib"])
            }

            func testSystemInfoComesFromTheEnvironment() throws {
                try requireStreamRuntime()
                guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
                let report = try decode(Self.sigsegvJSON)
                let system = makeSystemInfo(from: report.environment, processName: "Sample")
                XCTAssertEqual(system.processID, 51804)
                XCTAssertEqual(system.processName, "Sample")
                XCTAssertEqual(system.cfBundleIdentifier, "com.github.kstenerud.KSCrash.Sample")
                XCTAssertEqual(system.systemName, "iPhone OS")
                XCTAssertEqual(system.systemVersion, "27.0.1")
                XCTAssertEqual(system.osVersion, "24A446")
                XCTAssertEqual(system.machine, "iPhone18,1")
                XCTAssertEqual(system.buildType, .appStore)
            }

            func testCrashTimeRangeIsAnInstant() throws {
                try requireStreamRuntime()
                guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
                let range = try decode(Self.sigsegvJSON).timeRange
                XCTAssertEqual(range.start, range.end)
                XCTAssertEqual(range.end.timeIntervalSinceReferenceDate, 815_241_279.191, accuracy: 0.0005)
            }

            #if os(iOS) && !targetEnvironment(macCatalyst)
                func testMemoryExceptionCallStack() throws {
                    try requireStreamRuntime()
                    guard #available(iOS 27.0, *) else { return }
                    guard case .memoryException(let diagnostic) = try decode(Self.memoryExceptionJSON).result else {
                        return XCTFail("fixture should decode as a memory exception")
                    }
                    let data = buildCallStackData(from: diagnostic.callStackTree.callStackRepresentation)
                    XCTAssertEqual(data.crashedThreadIndex, 1)
                    XCTAssertEqual(data.threads.count, 2)
                }
            #endif

        #endif
    }

#endif
