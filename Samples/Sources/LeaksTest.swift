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
import KSCrashRecording

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
    let config = KSCrashConfiguration()
    config.monitors = .all
    do {
        try KSCrash.shared.install(with: config)
        print("[LeaksTest] KSCrash installed successfully")
        return true
    } catch {
        print("[LeaksTest] Failed to install KSCrash: \(error)")
        return false
    }
}

private func exerciseKSCrashAPIs() {
    // Set user info
    KSCrash.shared.userInfo = [
        "leaks_test": true,
        "test_string": "Hello from leaks test",
        "test_number": 42,
        "test_array": [1, 2, 3],
        "test_dict": ["nested": "value"],
    ]
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

    // Report a non-fatal user exception
    KSCrash.shared.reportUserException(
        "LeaksTestException",
        reason: "Testing for memory leaks",
        language: "Swift",
        lineOfCode: "LeaksTest.swift:50",
        stackTrace: ["frame1", "frame2", "frame3"],
        logAllThreads: false,
        terminateProgram: false
    )
    print("[LeaksTest] Reported user exception")

    // Update userInfo again
    KSCrash.shared.userInfo = [
        "leaks_test_phase": "exercised",
        "timestamp": Date().timeIntervalSince1970,
    ]
    print("[LeaksTest] Updated userInfo")
}

private func readAndDeleteReports() {
    guard let reportStore = KSCrash.shared.reportStore else {
        print("[LeaksTest] No report store available")
        return
    }

    let reportCount = reportStore.reportCount
    print("[LeaksTest] Report count: \(reportCount)")

    let reportIDs = reportStore.reportIDs
    print("[LeaksTest] Report IDs: \(reportIDs)")

    // Read all reports
    for reportID in reportIDs {
        if let report = reportStore.report(for: reportID.int64Value) {
            print("[LeaksTest] Read report \(reportID)")
            // Access the report data to exercise parsing
            if let value = report.value as? [String: Any] {
                print("[LeaksTest] Report has \(value.keys.count) top-level keys")
            }
        }
    }

    // Delete all reports to exercise deletion code path
    reportStore.deleteAllReports()
    print("[LeaksTest] Deleted all reports")
}

// MARK: - Entry Points

/// First run: Install KSCrash, exercise APIs, then crash to generate a crash report
private func runLeaksTestCrash() {
    print("[LeaksTest] Starting crash phase...")

    guard installKSCrash() else { return }
    exerciseKSCrashAPIs()

    print("[LeaksTest] About to crash via NSException...")
    NSException(name: .genericException, reason: "Leaks test crash", userInfo: nil).raise()
}

/// Second run: Install KSCrash, read crash reports from previous run, then exit
private func runLeaksTest() {
    print("[LeaksTest] Starting leaks test phase...")

    guard installKSCrash() else { return }
    exerciseKSCrashAPIs()
    readAndDeleteReports()
    createSentinelLeak()

    print("[LeaksTest] Leaks test completed")

    // Exit so leaks --atExit can report
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        exit(0)
    }
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
