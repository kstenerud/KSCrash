//
//  LeaksTest.swift
//
//  Created by Alexander Cohen on 2025-12-26.
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
import KSCrashDemangleFilter
import KSCrashFilters
import KSCrashRecording
import KSCrashSinks

// MARK: - Sentinel leak to validate leak detection is working

private class LeakA {
    var b: LeakB?
    var padding = [UInt64](repeating: 0, count: 512)  // 4KB padding
}

private class LeakB {
    var a: LeakA?
    var padding = [UInt64](repeating: 0, count: 512)  // 4KB padding
}

/// Creates intentional leaks to ensure the leaks detection system is functioning.
/// If the CI reports 0 leaks, something is wrong with the detection.
private func createSentinelLeak() {
    // Create multiple Swift retain cycle leaks
    for i in 0..<10 {
        let a = LeakA()
        let b = LeakB()
        a.b = b
        b.a = a  // Retain cycle - will leak
        _ = i  // Suppress unused warning
    }

    // Raw malloc leak - cannot be optimized away
    let mallocLeak = malloc(4096)
    _ = mallocLeak  // Suppress unused warning, intentionally not freed

    print("[LeaksTest] Created sentinel leaks (expected: 21 leaks - 20 Swift objects + 1 malloc, ~84KB)")
}

// MARK: - KSCrash Setup

private func installKSCrash() -> Bool {
    let config = CrashInstallConfiguration()
    config.monitors = .all
    config.enableHangReporting = true
    do {
        try KSCrash.shared.install(with: config)
        print("[LeaksTest] KSCrash installed successfully")
        return true
    } catch {
        print("[LeaksTest] Failed to install KSCrash: \(error)")
        return false
    }
}

// MARK: - API Exercising

private func exerciseKSCrashAPIs() {
    // Set user info using per-key API with various types
    KSCrash.shared.setUserInfo(true, forKey: "leaks_test")
    KSCrash.shared.setUserInfo("Hello from leaks test", forKey: "test_string")
    KSCrash.shared.setUserInfo(42, forKey: "test_number")
    KSCrash.shared.setUserInfo(3.14159, forKey: "test_double")
    KSCrash.shared.setUserInfo(Date(), forKey: "test_date")
    print("[LeaksTest] Set userInfo")

    // Access various properties
    let systemInfo = KSCrash.shared.systemInfo
    print("[LeaksTest] System info keys: \(systemInfo.keys.joined(separator: ", "))")

    let crashedLastLaunch = KSCrash.shared.crashedLastLaunch
    print("[LeaksTest] Crashed last launch: \(crashedLastLaunch)")

    let activeDuration = KSCrash.shared.activeDurationSinceLastCrash
    print("[LeaksTest] Active duration since last crash: \(activeDuration)")

    let launchesSinceLastCrash = KSCrash.shared.launchesSinceLastCrash
    print("[LeaksTest] Launches since last crash: \(launchesSinceLastCrash)")

    // Update userInfo again
    KSCrash.shared.setUserInfo("exercised", forKey: "leaks_test_phase")
    KSCrash.shared.setUserInfo(Date().timeIntervalSince1970, forKey: "timestamp")
    print("[LeaksTest] Updated userInfo")
}

private func reportUserExceptions() {
    // Non-fatal user exception with stack trace
    KSCrash.shared.reportUserException(
        "LeaksTestException",
        reason: "Testing for memory leaks",
        language: "Swift",
        lineOfCode: "LeaksTest.swift:100",
        stackTrace: ["frame1", "frame2", "frame3"],
        logAllThreads: false,
        terminateProgram: false
    )
    print("[LeaksTest] Reported user exception (non-fatal, no threads)")

    // Non-fatal user exception with all threads logged
    KSCrash.shared.reportUserException(
        "LeaksTestAllThreads",
        reason: "Testing thread capture",
        language: "Swift",
        lineOfCode: "LeaksTest.swift:110",
        stackTrace: ["frame_a", "frame_b"],
        logAllThreads: true,
        terminateProgram: false
    )
    print("[LeaksTest] Reported user exception (non-fatal, all threads)")

    // Non-fatal with different language tag
    KSCrash.shared.reportUserException(
        "LeaksTestObjC",
        reason: "Testing ObjC path",
        language: "Objective-C",
        lineOfCode: "LeaksTest.m:50",
        stackTrace: ["-[MyClass myMethod]", "-[AppDelegate init]"],
        logAllThreads: false,
        terminateProgram: false
    )
    print("[LeaksTest] Reported user exception (ObjC language)")
}

