//
//  MetricKitMonitor+Helpers.swift
//
//  Created by Alexander Cohen on 2026-01-31.
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
import KSCrashRecording
import KSCrashReportModel
import os.log

let metricKitLog = OSLog(subsystem: "com.kscrash", category: "MetricKit")

// MARK: - Report Info

/// Builds the `ReportInfo` for a MetricKit-sourced report from the skeleton report's metadata,
/// shared by the crash, hang, and memory paths.
///
/// `finalized` controls whether the store stitches the report's run sidecars on read. Crash and
/// memory exceptions are the dead run's last moment, so its sidecars (memory state, breadcrumbs,
/// lifecycle) are aligned data — pass `false` to let them stitch in, keyed by `runId`. A hang is
/// a moment within a run that kept going, so its last-moment sidecar does not align — pass `true`.
func makeMetricKitReportInfo(
    skeleton: Report, timestamp: Date, runId: String?, finalized: Bool
) -> ReportInfo {
    ReportInfo(
        id: skeleton.report.id,
        processName: skeleton.report.processName,
        timestamp: timestamp,
        type: skeleton.report.type,
        version: skeleton.report.version,
        // A crumb that does not decode to a UUID names no run: the report
        // still delivers, without the run stitch.
        runId: runId.flatMap(RunSummary.ID.init),
        monitorId: skeleton.report.monitorId,
        finalized: finalized
    )
}

// MARK: - OS Version Parsing

struct OSVersionInfo {
    let name: String?
    let version: String?
    let build: String?
}

/// Parses a MetricKit OS version string into its components.
/// Format: "<Name> <Version> (<Build>)" e.g. "iPhone OS 26.2.1 (23C71)"
/// Falls back to using the raw string as systemVersion if parsing fails.
func parseOSVersion(_ raw: String) -> OSVersionInfo {
    let pattern = #"^(.+?)\s+([\d.]+)\s+\((.+)\)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
        match.numberOfRanges == 4,
        let nameRange = Range(match.range(at: 1), in: raw),
        let versionRange = Range(match.range(at: 2), in: raw),
        let buildRange = Range(match.range(at: 3), in: raw)
    else {
        return OSVersionInfo(name: nil, version: raw, build: nil)
    }
    return OSVersionInfo(
        name: String(raw[nameRange]),
        version: String(raw[versionRange]),
        build: String(raw[buildRange])
    )
}

// MARK: - VM Region Parsing

/// Parses the faulting address from a `virtualMemoryRegionInfo` string.
/// The string starts with the address (decimal or hex), e.g.
/// "0 is not in any region. ..." or "0x1234 is not in any region. ..."
func parseVMRegionAddress(from info: String) -> UInt64? {
    let token = String(info.prefix(while: { !$0.isWhitespace }))
    guard !token.isEmpty else { return nil }
    if token.hasPrefix("0x") || token.hasPrefix("0X") {
        return UInt64(token.dropFirst(2), radix: 16)
    }
    return UInt64(token)
}

// MARK: - Termination Reason Parsing

/// Parses a hex or decimal integer from the substring starting at `start`.
/// Reads until the next whitespace, common delimiter, or end of string.
private func parseCodeValue(from str: Substring) -> UInt64? {
    let terminators: Set<Character> = [" ", "\t", "\n", "\r", ">", ",", ";", "|"]
    let raw = String(str.prefix(while: { !terminators.contains($0) }))
    if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
        return UInt64(raw.dropFirst(2), radix: 16)
    }
    return UInt64(raw)
}

/// Parses the exit code from a termination reason string.
///
/// Supports three known formats:
/// 1. Old style: `Namespace SPRINGBOARD, Code 0x8badf00d`
/// 2. Newer with context: `FRONTBOARD 2343432205 <RBSTerminateContext| domain:10 code:0x8BADF00D ...>`
/// 3. Just context: `<RBSTerminateContext| domain:10 code:0x8BADF00D ...>`
///
/// Prefers the `code:` field inside RBSTerminateContext when present,
/// falling back to the old `Code ` prefix format.
func parseExitCode(from terminationReason: String) -> UInt64? {
    // Try RBSTerminateContext code: field first (formats 2 & 3)
    if let contextCodeRange = terminationReason.range(of: "code:", options: .caseInsensitive) {
        let after = terminationReason[contextCodeRange.upperBound...]
        if let result = parseCodeValue(from: after) {
            return result
        }
    }

    // Fall back to old format: "Code <value>" (format 1)
    if let codeRange = terminationReason.range(of: "Code ") {
        let after = terminationReason[codeRange.upperBound...]
        return parseCodeValue(from: after)
    }

    return nil
}

