//
//  Monitor_Tests.swift
//
//  Created by Alexander Cohen on 2026-07-11.
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

import KSCrashRecordingCore
import XCTest

@testable import KSCrashMonitorPlugins

/// The Monitor wrapper's C-facing lifecycle, driven the way the monitor pipeline drives it:
/// through the api table's function pointers. The payload roundtrip (host.handle →
/// writeReportSection) is covered end-to-end by the corpse capture tests.
final class Monitor_Tests: XCTestCase {

    final class TestMonitor: CrashMonitor {
        typealias EventPayload = String
        static let id = "TestMonitor"
        static let stitchPriority = 7

        let host: MonitorHost<String>
        var enabledChanges: [Bool] = []
        var postSystemEnables = 0

        init(host: MonitorHost<String>, configuration: Void) { self.host = host }
        func enabledDidChange(_ isEnabled: Bool) { enabledChanges.append(isEnabled) }
        func systemDidEnable() { postSystemEnables += 1 }
    }

    private func install(_ core: MonitorCore) {
        var callbacks = KSCrash_ExceptionHandlerCallbacks()
        withUnsafeMutablePointer(to: &callbacks) { core.api.pointee.`init`($0, core.api.pointee.context) }
    }

    func testIdentityComesFromTheMonitorType() {
        let monitor = Monitor(TestMonitor.self)
        let api = monitor.api.pointee
        XCTAssertEqual(api.monitorId(api.context).map { String(cString: $0) }, "TestMonitor")
        XCTAssertEqual(api.priority, 7)
        XCTAssertEqual(api.monitorFlags(api.context), .plugin)
    }

    final class OutOfRangePriorityMonitor: CrashMonitor {
        static let id = "OutOfRangePriorityMonitor"
        static let stitchPriority = Int.max
        init(host: MonitorHost<Void>, configuration: Void) {}
    }

    func testStitchPriorityIsClampedToTheTable() {
        // A conformer's Int is wider than the C table's int; constructing the plugin must not
        // trap on a value past it.
        let monitor = Monitor(OutOfRangePriorityMonitor.self)
        XCTAssertEqual(monitor.api.pointee.priority, Int32.max)
    }

    func testMonitorExistsBeforeInstall() {
        let monitor = Monitor(TestMonitor.self)
        XCTAssertFalse(monitor.isInstalled)
        _ = monitor.monitor  // non-optional: reachable immediately, eager instantiation.
        install(monitor)
        XCTAssertTrue(monitor.isInstalled)
    }

    func testWrapperOwnsEnabledStateAndNotifiesChangesOnce() {
        let monitor = Monitor(TestMonitor.self)
        let api = monitor.api.pointee
        install(monitor)

        XCTAssertFalse(api.isEnabled(api.context))
        api.setEnabled(true, api.context)
        api.setEnabled(true, api.context)  // repeat: state unchanged, no second notification
        api.setEnabled(false, api.context)

        XCTAssertEqual(monitor.monitor.enabledChanges, [true, false])
        XCTAssertFalse(api.isEnabled(api.context))
        XCTAssertFalse(monitor.monitor.host.isEnabled)

        api.notifyPostSystemEnable(api.context)
        XCTAssertEqual(monitor.monitor.postSystemEnables, 1)
    }

    final class ConfiguredMonitor: CrashMonitor {
        struct Options { let name: String }
        static let id = "ConfiguredMonitor"

        let host: MonitorHost<Void>
        let options: Options

        init(host: MonitorHost<Void>, configuration: Options) {
            self.host = host
            self.options = configuration
        }
    }

    func testConfigurationIsDeliveredAtInstantiation() {
        let monitor = Monitor(ConfiguredMonitor.self, .init(name: "configured"))
        install(monitor)
        XCTAssertEqual(monitor.monitor.options.name, "configured")
    }

    // The monitor exists from construction, so it hears every enabled change, even ones that
    // land before the bridge is installed.
    func testEnableBeforeInstallNotifiesTheMonitor() {
        let monitor = Monitor(TestMonitor.self)
        let api = monitor.api.pointee
        api.setEnabled(true, api.context)
        XCTAssertEqual(
            monitor.monitor.enabledChanges, [true],
            "the monitor exists from construction, so it hears every change")
    }

