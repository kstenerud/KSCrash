//
//  TimeProfile.Report.swift
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
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashRecordingCore

// MARK: - Time Profile Report Writing

/// Extension that provides crash report writing functionality for time-sampled profiles.
///
/// This extension routes profiles through `ProfileMonitor`, the profiler's monitor on the
/// Swift monitor layer, which allows profiles to be written as crash reports. The report
/// format uses frame deduplication to minimize file size:
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
/// - `threads`: One entry per thread (a time profile has exactly one, flagged primary),
///   each with a `samples` array referencing frames by index
extension TimeProfile {

    /// Writes this profile to a crash report file.
    ///
    /// This method drives the profile through the exception-handling pipeline via
    /// `ProfileMonitor.shared`, which produces a JSON report containing the profile data.
    /// The report is written synchronously to the KSCrash reports directory.
    ///
    /// - Returns: The URL of the written report file, or `nil` if the report could not be written.
    internal func _writeReport() -> URL? {
        let bridge = ProfileMonitor.shared
        guard bridge.isInstalled else { return nil }
        let written = try? bridge.monitor.host.handle(
            payload: self, requirements: .nonFatal, subjectThread: thread, finalize: true
        ) { context in
            // Profile frames already include object_uuid, so binary_images is redundant.
            context.pointee.omitBinaryImages = true
        }
        return written?.url
    }

    /// Writes this profile's data to the report using the given writer.
    ///
    /// Single-pass frame deduplication:
    /// 1. Walk samples once, assigning each new address an index in `addrToIdx`
    ///    and appending it to `uniqueAddrs`. Per-sample index sequences are
    ///    captured into `sampleIndexes` to avoid a second hash lookup per frame
    ///    at write time.
    /// 2. Write metadata + the frames array, symbolicating each unique address
    ///    on the fly (no intermediate `[SymbolInformation]`).
    /// 3. Write the samples array, emitting the pre-computed indexes.
    ///
    /// Frames are written in insertion order rather than sorted, since the
    /// consumer doesn't depend on sort order and skipping the sort avoids an
    /// extra pass and allocation.
    ///
    /// - Parameter writer: The report writer to use for JSON output.
    func write(with writer: ReportSectionWriter) {
        var addrToIdx: [UInt: Int32] = [:]
        // One unique address per sample is a reasonable starting estimate;
        // the dictionary will grow on its own if the profile has more variety.
        addrToIdx.reserveCapacity(samples.count)
        var uniqueAddrs: [UInt] = []
        uniqueAddrs.reserveCapacity(samples.count)
        var sampleIndexes: [[Int32]] = []
        sampleIndexes.reserveCapacity(samples.count)

        for sample in samples {
            var idxs: [Int32] = []
            idxs.reserveCapacity(sample.addresses.count)
            for addr in sample.addresses {
                if let i = addrToIdx[addr] {
                    idxs.append(i)
                } else {
                    let i = Int32(uniqueAddrs.count)
                    addrToIdx[addr] = i
                    uniqueAddrs.append(addr)
                    idxs.append(i)
                }
            }
            sampleIndexes.append(idxs)
        }

        writer.add("name", name)
        writer.add("id", id.uuidString)
        writer.add("time_start_epoch", UInt64(startTime.timeIntervalSince1970 * 1_000_000_000.0))
        writer.add("time_start_uptime", startTimestampNs)
        writer.add("time_end_uptime", endTimestampNs)
        writer.add("expected_sample_interval", expectedSampleIntervalNs)
        writer.add("duration", durationNs)
        writer.add("time_units", "nanoseconds")
        writer.add("truncated_count", UInt64(truncatedSampleCount))

        writer.beginArray("frames")
        for addr in uniqueAddrs {
            // Re-init per address: ksbt_symbolicateAddress only writes the fields it
            // can resolve, so a fresh struct is needed per call to keep stale fields
            // (symbolName, imageName, imageUUID, etc.) from a previous frame from
            // leaking into a frame whose address fails to resolve.
            var info = SymbolInformation()
            _ = symbolicate(address: addr, result: &info)

            writer.beginObject(nil)
            if let symbolName = info.symbolName {
                writer.add("symbol_name", String(cString: symbolName))
            }
            writer.add("symbol_addr", UInt64(info.symbolAddress))
            writer.add("instruction_addr", UInt64(info.callInstruction))
            if let imageName = info.imageName {
                let name = URL(fileURLWithPath: String(cString: imageName)).lastPathComponent
                writer.add("object_name", name)
            }
            writer.add("object_addr", UInt64(info.imageAddress))
            if let uuid = info.imageUUID {
                writer.addUUID("object_uuid", uuid)
            }
            writer.endContainer()
        }
        writer.endContainer()

        // A time profile observes a single thread, emitted as a one-element `threads` array
        // so the report shape matches multi-thread profiles (e.g. hangs). count is always 1:
        // each captured backtrace is its own sample.
        writer.beginArray("threads")
        writer.beginObject(nil)
        writer.add("index", Int64(0))
        writer.add("primary", true)

        writer.beginArray("samples")
        for (i, sample) in samples.enumerated() {
            writer.beginObject(nil)
            writer.add("count", Int64(1))
            writer.add("time_start_uptime", sample.metadata.timestampBeginNs)
            writer.add("time_end_uptime", sample.metadata.timestampEndNs)
            writer.add("duration", sample.metadata.durationNs)

            writer.beginArray("frames")
            for index in sampleIndexes[i] {
                writer.add(nil, UInt64(index))
            }
            writer.endContainer()

            writer.endContainer()
        }
        writer.endContainer()  // samples

        writer.endContainer()  // thread object
        writer.endContainer()  // threads
    }
}

// MARK: - Profile Monitor

/// The profiler's monitor on the Swift monitor layer (`.claude/rules/swift-monitors.md`).
/// Writes a profile's frames and samples into its report section.
final class ProfileMonitor: CrashMonitor {
    typealias EventPayload = TimeProfile
    /// Doubles as the report wire format: the writer emits this as crash.error.type and
    /// its fence matches it to route the payload to its schema home, `crash.error.profile`.
    static let id = ExceptionType.profile.rawValue

    let host: MonitorHost<TimeProfile>

    init(host: MonitorHost<TimeProfile>, configuration: Void) {
        self.host = host
    }

    func writeReportSection(payload: TimeProfile, writer: ReportSectionWriter) {
        payload.write(with: writer)
    }
}

extension ProfileMonitor {
    /// The profiler's bridge, registered by the profiler's install hook exactly where the old
    /// api table was: unlike the developer-facing monitors (MetricKit, Corpse), the profiler
    /// has always self-registered on first use rather than requiring `config.plugins` wiring,
    /// so this lazy static keeps that contract by calling `kscm_addMonitor` itself.
    static let shared: Monitor<ProfileMonitor> = {
        let bridge = ProfileMonitor.plugin()
        kscm_addMonitor(bridge.api)
        // kscm_addMonitor registers but does not enable, and the bulk enable pass ran during
        // install, long before this lazy static is first touched. Without this the monitor
        // would stay disabled for the process lifetime, where the pre-bridge implementation
        // defaulted to enabled.
        kscm_setMonitorEnabled(bridge.api, true)
        return bridge
    }()
}
