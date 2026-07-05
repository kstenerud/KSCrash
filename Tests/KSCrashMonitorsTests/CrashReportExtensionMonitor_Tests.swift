//
//  CrashReportExtensionMonitor_Tests.swift
//
//  Created by Alexander Cohen on 2026-07-04.
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

import Darwin
import Foundation
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashReportModel
import XCTest

@testable import KSCrashMonitors

/// The corpse capture path validated in-process: "the corpse" is our own task, the crashed thread is
/// a worker parked in a semaphore wait, and the images are our own. A real extension does the same
/// against a foreign corpse port. What this covers: unwinding, thread walking, and the binary images
/// section all read the subject task and the provided image list. What it deliberately does not:
/// system/process/user report content describes the reporting process and is corrected by run-sidecar
/// stitching, and nothing here has run against a genuine foreign corpse yet.
final class CrashReportExtensionMonitor_Tests: XCTestCase {

    /// Install happens once per process, so the bridge that got registered (connected to the
    /// pipeline at install, with its host) must be shared by every test. This is the real
    /// extension flow: a corpse-reporting install into the process's own report area.
    private static var monitor: CrashReportExtensionMonitor { ExtensionReporting.bridge.monitor }
    private static let installRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
    /// Where the winning install writes reports. When the extension-reporting install wins the
    /// one-per-process race this is our own root; when another suite's normal install won, the
    /// bridge is attached to that live pipeline instead (the tolerated shared-install pattern)
    /// and reports land in that install's Reports directory, a sibling of its Runs directory.
    private static var reportsDirectory = installRoot.appendingPathComponent("Reports")

    private static let install: Bool = {
        var config = ExtensionReportingConfiguration(appName: "CorpseTestApp", appGroupIdentifier: "group.test")
        config.installPathOverride = installRoot.path
        do {
            try ExtensionReporting.install(with: config)
        } catch ExtensionReportingInstallError.install(.alreadyInstalled) {
            // Another suite installed first; the pipeline and a store both exist. Attach the
            // bridge to the live registry (its init reran with the real callbacks) and read
            // back from that install's report area.
            guard kscm_addMonitor(ExtensionReporting.bridge.api) else { return false }
            kscm_setMonitorEnabled(ExtensionReporting.bridge.api, true)
            guard let runs = kscrash_getRunSummariesPath() else { return false }
            reportsDirectory = URL(fileURLWithPath: String(cString: runs))
                .deletingLastPathComponent().appendingPathComponent("Reports")
        } catch {
            return false
        }
        return true
    }()

    /// The app later reads the extension's report area with its own store; the tests read the
    /// written file back the same way, by the id in its name.
    private static func readReport(_ id: Report.ID) throws -> [String: Any] {
        let dir = reportsDirectory
        let name = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(atPath: dir.path)
                .first { $0.contains(id.description) },
            "a report file named by the id should exist")
        var config = KSCrashReportStoreCConfiguration_Default()
        let cReportsPath = strdup(dir.path)
        config.reportsPath = UnsafePointer(cReportsPath)
        defer { free(cReportsPath) }
        // The config-bearing reader runs every stitch pass, including the final pass that
        // relocates the corpse snapshot; the path-only reader does not.
        let raw = try XCTUnwrap(kscrs_readReport(id.description, &config, nil))
        defer { free(raw) }
        let data = Data(bytes: raw, count: strlen(raw))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    override func setUpWithError() throws {
        XCTAssertTrue(Self.install, "extension-reporting install should succeed")
    }

    func testExtensionReportingInstallCreatesOnlyReportState() throws {
        try XCTSkipIf(
            Self.reportsDirectory != Self.installRoot.appendingPathComponent("Reports"),
            "another suite's normal install won the process; the reporter-only layout is not ours to assert")
        let exists = { (path: String) in
            FileManager.default.fileExists(atPath: Self.installRoot.appendingPathComponent(path).path)
        }
        XCTAssertTrue(exists("Reports"), "the report store must be initialized")
        XCTAssertFalse(exists("Data/last_run_id"), "no last-run chain in a reporter-only install")
        XCTAssertFalse(exists("Runs"), "no run summaries in a reporter-only install")
        XCTAssertFalse(exists("Data/ConsoleLog.txt"), "no console log in a reporter-only install")
    }

