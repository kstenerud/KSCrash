//
//  SidecarMetadataMonitorPluginTests.swift
//
//  Created by Alexander Cohen on 2025-12-14.
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
import KSCrashBootMonitor
import KSCrashDiskMonitor
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashRecordingCore
import XCTest

/// The provider handed to the plugins under test; file-scope so the C
/// callback below can stay non-capturing.
nonisolated(unsafe) private var providerDirectory = ""

private let testProvider: KSCrashSidecarRunPathProviderFunc = { monitorID, buffer, length in
    guard let monitorID, let buffer else { return false }
    let path = providerDirectory + "/" + String(cString: monitorID) + ".ksscr"
    return path.withCString { strlcpy(buffer, $0, length) < length }
}

nonisolated(unsafe) private var testCallbacks = KSCrash_ExceptionHandlerCallbacks()

final class SidecarMetadataMonitorPluginTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarMetadataMonitorPluginTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        providerDirectory = directory.path
        testCallbacks = KSCrash_ExceptionHandlerCallbacks()
        testCallbacks.getRunSidecarPath = testProvider
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func enable(_ plugin: any MonitorPlugin) {
        let api = plugin.api.pointee
        api.`init`(&testCallbacks, api.context)
        api.setEnabled(true, api.context)
    }

    /// Raw engine read, independent of the typed store under test.
    private func storedValues(monitorID: String) -> [String: UInt64] {
        let path = directory.appendingPathComponent(monitorID + ".ksscr").path
        guard let store = kskvs_create(path, KSKVSModeRead, nil, nil) else { return [:] }
        defer { kskvs_destroy(store) }
        final class Values {
            var byKey: [String: UInt64] = [:]
        }
        let values = Values()
        var callbacks = KSKVSCallbacks()
        callbacks.onUInt64 = { key, keyLength, value, context in
            guard let key else { return }
            let name = String(decoding: UnsafeRawBufferPointer(start: key, count: Int(keyLength)), as: UTF8.self)
            Unmanaged<Values>.fromOpaque(context!).takeUnretainedValue().byKey[name] = value
        }
        kskvs_iterate(store, &callbacks, Unmanaged.passUnretained(values).toOpaque())
        return values.byKey
    }

    private func stitched(_ plugin: any MonitorPlugin, monitorID: String, report: NSDictionary) -> NSDictionary? {
        let api = plugin.api.pointee
        let path = directory.appendingPathComponent(monitorID + ".ksscr").path
        return path.withCString { cPath in
            api.createStitchedReport(report as CFDictionary, cPath, KSCrashSidecarScopeRun, api.context)
        }.map { $0.takeRetainedValue() as NSDictionary }
    }

    func test_diskMonitor_wiresTheEventHook_andTogglesEnabled() throws {
        let plugin = DiskMonitor.plugin()
        XCTAssertEqual(String(cString: plugin.api.pointee.monitorId(plugin.api.pointee.context)!), "DiscSpace")
        // The values land in the System sidecar and SystemStitch delivers
        // them; both are covered by the System monitor tests. The plugin's
        // own surface is enablement and the event-time hook wiring.
        let hook = unsafeBitCast(plugin.api.pointee.addContextualInfoToEvent, to: UnsafeRawPointer?.self)
        let refresh =
            kscm_system_refreshFreeStorageAtEvent
            as (@convention(c) (UnsafeMutablePointer<KSCrash_MonitorContext>?, UnsafeMutableRawPointer?) -> Void)?
        XCTAssertEqual(hook, unsafeBitCast(refresh, to: UnsafeRawPointer?.self))

        enable(plugin)
        XCTAssertTrue(plugin.api.pointee.isEnabled(plugin.api.pointee.context))
        plugin.api.pointee.setEnabled(false, plugin.api.pointee.context)
        XCTAssertFalse(plugin.api.pointee.isEnabled(plugin.api.pointee.context))
    }

    func test_bootMonitor_recordsTheReservedKey_andStitchesBootTime() throws {
        let plugin = BootMonitor.plugin()
        XCTAssertEqual(String(cString: plugin.api.pointee.monitorId(plugin.api.pointee.context)!), "BootTime")
        enable(plugin)
        XCTAssertGreaterThan(storedValues(monitorID: "BootTime")["com.kscrash.boot.time"] ?? 0, 0)

        let report = try XCTUnwrap(stitched(plugin, monitorID: "BootTime", report: [:]))
        let bootTime = try XCTUnwrap((report["system"] as? NSDictionary)?["boot_time"] as? String)
        XCTAssertFalse(bootTime.isEmpty)
    }

    func test_corruptBootTimeSidecar_deliversTheReportUntouched() throws {
        // A torn sidecar can hold any bytes; a value past Int64.max must
        // read as absence at delivery, never trap the send.
        let path = directory.appendingPathComponent("BootTime.ksscr").path
        var config = KSKVSConfig(initialCapacity: 512, maxKeyLength: 64, maxStringLength: 64)
        let store = try XCTUnwrap(kskvs_create(path, KSKVSModeReadWriteCreate, &config, nil))
        XCTAssertTrue(kskvs_setUInt64(store, "com.kscrash.boot.time", UInt64.max))
        kskvs_destroy(store)

        let plugin = BootMonitor.plugin()
        let report = try XCTUnwrap(stitched(plugin, monitorID: "BootTime", report: [:]))
        XCTAssertNil((report["system"] as? NSDictionary)?["boot_time"])
    }

    func test_absentSidecar_deliversTheReportUntouched() throws {
        let plugin = BootMonitor.plugin()
        let report = try XCTUnwrap(stitched(plugin, monitorID: "BootTime", report: ["report": ["id": "x"]]))
        XCTAssertEqual(report, ["report": ["id": "x"]] as NSDictionary)
    }

    func test_plugins_areDistinctInstances() {
        XCTAssertTrue(DiskMonitor.plugin() !== DiskMonitor.plugin())
        XCTAssertTrue(BootMonitor.plugin() !== BootMonitor.plugin())
    }
}
