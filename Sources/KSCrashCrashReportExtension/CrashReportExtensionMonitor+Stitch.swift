//
//  CrashReportExtensionMonitor+Stitch.swift
//
//  Created by Alexander Cohen on 2026-07-18.
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
import KSCrashReportModel

extension CrashReportExtensionMonitor {

    /// The app-side half of corpse reporting: in the final stitch pass (no sidecar), replace
    /// the run-cached values the sidecar stitches wrote with the corpse's at-death data, read
    /// from the report's own embedded snapshot. Key by key, never wholesale; keys the corpse
    /// has no equivalent for (memory_pressure, memory_level) stay as stitched. A corpse that died
    /// of an uncaught Objective-C or C++ exception is typed the way an in-process report of the
    /// same crash is.
    public func stitchedReport(_ report: [String: Any], sidecarURL: URL?, scope: SidecarScope) throws -> [String: Any] {
        guard scope == .final,
            let crash = report["crash"] as? [String: Any],
            var error = crash["error"] as? [String: Any],
            let section = error[Self.id] as? [String: Any]
        else { return report }
        guard let snapshot = section["snapshot"] as? [String: Any] else {
            // A snapshot-less capture: the writer still emitted the (empty) scratch section.
            // Cleanup belongs at read time, so sweep it here rather than special-case the
            // crash-time writer.
            guard section.isEmpty else { return report }
            error[Self.id] = nil
            var result = report
            var mutableCrash = crash
            Self.classifyLanguageException(in: report, error: &error, crash: &mutableCrash)
            mutableCrash["error"] = error
            result["crash"] = mutableCrash
            return result
        }

        var result = report

        var system = (report["system"] as? [String: Any]) ?? [:]
        var appMemory = (system["app_memory"] as? [String: Any]) ?? [:]
        // The Resource sidecar's footprint is its last periodic sample; kcdata's rusage carries
        // the value at death.
        if let footprint = (snapshot["rusage"] as? [String: Any])?["physFootprint"] {
            appMemory["memory_footprint"] = footprint
        }
        // -1 means the kernel did not report a limit.
        if let remaining = (snapshot["vmInfo"] as? [String: Any])?["limitBytesRemaining"] as? Int64, remaining >= 0 {
            appMemory["memory_remaining"] = remaining
        }
        if !appMemory.isEmpty {
            system["app_memory"] = appMemory
        }
        var appStats = (system["application_stats"] as? [String: Any]) ?? [:]
        if let taskRole = snapshot["taskRole"] as? String {
            appStats["task_role"] = taskRole
        }
        if !appStats.isEmpty {
            system["application_stats"] = appStats
        }
        if !system.isEmpty {
            result["system"] = system
        }

        // kcdata's exit reason knows the namespace and flags; the writer's version carries only
        // a code.
        if let exitReason = (snapshot["crashInfo"] as? [String: Any])?["exitReason"] as? [String: Any] {
            var reason: [String: Any] = [:]
            reason["namespace"] = exitReason["namespace"]
            reason["code"] = exitReason["code"]
            if let flags = exitReason["flags"] {
                reason["flags"] = flags
            }
            error["exit_reason"] = reason

            // The same wire values the synthetic reports carry (Termination's strings,
            // MetricKit's enums), so one death reads the same across every narrative.
            // Only namespaces with a certain mapping; anything else stays untagged.
            if let namespace = exitReason["namespace"] as? UInt32 {
                switch ExitReasonNamespace(rawValue: namespace) {
                case .OS_REASON_JETSAM:
                    error["termination_reason"] = TerminationReason.memoryLimit.rawValue
                    error["subtype"] = CrashErrorSubtype.memoryException.rawValue
                case .OS_REASON_WATCHDOG:
                    error["termination_reason"] = TerminationReason.hang.rawValue
                default:
                    break
                }
            }
        }

        // The snapshot describes the crashed process, not the error: the stitches above read it
        // to fill in system, process and termination facts, so it belongs at the report's root
        // rather than nested in the error the way a monitor's own section is written.
        error[Self.id] = nil
        result[Self.rootKey] = snapshot

        var mutableCrash = crash
        Self.classifyLanguageException(in: report, error: &error, crash: &mutableCrash)
        mutableCrash["error"] = error
        result["crash"] = mutableCrash

        return result
    }

    /// Gives a corpse that died of an uncaught language exception the type an in-process report of
    /// the same crash carries, with the fields the runtime's messages carry for it, so one crash
    /// reads the same whichever path captured it. The Mach and signal sections stay: in-process
    /// writes them for every type. Frames carry only their address, like the corpse's own thread
    /// frames, since nothing here can symbolicate another process's addresses.
    ///
    /// Only a corpse that died of SIGABRT is read. An uncaught exception ends the process through
    /// abort(), but CoreFoundation writes its message before calling the app's own handler, so a
    /// handler that keeps the process alive leaves the message behind for whatever kills it later.
    static func classifyLanguageException(
        in report: [String: Any], error: inout [String: Any], crash: inout [String: Any]
    ) {
        guard ((error["signal"] as? [String: Any])?["signal"] as? Int) == Int(SIGABRT),
            let images = report["binary_images"] as? [[String: Any]],
            let exception = CorpseLanguageException.read(fromBinaryImages: images)
        else { return }
        switch exception {
        case .objC(let name, let reason, let throwAddresses):
            error["type"] = "nsexception"
            error["nsexception"] = ["name": name]
            error["reason"] = reason
            if !throwAddresses.isEmpty {
                crash["last_exception_backtrace"] = [
                    "contents": throwAddresses.map { ["instruction_addr": $0] },
                    "skipped": 0,
                ]
            }
        case .cpp(let name, let reason):
            error["type"] = "cpp_exception"
            // An empty object for a bare std::terminate(), as in-process writes it.
            error["cpp_exception"] = name.map { ["name": $0] } ?? [String: Any]()
            error["reason"] = reason
        }
    }
}