    func testWriteReportForOwnTaskProducesReadableCrashReport() throws {
        let worker = ParkedThread()
        defer { worker.release() }

        let reportID = try Self.monitor.writeReport(
            corpse: mach_task_self_,
            crashedThreadID: worker.machThreadID,
            images: Self.ownImages(),
            exception: EXC_BAD_ACCESS,
            code: UInt64(KERN_INVALID_ADDRESS),
            subcode: 0xDEAD_BEEF)

        let report = try Self.readReport(reportID)

        // The report is stamped with this run's ID (in the extension this is the ID loaded
        // from the corpse, so it stitches against the crashed run's sidecars).
        let info = try XCTUnwrap(report["report"] as? [String: Any])
        XCTAssertEqual(info["run_id"] as? String, String(cString: kscrash_getRunID()))

        // The error section carries the mach exception we were handed, typed like a report
        // the in-process Mach monitor would have written.
        let crash = try XCTUnwrap(report["crash"] as? [String: Any])
        let error = try XCTUnwrap(crash["error"] as? [String: Any])
        XCTAssertEqual(error["type"] as? String, "mach")
        let mach = try XCTUnwrap(error["mach"] as? [String: Any])
        XCTAssertEqual(mach["exception"] as? Int32, EXC_BAD_ACCESS)
        XCTAssertEqual(mach["code"] as? Int64, Int64(KERN_INVALID_ADDRESS))
        XCTAssertEqual(mach["subcode"] as? UInt64, 0xDEAD_BEEF)

        // The crashed thread is the one we said crashed, and it has a real backtrace.
        let threads = try XCTUnwrap(crash["threads"] as? [[String: Any]])
        XCTAssertGreaterThan(threads.count, 1, "sibling threads should be recorded too")
        let crashed = try XCTUnwrap(threads.first { $0["crashed"] as? Bool == true })
        // watchOS prohibits thread_suspend, so the live stand-in worker can't be frozen and
        // its state read; a real corpse's threads are already dead, so this gap is test-only.
        #if !os(watchOS)
            let backtrace = try XCTUnwrap(crashed["backtrace"] as? [String: Any])
            let frames = try XCTUnwrap(backtrace["contents"] as? [[String: Any]])
            XCTAssertGreaterThanOrEqual(frames.count, 3, "a parked worker has park/run/start frames at least")
        #endif

        // Binary images are present so the frames can be symbolicated server-side.
        let images = try XCTUnwrap(report["binary_images"] as? [[String: Any]])
        XCTAssertFalse(images.isEmpty)

        // Symbolication derives each image's slide as image_addr - image_vmaddr, so a zero
        // vmaddr silently misplaces every frame in that image. Check it against the in-process
        // reader for the same header rather than merely asserting non-zero.
        var compared = 0
        for image in images {
            let address = try XCTUnwrap(image["image_addr"] as? UInt64)
            let vmAddress = try XCTUnwrap(image["image_vmaddr"] as? UInt64)

            var truth = KSBinaryImage()
            guard let header = UnsafeRawPointer(bitPattern: UInt(address)),
                ksdl_binaryImageForHeader(header, nil, &truth)
            else { continue }

            XCTAssertEqual(vmAddress, truth.vmAddress, "image_vmaddr must match the in-process reader")
            XCTAssertEqual(image["image_size"] as? UInt64, truth.size)
            XCTAssertEqual(image["major_version"] as? UInt64, truth.majorVersion)
            XCTAssertEqual(image["minor_version"] as? UInt64, truth.minorVersion)
            XCTAssertEqual(image["revision_version"] as? UInt64, truth.revisionVersion)
            compared += 1
        }
        // Without this the loop would pass by comparing nothing, which is the failure mode
        // the check exists to rule out.
        XCTAssertGreaterThan(compared, 0, "no image was actually compared against the in-process reader")
    }