// MARK: - Time Range

/// The period MetricKit gives for a diagnostic: `timeRange` on 27+, the payload's
/// `timeStampBegin` and `timeStampEnd` before. Diagnostics delivered together share one range,
/// and the run the diagnostic describes need not contain either end of it, so a report with no run
/// ID carries both ends: a backend matches it to the run whose window the range overlaps.
///
/// Encoded as milliseconds since 1970, the unit of a run summary's `started_at_ms` and
/// `ended_at_ms`. An end that cannot be represented is left out.
struct MetricKitTimeRange: Codable, Equatable {
    let begin: Date
    let end: Date

    init(begin: Date, end: Date) {
        self.begin = begin
        self.end = end
    }

    enum CodingKeys: String, CodingKey {
        case begin = "begin_ms"
        case end = "end_ms"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        begin = Date(timeIntervalSince1970: Double(try c.decode(Int64.self, forKey: .begin)) / 1000)
        end = Date(timeIntervalSince1970: Double(try c.decode(Int64.self, forKey: .end)) / 1000)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(Self.epochMillis(begin), forKey: .begin)
        try c.encodeIfPresent(Self.epochMillis(end), forKey: .end)
    }

    private static func epochMillis(_ date: Date) -> Int64? {
        let ms = (date.timeIntervalSince1970 * 1000).rounded()
        guard ms.isFinite, ms >= Double(Int64.min), ms < Double(Int64.max) else { return nil }
        return Int64(ms)
    }
}

// MARK: - Profile Time

/// Converts a nanosecond count to `UInt64`, returning nil for non-finite, negative, or
/// out-of-range values rather than trapping on the cast.
func nanosToUInt64(_ ns: Double) -> UInt64? {
    guard ns.isFinite, ns >= 0, ns < Double(UInt64.max) else { return nil }
    return UInt64(ns.rounded())
}

/// Wall-clock start of a profile window: its end timestamp minus its duration. Returns nil if
/// the timestamp is out of range or the subtraction would underflow.
func epochNanos(for timestamp: Date, minus durationNs: UInt64) -> UInt64? {
    guard let end = nanosToUInt64(timestamp.timeIntervalSince1970 * 1_000_000_000) else { return nil }
    return end >= durationNs ? end - durationNs : nil
}

// MARK: - Bundle

/// The bundle ID in a legacy diagnostic's JSON (`diagnosticMetaData.bundleIdentifier`), or nil
/// when the JSON has none.
func diagnosticBundleIdentifier(fromJSON json: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
        let meta = object["diagnosticMetaData"] as? [String: Any],
        let bundleID = meta["bundleIdentifier"] as? String, !bundleID.isEmpty
    else { return nil }
    return bundleID
}

// MARK: - Device

/// The device hash for a report about a diagnostic MetricKit delivered to this app, or nil when
/// the diagnostic is another bundle's.
///
/// The hash identifies the app on this device and is the same in every run, so this run's value
/// is the one the diagnostic's own run recorded. MetricKit can deliver an app extension's
/// diagnostic to its app, and the hash covers the bundle ID, so a diagnostic from any other bundle
/// gets nil rather than the app's hash. A diagnostic that names no bundle is taken to be the app's
/// own.
///
/// - Parameters:
///   - diagnosticBundleID: The bundle ID the diagnostic names, when it names one.
///   - appBundleID: This app's bundle ID.
///   - hash: This app's device hash.
func deviceAppHash(
    forDiagnosticBundleID diagnosticBundleID: String?,
    appBundleID: String? = Bundle.main.bundleIdentifier,
    hash: String = String(cString: kscm_system_getDeviceAppHash())
) -> String? {
    if let diagnosticBundleID, !diagnosticBundleID.isEmpty, diagnosticBundleID != appBundleID {
        return nil
    }
    return hash
}