    func testRemovedMonitorLeavesTheRegistryAndItsIDFree() {
        do {
            let monitor = Monitor(TestMonitor.self)
            XCTAssertTrue(kscm_addMonitor(monitor.api))
            XCTAssertNotNil(kscm_getMonitor(TestMonitor.id))
            kscm_removeMonitor(monitor.api)
        }
        XCTAssertNil(kscm_getMonitor(TestMonitor.id))
        // The id is free again: a second bridge with the same id registers.
        let again = Monitor(TestMonitor.self)
        XCTAssertTrue(kscm_addMonitor(again.api))
        kscm_removeMonitor(again.api)
    }

    final class SectionMonitor: CrashMonitor {
        static let id = "SectionMonitor"
        init(host: MonitorHost<Void>, configuration: Void) {}
        func writeReportSection(payload: Void, writer: ReportSectionWriter) {
            writer.add("custom_key", "custom_value")
        }
    }

    func testReportSectionIsWrittenDirectlyIntoTheWritersFence() {
        // The crash-time writer opens the monitor's section itself (KSCrashReportC_Tests
        // pins that side). A bridge that opened a section of its own would double-nest
        // every section written through the layer.
        let bridge = Monitor(SectionMonitor.self)
        recordedWriterEvents = []
        var writer = makeRecordingWriter()
        var context = KSCrash_MonitorContext()
        withUnsafePointer(to: &context) { context in
            withUnsafePointer(to: &writer) { writer in
                bridge.api.pointee.writeInReportSection(context, writer, bridge.api.pointee.context)
            }
        }
        XCTAssertEqual(recordedWriterEvents, ["string custom_key=custom_value"])
    }

    final class ConfiguringSectionMonitor: CrashMonitor {
        static let id = "ConfiguringSectionMonitor"
        let host: MonitorHost<String>
        init(host: MonitorHost<String>, configuration: Void) { self.host = host }
        func writeReportSection(payload: String, writer: ReportSectionWriter) {
            writer.add("payload", payload)
        }
    }

    func testConfigureCannotClobberThePayloadBox() {
        // `configure` receives the raw context, and setting callbackContext on it is exactly
        // what the hand-rolled monitors did, so a port will reach for it. The box has to be
        // written after configure runs, or the write side reinterprets whatever was left
        // there as a PayloadBox.
        //
        // The section is written from inside handleWithResult, where the real pipeline
        // writes it: the box only lives for the duration of the handle call.
        let bridge = Monitor(ConfiguringSectionMonitor.self)
        var context = KSCrash_MonitorContext()
        var writer = makeRecordingWriter()
        var decoy = 0xDEAD_BEEF
        recordedWriterEvents = []

        withUnsafeMutablePointer(to: &context) { contextPointer in
            withUnsafePointer(to: &writer) { writerPointer in
                eventContext = contextPointer
                sectionWriterUnderTest = writerPointer
                bridgeUnderTest = bridge.api

                var callbacks = KSCrash_ExceptionHandlerCallbacks()
                callbacks.notify = { _, _ in eventContext }
                callbacks.handleWithResult = { ctx, _, _ in
                    // The report id is left unset, so handle() ends up throwing .notWritten.
                    // The section is written before that, which is all this test is about.
                    let api = bridgeUnderTest!
                    api.pointee.writeInReportSection(ctx, sectionWriterUnderTest, api.pointee.context)
                }
                withUnsafeMutablePointer(to: &callbacks) {
                    bridge.api.pointee.`init`($0, bridge.api.pointee.context)
                }

                withUnsafeMutableBytes(of: &decoy) { decoyBytes in
                    _ = try? bridge.monitor.host.handle(payload: "kept", requirements: .nonFatal) { ctx in
                        ctx.pointee.callbackContext = decoyBytes.baseAddress
                    }
                }
            }
        }
        XCTAssertEqual(recordedWriterEvents, ["string payload=kept"])
    }