    func testSnapshotlessCaptureWritesNoMonitorSection() throws {
        let worker = ParkedThread()
        defer { worker.release() }

        // No snapshot means the monitor has nothing to write for this event. It must then add
        // no key at all: an empty "Corpse": {} is noise that every consumer has to special-case,
        // and it contradicts the documented "writes the report WITHOUT the monitor's section".
        let reportID = try Self.monitor.writeReport(
            corpse: mach_task_self_,
            crashedThreadID: worker.machThreadID,
            images: Self.ownImages(),
            exception: EXC_BAD_ACCESS,
            code: 0,
            subcode: 0)

        let report = try Self.readReport(reportID)
        let crash = try XCTUnwrap(report["crash"] as? [String: Any])
        let error = try XCTUnwrap(crash["error"] as? [String: Any])
        XCTAssertNil(
            (error["monitor_data"] as? [String: Any])?["Corpse"],
            "a monitor that writes nothing must not leave an empty section")
        XCTAssertNil(report["corpse"], "and the final-pass stitch has nothing to lift to the root")

        // The rest of the error section is unaffected, so the report is still well formed.
        XCTAssertNotNil(error["type"])
        XCTAssertNotNil(report["binary_images"])
    }

    func testWriteReportCorrectsLyingImageSizes() throws {
        let worker = ParkedThread()
        defer { worker.release() }

        // The extension hands shared-cache images sizes computed to the end of the cache,
        // gigabytes past the image. The capture must record the real __TEXT size from the
        // corpse's own header instead.
        var lied = Array(Self.ownImages().prefix(2))
        // Independent truth: the in-process reader's __TEXT size for the same headers.
        let realSizes: [UInt64] = lied.map { image in
            var binaryImage = KSBinaryImage()
            let header = UnsafeRawPointer(bitPattern: UInt(image.baseAddress))
            XCTAssertTrue(ksdl_binaryImageForHeader(header, image.path, &binaryImage))
            return binaryImage.size
        }
        for index in lied.indices {
            lied[index] = CorpseSnapshot.Image(
                path: lied[index].path, uuid: lied[index].uuid, baseAddress: lied[index].baseAddress,
                size: 6_000_000_000, cpuType: lied[index].cpuType, cpuSubType: lied[index].cpuSubType)
        }

        let reportID = try Self.monitor.writeReport(
            corpse: mach_task_self_,
            crashedThreadID: worker.machThreadID,
            images: lied,
            exception: EXC_CRASH,
            code: 0,
            subcode: 0)

        let report = try Self.readReport(reportID)
        let images = try XCTUnwrap(report["binary_images"] as? [[String: Any]])
        XCTAssertEqual(images.count, lied.count)
        let reportedByAddress = Dictionary(
            uniqueKeysWithValues: images.compactMap { image -> (UInt64, UInt64)? in
                guard let address = image["image_addr"] as? UInt64, let size = image["image_size"] as? UInt64 else {
                    return nil
                }
                return (address, size)
            })
        for (image, realSize) in zip(lied, realSizes) {
            let reported = try XCTUnwrap(reportedByAddress[image.baseAddress])
            XCTAssertEqual(reported, realSize, "the corpse's own header wins over the handed size")
            XCTAssertGreaterThan(reported, 0)
            XCTAssertLessThan(reported, 6_000_000_000)
        }
    }

    func testWriteReportListsExactlyTheProvidedImages() throws {
        let worker = ParkedThread()
        defer { worker.release() }

        // A subset of our real images (real, so the unwind image set builds); the report's
        // binary images section must contain exactly these, not this process's full list.
        let provided = Array(Self.ownImages().prefix(4))
        let reportID = try Self.monitor.writeReport(
            corpse: mach_task_self_,
            crashedThreadID: worker.machThreadID,
            images: provided,
            exception: EXC_CRASH,
            code: 0,
            subcode: 0)

        let report = try Self.readReport(reportID)
        let images = try XCTUnwrap(report["binary_images"] as? [[String: Any]])
        XCTAssertEqual(images.count, provided.count)
        let reportedNames = Set(images.compactMap { $0["name"] as? String })
        XCTAssertEqual(reportedNames, Set(provided.map { $0.path }))
        let reportedAddresses = Set(images.compactMap { ($0["image_addr"] as? UInt64) })
        XCTAssertEqual(reportedAddresses, Set(provided.map { $0.baseAddress }))
    }