// MARK: - Report Reading and Processing

private func readReports() -> [[String: Any]] {
    guard let reportStore = KSCrash.shared.reportStore else {
        print("[LeaksTest] No report store available")
        return []
    }

    let reportCount = reportStore.reportCount
    print("[LeaksTest] Report count: \(reportCount)")

    let reportIDs = reportStore.reportIDs
    print("[LeaksTest] Report IDs: \(reportIDs)")

    var reports: [[String: Any]] = []
    for reportID in reportIDs {
        if let report = reportStore.report(for: reportID.int64Value) {
            let value = report.value
            print("[LeaksTest] Read report \(reportID), \(value.keys.count) top-level keys")
            reports.append(value)
        }
    }
    return reports
}

private func exerciseFilterPipeline(reports: [[String: Any]]) {
    guard !reports.isEmpty else {
        print("[LeaksTest] No reports to filter")
        return
    }

    // Wrap raw dicts into CrashReportDictionary objects for the filter pipeline
    let crashReports: [CrashReportDictionary] = reports.map { CrashReportDictionary.report(withValue: $0) }

    // Doctor filter: generates automated diagnosis
    let doctorFilter = CrashReportFilterDoctor()
    doctorFilter.filterReports(crashReports) { filtered, error in
        print("[LeaksTest] Doctor filter: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")
    }

    // Demangle filter: demangles C++/Swift symbols
    let demangleFilter = CrashReportFilterDemangle()
    demangleFilter.filterReports(crashReports) { filtered, error in
        print("[LeaksTest] Demangle filter: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")
    }

    // JSON encode filter: dict -> Data
    let jsonEncodeFilter = CrashReportFilterJSONEncode()
    jsonEncodeFilter.filterReports(crashReports) { filtered, error in
        print("[LeaksTest] JSON encode: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")

        if let encoded = filtered {
            // JSON decode filter: Data -> dict (round-trip)
            let jsonDecodeFilter = CrashReportFilterJSONDecode()
            jsonDecodeFilter.filterReports(encoded) { decoded, decError in
                print("[LeaksTest] JSON decode: \(decoded?.count ?? 0) reports, error: \(String(describing: decError))")
            }
        }
    }

    // Apple format filter
    let appleFilter = CrashReportFilterAppleFmt(reportStyle: .symbolicated)
    appleFilter.filterReports(crashReports) { filtered, error in
        print("[LeaksTest] Apple format: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")
    }

    // Stringify filter
    let stringifyFilter = CrashReportFilterStringify()
    stringifyFilter.filterReports(crashReports) { filtered, error in
        print("[LeaksTest] Stringify: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")
    }

    // Exercise the transform filters individually (demangle, doctor, JSON encode).
    CrashReportFilterDemangle().filterReports(crashReports) { filtered, error in
        print("[LeaksTest] Demangle: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")
    }
    CrashReportFilterDoctor().filterReports(crashReports) { filtered, error in
        print("[LeaksTest] Doctor: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")
    }
    CrashReportFilterJSONEncode().filterReports(crashReports) { filtered, error in
        print("[LeaksTest] JSONEncode: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")
    }

    // Console sink: exercises the sink's type-guard and completion path.
    // The sink expects KSCrashReportString inputs (from the Apple formatter),
    // so passing dictionaries validates the reject-and-continue path, not
    // the formatting pipeline. Good enough for a leaks test.
    let consoleSink = CrashReportSinkConsole()
    consoleSink.filterReports(crashReports) { filtered, error in
        print("[LeaksTest] Console sink: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")
    }

    // Combine filter: runs multiple filters in parallel on same input
    let combine = CrashReportFilterCombine(filters: [
        "json": CrashReportFilterJSONEncode(),
        "apple": CrashReportFilterAppleFmt(reportStyle: .symbolicated),
    ])
    combine.filterReports(crashReports) { filtered, error in
        print("[LeaksTest] Combine: \(filtered?.count ?? 0) reports, error: \(String(describing: error))")
    }

    // Demangle individual symbols
    _ = CrashReportFilterDemangle.demangledCppSymbol("_ZN5MyApp6MyFunc7doStuffEv")
    _ = CrashReportFilterDemangle.demangledSwiftSymbol("$s5MyApp6MyFuncC7doStuffyyF")
    print("[LeaksTest] Exercised symbol demangling")
}