    final class StitchMonitor: CrashMonitor {
        static let id = "StitchMonitor"
        let host: MonitorHost<Void>
        var shouldThrow = false
        init(host: MonitorHost<Void>, configuration: Void) { self.host = host }

        struct StitchError: Error {}
        func stitchedReport(
            _ report: [String: Any], sidecarURL: URL?, scope: SidecarScope
        ) throws -> [String: Any] {
            if shouldThrow { throw StitchError() }
            var stitched = report
            stitched["sidecar"] = sidecarURL?.lastPathComponent ?? "none"
            switch scope {
            case .report: stitched["scope"] = "report"
            case .run: stitched["scope"] = "run"
            case .final: stitched["scope"] = "final"
            }
            return stitched
        }
    }

    func testFinalScopeStitchHasNoSidecarURL() throws {
        let monitor = Monitor(StitchMonitor.self)
        let api = monitor.api.pointee
        install(monitor)

        let input = ["a": 1] as CFDictionary
        let stitched = api.createStitchedReport(input, nil, SidecarScope.final, api.context)
        let result = try XCTUnwrap(stitched?.takeRetainedValue() as? [String: Any])
        XCTAssertEqual(result["sidecar"] as? String, "none", "the final pass has no sidecar file")
        XCTAssertEqual(result["scope"] as? String, "final")
    }

    func testStitchModifiesTheReportAndThrowingAbortsIt() throws {
        let monitor = Monitor(StitchMonitor.self)
        let api = monitor.api.pointee
        install(monitor)

        let input = ["a": 1] as CFDictionary
        let stitched = "run.ksscr".withCString { path in
            api.createStitchedReport(input, path, SidecarScope.run, api.context)
        }
        let dict = try XCTUnwrap(stitched?.takeRetainedValue() as? [String: Any])
        XCTAssertEqual(dict["a"] as? Int, 1)
        XCTAssertEqual(dict["sidecar"] as? String, "run.ksscr")
        XCTAssertEqual(dict["scope"] as? String, "run")

        // A throwing stitch returns NULL: the store keeps the original (or aborts finalization).
        monitor.monitor.shouldThrow = true
        let failed = "run.ksscr".withCString { path in
            api.createStitchedReport(input, path, SidecarScope.report, api.context)
        }
        XCTAssertNil(failed)
    }

    func testDefaultStitchIsANoOp() throws {
        let monitor = Monitor(TestMonitor.self)
        let api = monitor.api.pointee
        install(monitor)

        let input = ["a": 1] as CFDictionary
        let out = "x.ksscr".withCString { path in
            api.createStitchedReport(input, path, SidecarScope.report, api.context)
        }
        let dict = try XCTUnwrap(out?.takeRetainedValue() as? [String: Any])
        XCTAssertEqual(dict["a"] as? Int, 1)
        XCTAssertEqual(dict.count, 1)
    }
}

// MARK: - Recording writer

/// What the bridge asked of a `ReportWriter`. File scope, because the writer's function
/// pointers must be non-capturing closures.
private nonisolated(unsafe) var recordedWriterEvents: [String] = []

/// The context `notify` hands back, for the same reason: the callbacks table's function
/// pointers must be non-capturing closures.
private nonisolated(unsafe) var eventContext: UnsafeMutablePointer<KSCrash_MonitorContext>?
private nonisolated(unsafe) var sectionWriterUnderTest: UnsafePointer<ReportWriter>?
private nonisolated(unsafe) var bridgeUnderTest: UnsafeMutablePointer<KSCrashMonitorAPI>?

private func makeRecordingWriter() -> ReportWriter {
    var writer = ReportWriter()
    writer.beginObject = { _, name in
        recordedWriterEvents.append("begin " + (name.map { String(cString: $0) } ?? ""))
    }
    writer.beginArray = { _, name in
        recordedWriterEvents.append("array " + (name.map { String(cString: $0) } ?? ""))
    }
    writer.endContainer = { _ in recordedWriterEvents.append("end") }
    writer.addStringElement = { _, name, value in
        recordedWriterEvents.append("string \(String(cString: name!))=\(String(cString: value!))")
    }
    return writer
}