    func testCaptureEmbedsSnapshotAndClassifiedError() throws {
        let worker = ParkedThread()
        defer { worker.release() }

        // A real kcdata code word is packed: signal 11, EXC_BAD_ACCESS, and the Mach code in
        // the low 20 bits, which is what the report must carry as mach.code.
        let crashInfo = CorpseSnapshot.CrashInfo(
            exceptionCode: 0x0B10_0001,
            exceptionSubcode: 0xBADF00D,
            signal: nil,
            machException: .EXC_BAD_ACCESS,
            subcode: 1,
            faultAddress: 0xDEAD,
            resource: nil,
            exitReason: nil,
            exitReasonDescription: nil,
            processName: "CorpseTestApp",
            pid: 4242,
            processPath: nil,
            crashedThreadID: worker.machThreadID,
            cpuType: nil,
            memoryLimitMB: nil)
        let snapshot = CorpseSnapshot(
            exception: .EXC_BAD_ACCESS,
            crashInfo: crashInfo,
            images: Self.ownImages())

        let reportID = try ExtensionReporting.captureCrashReport(snapshot: snapshot, corpse: mach_task_self_)

        let report = try Self.readReport(reportID)
        let crash = try XCTUnwrap(report["crash"] as? [String: Any])
        let error = try XCTUnwrap(crash["error"] as? [String: Any])

        // The crash facts come from the snapshot's kcdata.
        let mach = try XCTUnwrap(error["mach"] as? [String: Any])
        XCTAssertEqual(mach["exception"] as? Int32, EXC_BAD_ACCESS)
        XCTAssertEqual(mach["code"] as? UInt64, 1)
        XCTAssertEqual(mach["subcode"] as? UInt64, 0xBADF00D)

        // The decoded snapshot is written into the monitor's error section and lifted to the
        // report root by the final-pass stitch, which this read path runs.
        XCTAssertNil(error["monitor_data"], "the snapshot does not stay in the error section")
        let embedded = try XCTUnwrap(report["corpse"] as? [String: Any])
        let embeddedInfo = try XCTUnwrap(embedded["crashInfo"] as? [String: Any])
        XCTAssertEqual(embeddedInfo["pid"] as? UInt32, 4242)
        XCTAssertEqual(embeddedInfo["processName"] as? String, "CorpseTestApp")

        // The crashed thread is the worker, resolved from the snapshot's thread id.
        let threads = try XCTUnwrap(crash["threads"] as? [[String: Any]])
        XCTAssertNotNil(threads.first { $0["crashed"] as? Bool == true })
    }

    func testCaptureUsesKCDataSignalAndStampsProcessName() throws {
        let worker = ParkedThread()
        defer { worker.release() }

        // An EXC_CRASH corpse: the true signal (SIGABRT) lives in the kcdata exception
        // code's high byte, which the mach-exception mapping alone cannot recover.
        let crashInfo = CorpseSnapshot.CrashInfo(
            exceptionCode: UInt64(6) << 24,
            exceptionSubcode: 0,
            signal: .SIGABRT,
            machException: nil,
            subcode: nil,
            faultAddress: nil,
            resource: nil,
            exitReason: nil,
            exitReasonDescription: nil,
            processName: "CorpseTestApp",
            pid: 4242,
            processPath: nil,
            crashedThreadID: worker.machThreadID,
            cpuType: nil,
            memoryLimitMB: nil)
        let snapshot = CorpseSnapshot(
            exception: .EXC_CRASH,
            crashInfo: crashInfo,
            images: Self.ownImages())

        let reportID = try ExtensionReporting.captureCrashReport(snapshot: snapshot, corpse: mach_task_self_)

        let report = try Self.readReport(reportID)

        // The report names the corpse's process, not this (reporting) one.
        let info = try XCTUnwrap(report["report"] as? [String: Any])
        XCTAssertEqual(info["process_name"] as? String, "CorpseTestApp")

        // The kcdata signal wins over the mach-exception mapping (which gives 0 for EXC_CRASH).
        let crash = try XCTUnwrap(report["crash"] as? [String: Any])
        let error = try XCTUnwrap(crash["error"] as? [String: Any])
        let signal = try XCTUnwrap(error["signal"] as? [String: Any])
        XCTAssertEqual(signal["signal"] as? Int32, SIGABRT)

        // The embedded snapshot drops the image list; the report's binary_images carries it.
        let embedded = try XCTUnwrap(report["corpse"] as? [String: Any])
        XCTAssertEqual((embedded["images"] as? [Any])?.count, 0)
        XCTAssertFalse(try XCTUnwrap(report["binary_images"] as? [[String: Any]]).isEmpty)

        // The raw kcdata blob is never stored on a snapshot, so it cannot leak into a report.
        XCTAssertNil(embedded["kcdata"])
    }