private func deleteAllReports() {
    guard let reportStore = KSCrash.shared.reportStore else { return }
    reportStore.deleteAllReports()
    print("[LeaksTest] Deleted all reports")
}

// MARK: - Hang Exercise

/// Blocks the main thread long enough for the watchdog to detect a hang,
/// then spins the run loop so the recovery observer fires and finalizes
/// the hang report in place.
private func exerciseHangDetectionAndRecovery() {
    print("[LeaksTest] Blocking main thread to trigger hang detection...")
    Thread.sleep(forTimeInterval: 1.0)
    print("[LeaksTest] Spinning run loop for hang recovery...")
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
    print("[LeaksTest] Hang recovery complete")
}

// MARK: - Entry Points

/// Phase 1: Install KSCrash, exercise APIs, report user exceptions, then crash
private func runLeaksTestCrash() {
    print("[LeaksTest] Starting crash phase...")

    guard installKSCrash() else { return }
    exerciseKSCrashAPIs()
    reportUserExceptions()

    print("[LeaksTest] About to crash via NSException...")
    NSException(name: .genericException, reason: "Leaks test crash", userInfo: nil).raise()
}

/// Phase 2: Install KSCrash (triggers stitching), exercise all code paths, then exit
private func runLeaksTest() {
    print("[LeaksTest] Starting leaks test phase...")

    // Install triggers stitching/finalization of Phase 1 reports
    guard installKSCrash() else { return }
    exerciseKSCrashAPIs()

    // Read reports from Phase 1 (crash + user exceptions),
    // triggering the finalization/stitching pipeline
    let reports = readReports()

    // Run all reports through the filter pipeline
    exerciseFilterPipeline(reports: reports)

    // Clean up Phase 1 reports
    deleteAllReports()

    // Generate fresh user exceptions and process them too
    reportUserExceptions()
    let freshReports = readReports()
    exerciseFilterPipeline(reports: freshReports)
    deleteAllReports()

    // Spin the run loop so the watchdog's run loop observer activates.
    // This runs inline rather than via asyncAfter so exit(0) is reached
    // even if SwiftUI's lifecycle never yields (e.g. headless CI runner).
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))

    exerciseHangDetectionAndRecovery()

    // Read and process the hang report
    let hangReports = readReports()
    exerciseFilterPipeline(reports: hangReports)
    deleteAllReports()

    createSentinelLeak()
    print("[LeaksTest] Leaks test completed")
    exit(0)
}

// MARK: - Public API

/// Checks environment variables and runs the appropriate leaks test phase if requested.
/// Call this from app initialization.
public func runLeaksTestIfRequired() {
    if ProcessInfo.processInfo.environment["KSCRASH_LEAKS_TEST_CRASH"] != nil {
        runLeaksTestCrash()
    } else if ProcessInfo.processInfo.environment["KSCRASH_LEAKS_TEST"] != nil {
        runLeaksTest()
    }
}
