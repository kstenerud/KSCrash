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
    /// has no equivalent for (memory_pressure, memory_level) stay as stitched.
    public func stitchedReport(_ report: [String: Any], sidecarURL: URL?, scope: SidecarScope) throws -> [String: Any] {
        guard scope == .final,
            let crash = report["crash"] as? [String: Any],
            var error = crash["error"] as? [String: Any],
            var monitorData = error["monitor_data"] as? [String: Any],
            let section = monitorData[Self.id] as? [String: Any]
        else { return report }
        guard let snapshot = section["snapshot"] as? [String: Any] else {
            // A snapshot-less capture: the writer's fence still emitted the (empty) section
            // object. Cleanup belongs at read time, so sweep it here rather than special-case
            // the crash-time writer.
            guard section.isEmpty else { return report }
            monitorData[Self.id] = nil
            error["monitor_data"] = monitorData.isEmpty ? nil : monitorData
            var result = report
            var mutableCrash = crash
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
        monitorData[Self.id] = nil
        error["monitor_data"] = monitorData.isEmpty ? nil : monitorData
        result[Self.rootKey] = snapshot

        var mutableCrash = crash
        mutableCrash["error"] = error
        result["crash"] = mutableCrash

        return result
    }
}