    // The savesKCData debug dump: enabled, the saver writes the raw blob under
    // <installRoot>/KCData named by process/pid; disabled (the default), there is no saver at
    // all so captures skip the work.
    func testKCDataSaverWritesBlobWhenEnabled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var configuration = ExtensionReportingConfiguration(appName: "MyApp", appGroupIdentifier: "group.test")
        configuration.installPathOverride = root.path
        let previous = ExtensionReporting.activeConfiguration
        defer {
            ExtensionReporting.activeConfiguration = previous
            try? FileManager.default.removeItem(at: root)
        }

        ExtensionReporting.activeConfiguration = configuration
        XCTAssertNil(ExtensionReporting.kcdataSaver(), "off by default")

        configuration.savesKCData = true
        ExtensionReporting.activeConfiguration = configuration
        let saver = try XCTUnwrap(ExtensionReporting.kcdataSaver())

        let blob = Data([0xAB, 0xCD, 0xEF])
        let crashInfo = CorpseSnapshot.CrashInfo(exceptionCode: 0, exceptionSubcode: 0, processName: "Dead", pid: 7)
        saver(blob, crashInfo)

        let directory = try XCTUnwrap(configuration.kcdataDirectory)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let file = try XCTUnwrap(files.first { $0.hasPrefix("Dead-7-") && $0.hasSuffix(".kcdata") })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(file)), blob)
    }

    func testCaptureFailsWithoutCrashInfo() throws {
        let snapshot = CorpseSnapshot(
            exception: .EXC_CRASH,
            crashInfo: nil,
            images: Self.ownImages())
        XCTAssertThrowsError(try ExtensionReporting.captureCrashReport(snapshot: snapshot, corpse: mach_task_self_))
    }

    func testWriteReportFailsForAnUnknownCrashedThread() throws {
        XCTAssertThrowsError(
            try Self.monitor.writeReport(
                corpse: mach_task_self_,
                crashedThreadID: UInt64.max,
                images: Self.ownImages(),
                exception: EXC_CRASH,
                code: 0,
                subcode: 0))
    }

    // MARK: - Harness

    /// Our own images in the shape the extension gets them from CrashedProcess.binaryImages.
    private static func ownImages() -> [CorpseSnapshot.Image] {
        (0..<_dyld_image_count()).compactMap { i in
            guard let header = _dyld_get_image_header(i), let name = _dyld_get_image_name(i) else { return nil }
            return CorpseSnapshot.Image(
                path: String(cString: name), uuid: nil,
                baseAddress: UInt64(UInt(bitPattern: UnsafeRawPointer(header))),
                size: 0, cpuType: 0, cpuSubType: 0)
        }
    }
}

// MARK: - Final-pass stitch (the app-side overlay)

extension CrashReportExtensionMonitor_Tests {

