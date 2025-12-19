//
//  Profile.Report.swift
//
//  Created by Alexander Cohen on 2025-12-17.
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

#if SWIFT_PACKAGE
    import KSCrashRecording
    import KSCrashRecordingCore
#endif

// MARK: - Profile Report Writing

/// Extension that provides crash report writing functionality for profiles.
///
/// This extension registers a custom KSCrash monitor that allows profiles to be written
/// as crash reports. The report format uses frame deduplication to minimize file size:
/// - Unique frames are collected and symbolicated once
/// - Each sample references frames by index rather than duplicating addresses
///
/// ## Report Structure
///
/// The profile section in the crash report contains:
/// - `name`: The profile name
/// - `id`: Unique profile identifier (UUID)
/// - `time_start_epoch`: Wall-clock start time in nanoseconds since epoch
/// - `time_start_uptime`: Monotonic start timestamp
/// - `time_end_uptime`: Monotonic end timestamp
/// - `duration`: Profile duration in nanoseconds
/// - `frames`: Array of unique symbolicated frames
/// - `samples`: Array of samples, each referencing frames by index
extension Profile {

    /// Writes this profile to a crash report file.
    ///
    /// This method triggers the KSCrash report writing machinery to generate a JSON report
    /// containing the profile data. The report is written synchronously to the KSCrash
    /// reports directory.
    ///
    /// The profile data is passed to the monitor's `writeInReportSection` callback via
    /// the `callbackContext` field in the monitor context.
    ///
    /// - Returns: The URL of the written report file, or `nil` if the report could not be written.
    func writeReport() -> URL? {

        let api = ProfileMonitor.api
        guard let callbacks = ProfileMonitor.callbacks else {
            return nil
        }

        let requirements = KSCrash_ExceptionHandlingRequirements(
            shouldRecordAllThreads: 0,
            shouldWriteReport: 1,
            isFatal: 0,
            asyncSafety: 0,
            asyncSafetyBecauseThreadsSuspended: 0,
            crashedDuringExceptionHandling: 0,
            shouldExitImmediately: 0
        )

        let context = callbacks.notify(thread, requirements)
        kscm_fillMonitorContext(context, api)
        let callbackContext = Unmanaged.passRetained(BoxedProfile(self)).toOpaque()
        defer {
            Unmanaged<BoxedProfile>.fromOpaque(callbackContext).release()
        }
        context?.pointee.callbackContext = callbackContext

        var result = KSCrash_ReportResult()
        callbacks.handleWithResult(context, &result)

        let path = withUnsafePointer(to: &result.path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(PATH_MAX)) {
                String(cString: $0)
            }
        }

        guard !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }
}

// MARK: - BoxedProfile

/// A class wrapper around `Profile` for passing through C callbacks.
///
/// Since `Profile` is a struct, we need a reference type to pass through the
/// `void*` context in the monitor callbacks. This class boxes the profile and
/// provides the `write(with:)` method to serialize it to JSON.
private class BoxedProfile {
    let profile: Profile

    init(_ profile: Profile) {
        self.profile = profile
    }

    /// Writes the profile data to the report using the given writer.
    ///
    /// The output format uses frame deduplication:
    /// 1. Collect all unique addresses from all samples
    /// 2. Symbolicate each unique address once
    /// 3. Build a lookup table mapping address -> index
    /// 4. Write frames array with symbolicated info
    /// 5. Write samples array with frame indexes instead of addresses
    ///
    /// - Parameter writer: The report writer to use for JSON output.
    func write(with writer: UnsafeReportWriter) {

        let addresses = Array(Set(profile.samples.flatMap(\.addresses)))
            .sorted()
            .compactMap {
                var info = SymbolInformation()
                if quickSymbolicate(address: $0, result: &info) {
                    return info
                }
                return nil
            }

        let addressToIndex = Dictionary(uniqueKeysWithValues: addresses.enumerated().map { ($1.returnAddress, $0) })

        let indexedSamples: [(indexes: [Int], sample: any Sample)] = profile.samples.map { sample in
            let indexes = sample.addresses.compactMap { address in
                addressToIndex[address]
            }
            return (indexes, sample)
        }

        writer.add("name", profile.name)
        writer.add("id", profile.id.uuidString)
        writer.add("time_start_epoch", UInt64(profile.startTime.timeIntervalSince1970 * 1_000_000_000.0))
        writer.add("time_start_uptime", profile.startTimestampNs)
        writer.add("time_end_uptime", profile.endTimestampNs)
        writer.add("expected_sample_interval", profile.expectedSampleIntervalNs)
        writer.add("duration", profile.durationNs)
        writer.add("time_units", "nanoseconds")

        writer.beginArray("frames")
        for address in addresses {
            writer.beginObject(nil)

            if let symbolName = address.symbolName {
                writer.add("symbol_name", String(cString: symbolName))
            }
            writer.add("symbol_addr", UInt64(address.symbolAddress))
            writer.add("instruction_addr", UInt64(address.callInstruction))
            if let imageName = address.imageName {
                let name = URL(fileURLWithPath: String(cString: imageName)).lastPathComponent
                writer.add("object_name", name)
            }
            writer.add("object_addr", UInt64(address.imageAddress))

            writer.endContainer()
        }
        writer.endContainer()

        writer.beginArray("samples")
        for (indexes, sample) in indexedSamples {

            writer.beginObject(nil)
            writer.add("time_start_uptime", sample.metadata.timestampBeginNs)
            writer.add("time_end_uptime", sample.metadata.timestampEndNs)
            writer.add("duration", sample.metadata.captureDurationNs)

            writer.beginArray("frames")
            for index in indexes {
                writer.add(nil, UInt64(index))
            }
            writer.endContainer()

            writer.endContainer()
        }
        writer.endContainer()
    }
}

