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
import KSCrashRecording
import KSCrashRecordingCore
import KSCrashReportModel
import XCTest

// Testable for `SidecarMetadata.reading`, the only way to open an existing
// file without truncating it.
@testable import KSCrashMonitorPlugins

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
    func test_keys_omitAStringRecordWhoseReadIsAbsence() throws {
        // Same rule as the JSON case below: value bytes that are not UTF-8
        // read as absence, so keys must not name the key either.
        let path = directory.appendingPathComponent("BrokenString.ksscr").path
        var config = KSKVSConfig(initialCapacity: 512)
        let raw = try XCTUnwrap(kskvs_create(path, KSKVSModeReadWriteCreate, &config, nil))
        XCTAssertTrue(kskvs_setString(raw, "good", "v"))
        let invalidUTF8: [CChar] = [CChar(bitPattern: 0xC3), 0x28, 0]
        XCTAssertTrue(invalidUTF8.withUnsafeBufferPointer { kskvs_setString(raw, "bad", $0.baseAddress) })
        kskvs_destroy(raw)

        let store = try XCTUnwrap(SidecarMetadata.reading(at: path))
        XCTAssertNil(store["bad"] as String?)
        XCTAssertEqual(store.keys, ["good"])
    }

    func test_foreignNonFiniteDouble_readsAsAbsence() throws {
        // The write path refuses these, but a foreign writer, or a build that
        // predates that guard, can leave one on disk. Reading it as a value
        // would put `1e999` in the report and make the whole thing
        // undeliverable, so the read calls it absence too.
        let path = directory.appendingPathComponent("ForeignDouble.ksscr").path
        var config = KSKVSConfig(initialCapacity: 512)
        let raw = try XCTUnwrap(kskvs_create(path, KSKVSModeReadWriteCreate, &config, nil))
        XCTAssertTrue(kskvs_setString(raw, "good", "v"))
        XCTAssertTrue(kskvs_setDouble(raw, "inf", .infinity))
        XCTAssertTrue(kskvs_setDouble(raw, "nan", .nan))
        kskvs_destroy(raw)

        let store = try XCTUnwrap(SidecarMetadata.reading(at: path))
        XCTAssertNil(store["inf"] as Double?)
        XCTAssertNil(store["nan"] as Double?)
        XCTAssertEqual(store.keys, ["good"])
    }

    func test_fullStore_refusedWrite_leavesTheKeyAbsentNotStale() throws {
        // At the ceiling the replacement cannot be written and neither can a
        // removal record, so the key is cleared in place. Without that it
        // would go on serving the value the app believes it replaced.
        let path = directory.appendingPathComponent("Full.ksscr").path
        // Grown into the ceiling by writing, so the test does not have to
        // name it.
        let store = try SidecarMetadata.creating(at: path, config: KSKVSConfig(initialCapacity: 4096))

        let key = try XCTUnwrap(fillToCeiling(store), "the store never filled")

        store[key] = String(repeating: "w", count: 60000)
        XCTAssertNil(store[key] as String?)
        XCTAssertFalse(store.keys.contains(key))
    }

    func test_containerTooDeepForTheReport_readsAsAbsence() throws {
        // Foundation decodes far deeper than the report encoder can write,
        // and the report writes a stored container two containers down, at
        // report -> "user" -> key. Judged against Foundation's own limit
        // instead, this reader would call a value what the report stitch
        // drops, so `keys`, the getter and the run summary would all carry a
        // key the report does not have.
        let path = directory.appendingPathComponent("Deep.ksscr").path
        let store = try SidecarMetadata.creating(at: path, config: KSKVSConfig(initialCapacity: 4096))

        func nested(levels: Int) -> MetadataValue {
            var value = MetadataValue.array([])
            for _ in 1..<levels {
                value = .array([value])
            }
            return value
        }

        store["deep"] = nested(levels: Int(KSKVS_MAX_VALUE_DEPTH) + 1)
        store["fits"] = nested(levels: Int(KSKVS_MAX_VALUE_DEPTH))
        store["good"] = "v"

        XCTAssertNil(store["deep"] as MetadataValue?)
        XCTAssertNotNil(store["fits"] as MetadataValue?)
        XCTAssertEqual(store.keys, ["fits", "good"])
    }

    func test_containerCarryingAnEmbeddedNUL_readsAsAbsence() throws {
        // This reader keeps the whole string; the report's C codec builds
        // NUL-terminated ones, so it would keep a prefix and collapse two
        // member names differing only past the NUL. Neither can be talked out
        // of its string handling, so the record is absence to both rather than
        // a value they read differently.
        let path = directory.appendingPathComponent("NUL.ksscr").path
        let store = try SidecarMetadata.creating(at: path, config: KSKVSConfig(initialCapacity: 512))

        store["nul"] = MetadataValue.object(["a\0b": .integer(1), "a\0c": .integer(2)])
        store["value"] = MetadataValue.array([.string("plain\0text")])
        // A literal backslash before u0000 escapes nothing, so this is a value.
        store["literal"] = MetadataValue.object([#"a\u0000b"#: .integer(1)])
        store["good"] = "v"

        XCTAssertNil(store["nul"] as MetadataValue?)
        XCTAssertNil(store["value"] as MetadataValue?)
        XCTAssertNotNil(store["literal"] as MetadataValue?)
        XCTAssertEqual(store.keys, ["good", "literal"])
    }

    func test_keys_omitAJSONRecordWhoseReadIsAbsence() throws {
        // The writer checks only the opening byte, so bytes that open a
        // container but do not decode can reach a file (a torn or foreign
        // record); keys must not list what the getter reads as absence.
        let path = directory.appendingPathComponent("Broken.ksscr").path
        var config = KSKVSConfig(initialCapacity: 512)
        let raw = try XCTUnwrap(kskvs_create(path, KSKVSModeReadWriteCreate, &config, nil))
        XCTAssertTrue(kskvs_setString(raw, "good", "v"))
        XCTAssertTrue("{broken".withCString { kskvs_setJSON(raw, "bad", $0, strlen($0)) })
        kskvs_destroy(raw)

        let store = try XCTUnwrap(SidecarMetadata.reading(at: path))
        XCTAssertEqual(store.keys, ["good"])
        XCTAssertNil(store["bad"] as MetadataValue?)
    }

    func test_nonFiniteDouble_isAbsence_andDoesNotPoisonTheRecord() throws {
        // JSON carries no infinity or NaN: the C encoder writes `1e999` and
        // `null` for them, which a strict reader rejects, so one accepted here
        // would make every report and summary of the run undeliverable.
        let path = directory.appendingPathComponent("NonFinite.ksscr").path
        let store = try SidecarMetadata.creating(at: path, config: KSKVSConfig(initialCapacity: 512))
        store["ratio"] = 1.5
        store["ratio"] = Double.infinity
        XCTAssertNil(store["ratio"] as Double?)

        store["nan"] = Double.nan
        XCTAssertNil(store["nan"] as Double?)
        XCTAssertEqual(store.keys, [])

        // The scalar and container paths agree; neither stores one.
        store["nested"] = MetadataValue.object(["r": .double(.infinity)])
        XCTAssertNil(store["nested"] as MetadataValue?)

        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("1e999"))
    }

    func test_refusedWrite_removesTheKeyRatherThanKeepingTheOldValue() throws {
        // A refusal is data-dependent, not programmer error. The app believes
        // it replaced the value, so the old one must not go on being served.
        let path = directory.appendingPathComponent("TooBig.ksscr").path
        let store = try SidecarMetadata.creating(at: path, config: KSKVSConfig(initialCapacity: 512))
        store["blob"] = "small"
        XCTAssertEqual(store["blob"] as String?, "small")

        store["blob"] = String(repeating: "x", count: 70000)
        XCTAssertNil(store["blob"] as String?)
        XCTAssertEqual(store.keys, [])
    }

    func test_null_isAbsence() throws {
        // The same contract Metadata honors: .null removes the key, and null
        // members and elements resolve to absence on read. The write stores
        // the container as given (the write path does no cleanup); it is the
        // readers that drop the nulls.
        let path = directory.appendingPathComponent("Nulls.ksscr").path
        let store = try SidecarMetadata.creating(at: path, config: KSKVSConfig(initialCapacity: 512))
        store["gone"] = "value"
        store["gone"] = MetadataValue.null
        XCTAssertNil(store["gone"] as MetadataValue?)
        store["mixed"] = MetadataValue.object(["kept": .integer(1), "dropped": .null])
        XCTAssertEqual(store["mixed"] as MetadataValue?, .object(["kept": .integer(1)]))
        store["list"] = MetadataValue.array([.string("a"), .null, .object(["x": .null])])
        XCTAssertEqual(store["list"] as MetadataValue?, .array([.string("a"), .object([:])]))
        XCTAssertEqual(store.keys, ["list", "mixed"])

        // The persisted bytes keep the nulls; a fresh reader strips them too.
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("null"))
        let read = try XCTUnwrap(SidecarMetadata.reading(at: path))
        XCTAssertEqual(read["mixed"] as MetadataValue?, .object(["kept": .integer(1)]))
        XCTAssertEqual(read.keys, ["list", "mixed"])
    }

    /// Fill `store` to its ceiling with distinct keys, so compaction has
    /// nothing to reclaim. Returns the last key that fit.
    ///
    /// The tail matters: big records alone leave tens of kilobytes of slack,
    /// room enough for a removal record, so the in-place removal the ceiling
    /// exists to exercise never runs. The ladder spends that slack down below
    /// one empty record. The same shape as `fillToCeiling` in
    /// KSKeyValueStore_Tests.m, which exercises the engine directly; the two
    /// test targets share no code.
    private func fillToCeiling(_ store: SidecarMetadata) -> String? {
        let value = String(repeating: "v", count: 60000)
        var lastKey: String?
        var index = 0
        while index < 1000 {
            let key = "key\(index)"
            store[key] = value
            guard store[key] as String? != nil else { break }
            lastKey = key
            index += 1
        }

        var padSize = 32768
        while true {
            let pad = String(repeating: "p", count: padSize)
            while index < 100_000 {
                let padKey = "pad\(index)"
                store[padKey] = pad
                guard store[padKey] as String? != nil else { break }
                index += 1
            }
            if padSize == 0 { break }
            padSize /= 2
        }
        return lastKey
    }

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
            api.createStitchedReport(report as CFDictionary, cPath, SidecarScope.run, api.context)
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

    /// A scratch plugin on the base, standing in for a third-party recorder:
    /// the shipped monitors record through the System sidecar, so the base's
    /// own record/stitch path is covered here directly.
    private func makeBasePlugin() -> any MonitorPlugin {
        SidecarMetadataMonitorPlugin(
            monitorID: "TestSidecar",
            record: { store in store["com.kscrash.test.value"] = UInt64(42) },
            poller: nil,
            stitch: { values, system in
                if let value: UInt64 = values["com.kscrash.test.value"] {
                    system["test_value"] = value
                }
            })
    }

    func test_bootMonitor_wiresTheSystemRecording_andTogglesEnabled() throws {
        let plugin = BootMonitor.plugin()
        XCTAssertEqual(String(cString: plugin.api.pointee.monitorId(plugin.api.pointee.context)!), "BootTime")
        // The value lands in the System sidecar via kscm_system_setBootTime
        // and SystemStitch delivers it; both are covered by the System
        // monitor tests. The plugin's own surface is enablement and the
        // post-monitors-enabled recording hook.
        enable(plugin)
        XCTAssertTrue(plugin.api.pointee.isEnabled(plugin.api.pointee.context))
        plugin.api.pointee.notifyPostMonitorsEnabled?(plugin.api.pointee.context)
        plugin.api.pointee.setEnabled(false, plugin.api.pointee.context)
        XCTAssertFalse(plugin.api.pointee.isEnabled(plugin.api.pointee.context))
    }

    func test_basePlugin_recordsTheKey_andStitchesIt() throws {
        let plugin = makeBasePlugin()
        // Plugins never count toward the registry's any-monitor-active gate.
        XCTAssertEqual(plugin.api.pointee.monitorFlags(plugin.api.pointee.context), MonitorFlags.plugin)
        enable(plugin)
        XCTAssertEqual(storedValues(monitorID: "TestSidecar")["com.kscrash.test.value"], 42)

        let report = try XCTUnwrap(stitched(plugin, monitorID: "TestSidecar", report: [:]))
        let value = try XCTUnwrap((report["system"] as? NSDictionary)?["test_value"] as? UInt64)
        XCTAssertEqual(value, 42)
    }

    func test_absentSidecar_deliversTheReportUntouched() throws {
        let plugin = makeBasePlugin()
        let report = try XCTUnwrap(stitched(plugin, monitorID: "TestSidecar", report: ["report": ["id": "x"]]))
        XCTAssertEqual(report, ["report": ["id": "x"]] as NSDictionary)
    }

    func test_plugins_areDistinctInstances() {
        XCTAssertTrue(DiskMonitor.plugin() !== DiskMonitor.plugin())
        XCTAssertTrue(BootMonitor.plugin() !== BootMonitor.plugin())
    }
}