    func testFinalStitchReplacesRunCachedValuesWithCorpseTruth() throws {
        var snapshot = CorpseSnapshot(images: [])
        snapshot.rusage = CorpseSnapshot.Rusage(physFootprint: 999)
        snapshot.vmInfo = CorpseSnapshot.VMInfo(
            virtualSize: 0, residentSize: 0, residentSizePeak: 0, reusable: 0,
            compressed: 0, compressedPeak: 0, compressedLifetime: 0, limitBytesRemaining: 333, regionCount: 0)
        snapshot.taskRole = TaskRole(rawValue: "TASK_FOREGROUND_APPLICATION")
        snapshot.crashInfo = CorpseSnapshot.CrashInfo(exceptionCode: 0, exceptionSubcode: 0)
        snapshot.crashInfo?.exitReason = CorpseSnapshot.CrashInfo.ExitReason(
            namespace: .OS_REASON_JETSAM, code: ExitReasonCode(rawValue: 10), flags: 4)

        // Through the real encoder, so the key spellings the overlay reads are the ones the
        // report actually embeds.
        let encoded = try JSONEncoder().encode(snapshot.forEmbedding())
        let snapshotDict = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        let report: [String: Any] = [
            "system": [
                "app_memory": ["memory_footprint": 111, "memory_remaining": 222, "memory_pressure": "normal"],
                "application_stats": ["task_role": "TASK_UNSPECIFIED"],
            ],
            "crash": ["error": ["type": "mach", "monitor_data": ["Corpse": ["snapshot": snapshotDict]]]],
        ]

        let stitched = try Self.monitor.stitchedReport(report, sidecarURL: nil, scope: .final)

        let system = try XCTUnwrap(stitched["system"] as? [String: Any])
        let appMemory = try XCTUnwrap(system["app_memory"] as? [String: Any])
        XCTAssertEqual(appMemory["memory_footprint"] as? UInt64, 999)
        XCTAssertEqual(appMemory["memory_remaining"] as? Int64, 333)
        XCTAssertEqual(appMemory["memory_pressure"] as? String, "normal", "keys the corpse cannot know stay stitched")
        let appStats = try XCTUnwrap(system["application_stats"] as? [String: Any])
        XCTAssertEqual(appStats["task_role"] as? String, "TASK_FOREGROUND_APPLICATION")

        let error = try XCTUnwrap((stitched["crash"] as? [String: Any])?["error"] as? [String: Any])
        let exitReason = try XCTUnwrap(error["exit_reason"] as? [String: Any])
        XCTAssertEqual(exitReason["namespace"] as? UInt32, 1)
        XCTAssertEqual(exitReason["code"] as? UInt64, 10)
        XCTAssertEqual(exitReason["flags"] as? UInt64, 4)
        XCTAssertNotNil(stitched["corpse"], "the snapshot survives the overlay, at the root")

        // A jetsam death reads exactly like the synthetic OOM narratives.
        XCTAssertEqual(error["termination_reason"] as? String, "memory_limit")
        XCTAssertEqual(error["subtype"] as? String, "memory_exception")
    }

    func testFinalStitchTagsWatchdogKillsAsHangs() throws {
        var snapshot = CorpseSnapshot(images: [])
        snapshot.crashInfo = CorpseSnapshot.CrashInfo(exceptionCode: 0, exceptionSubcode: 0)
        snapshot.crashInfo?.exitReason = CorpseSnapshot.CrashInfo.ExitReason(
            namespace: .OS_REASON_WATCHDOG, code: ExitReasonCode(rawValue: 0x8BAD_F00D))

        let encoded = try JSONEncoder().encode(snapshot.forEmbedding())
        let snapshotDict = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let report: [String: Any] = [
            "crash": ["error": ["type": "mach", "monitor_data": ["Corpse": ["snapshot": snapshotDict]]]]
        ]

        let stitched = try Self.monitor.stitchedReport(report, sidecarURL: nil, scope: .final)

        let error = try XCTUnwrap((stitched["crash"] as? [String: Any])?["error"] as? [String: Any])
        XCTAssertEqual(error["termination_reason"] as? String, "hang", "the same wire value the fakes use")
        XCTAssertNil(error["subtype"], "hangs carry no memory tag")
    }