// MARK: - Profile Monitor API Functions

final private class ProfileMonitor: Sendable {

    static private let lock = UnfairLock()

    /// Whether the profile monitor is enabled.
    static private var _enabled: Bool = true
    static var enabled: Bool {
        set {
            lock.withLock { _enabled = newValue }
        }
        get {
            lock.withLock { _enabled }
        }
    }

    /// The monitor ID string. Allocated once and never freed (intentional for static lifetime).
    static private let _monitorId = strdup("profile")
    static var monitorId: UnsafePointer<CChar>? {
        lock.withLock { _monitorId.map { UnsafePointer($0) } }
    }

    /// Cached exception handler callbacks from KSCrash initialization.
    static private var _callbacks: KSCrash_ExceptionHandlerCallbacks? = nil
    static var callbacks: KSCrash_ExceptionHandlerCallbacks? {
        set {
            lock.withLock { _callbacks = newValue }
        }
        get {
            lock.withLock { _callbacks }
        }
    }

    /// The KSCrash monitor API for profile reports. Lazily initialized and registered.
    static let api: UnsafeMutablePointer<KSCrashMonitorAPI> = {
        var api = KSCrashMonitorAPI(
            init: profileMonitorInit,
            monitorId: profileMonitorGetId,
            monitorFlags: profileMonitorGetFlags,
            setEnabled: profileMonitorSetEnabled,
            isEnabled: profileMonitorIsEnabled,
            addContextualInfoToEvent: profileMonitorAddContextualInfoToEvent,
            notifyPostSystemEnable: profileMonitorNotifyPostSystemEnable,
            writeInReportSection: profileMonitorWriteInReportSection
        )

        let p = UnsafeMutablePointer<KSCrashMonitorAPI>.allocate(capacity: 1)  // never deallocated
        p.initialize(to: api)
        kscm_addMonitor(p)
        return p
    }()
}

private func profileMonitorInit(
    _ callbacks: UnsafeMutablePointer<KSCrash_ExceptionHandlerCallbacks>?
) {
    ProfileMonitor.callbacks = callbacks?.pointee
}

private func profileMonitorGetId() -> UnsafePointer<CChar>? {
    ProfileMonitor.monitorId
}

private func profileMonitorGetFlags() -> KSCrashMonitorFlag {
    .init(0)
}

private func profileMonitorSetEnabled(_ enabled: Bool) {
    ProfileMonitor.enabled = enabled
}

private func profileMonitorIsEnabled() -> Bool {
    ProfileMonitor.enabled
}

private func profileMonitorAddContextualInfoToEvent(
    _ eventContext: UnsafeMutablePointer<KSCrash_MonitorContext>?
) {
}

private func profileMonitorNotifyPostSystemEnable() {
}

private func profileMonitorWriteInReportSection(
    _ context: UnsafePointer<KSCrash_MonitorContext>?,
    _ writerRef: UnsafePointer<ReportWriter>?
) {
    guard let writer = UnsafeReportWriter(writerRef) else {
        return
    }
    guard let callbackContext = context?.pointee.callbackContext else {
        return
    }

    let profileBox = Unmanaged<BoxedProfile>.fromOpaque(callbackContext).takeUnretainedValue()
    profileBox.write(with: writer)
}