    func testFinalStitchLeavesUnmappedNamespacesUntagged() throws {
        var snapshot = CorpseSnapshot(images: [])
        snapshot.crashInfo = CorpseSnapshot.CrashInfo(exceptionCode: 0, exceptionSubcode: 0)
        snapshot.crashInfo?.exitReason = CorpseSnapshot.CrashInfo.ExitReason(
            namespace: .OS_REASON_INVALID, code: ExitReasonCode(rawValue: 3))

        let encoded = try JSONEncoder().encode(snapshot.forEmbedding())
        let snapshotDict = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let report: [String: Any] = [
            "crash": ["error": ["type": "mach", "monitor_data": ["Corpse": ["snapshot": snapshotDict]]]]
        ]

        let stitched = try Self.monitor.stitchedReport(report, sidecarURL: nil, scope: .final)

        let error = try XCTUnwrap((stitched["crash"] as? [String: Any])?["error"] as? [String: Any])
        XCTAssertNil(error["termination_reason"], "no guess for namespaces without a certain mapping")
        XCTAssertNil(error["subtype"])
        XCTAssertNotNil(error["exit_reason"], "the raw exit reason is still recorded")
    }

    func testFinalStitchMovesTheSnapshotToTheReportRoot() throws {
        var snapshot = CorpseSnapshot(images: [])
        snapshot.taskRole = TaskRole(rawValue: "TASK_FOREGROUND_APPLICATION")

        let encoded = try JSONEncoder().encode(snapshot.forEmbedding())
        let snapshotDict = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let report: [String: Any] = [
            "crash": ["error": ["type": "mach", "monitor_data": ["Corpse": ["snapshot": snapshotDict]]]]
        ]

        let stitched = try Self.monitor.stitchedReport(report, sidecarURL: nil, scope: .final)

        XCTAssertEqual(stitched["corpse"] as? NSDictionary, snapshotDict as NSDictionary)
        let error = try XCTUnwrap((stitched["crash"] as? [String: Any])?["error"] as? [String: Any])
        XCTAssertNil(error["monitor_data"], "the snapshot moved, it was not copied")
        XCTAssertEqual(error["type"] as? String, "mach", "the rest of the error section is untouched")
    }

    func testStitchIgnoresNonFinalScopes() throws {
        let report: [String: Any] = ["a": 1]
        let out = try Self.monitor.stitchedReport(report, sidecarURL: nil, scope: .run)
        XCTAssertEqual(out as NSDictionary, report as NSDictionary)
    }

    func testFinalStitchWithoutSnapshotSectionIsUntouched() throws {
        let report: [String: Any] = ["crash": ["error": ["type": "mach"]]]
        let out = try Self.monitor.stitchedReport(report, sidecarURL: nil, scope: .final)
        XCTAssertEqual(out as NSDictionary, report as NSDictionary)
    }
}

/// A worker thread parked in a semaphore wait, suspended so its stack is frozen while the
/// writer unwinds it. This stands in for a corpse thread.
private final class ParkedThread {
    let machThreadID: UInt64
    private let thread: thread_t
    private let unpark = DispatchSemaphore(value: 0)

    init() {
        let parked = DispatchSemaphore(value: 0)
        var port: thread_t = 0
        var threadID: UInt64 = 0
        let waiter = unpark
        Thread.detachNewThread {
            port = mach_thread_self()
            var info = thread_identifier_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<thread_identifier_info>.stride / MemoryLayout<natural_t>.stride)
            _ = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                    thread_info(mach_thread_self(), thread_flavor_t(THREAD_IDENTIFIER_INFO), intPointer, &count)
                }
            }
            threadID = info.thread_id
            parked.signal()
            waiter.wait()
        }
        parked.wait()
        // The worker is now inside waiter.wait(), and stays there until release() signals, so
        // its stack is stable. The suspend on top is belt and braces where the API exists;
        // watchOS prohibits thread_suspend/thread_resume, so there the semaphore park is all.
        #if !os(watchOS)
            thread_suspend(port)
        #endif
        self.thread = port
        self.machThreadID = threadID
    }

    func release() {
        #if !os(watchOS)
            thread_resume(thread)
        #endif
        unpark.signal()
    }
}
