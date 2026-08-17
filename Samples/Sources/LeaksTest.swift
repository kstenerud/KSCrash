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
import KSCrash

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

private func exerciseSendPipeline() {
    // A logging pass-through stage, so every delivered report walks the whole
    // Swift pipeline machinery (snapshot, claim, decode, stage, delete).
    struct LogStage: PipelineStage {
        func process(_ payload: Report) async throws -> Report? {
            print(
                "[LeaksTest] Send stage: report \(payload.report.id), \(String(describing: payload.crash.error.type))")
            return payload
        }
    }

    // The send is async; the leaks test is a synchronous script, so block on a
    // semaphore. The send runs off the caller's actor, so this cannot deadlock.
    let done = DispatchSemaphore(value: 0)
    Task {
        let configuration = SendConfiguration(
            reportPipeline: [AnyPipelineStage(LogStage())],
            includesDeliveredPayloads: true
        )
        do {
            let bulk = try await KSCrash.shared.sendReports(with: configuration)
            print(
                "[LeaksTest] Swift bulk send: delivered \(bulk.delivered.count), "
                    + "discarded \(bulk.discarded.count), kept \(bulk.kept.count)")

            // The bulk send skips current-run reports (the fresh user
            // exceptions, the hang report). Naming ids is how those are sent
            // deliberately, and it exercises the selection path too.
            let remaining = (KSCrash.shared.reportStore?.reportIDs ?? []).map(\.stringValue)
            let named = try await KSCrash.shared.sendReports(with: configuration, only: remaining)
            print(
                "[LeaksTest] Swift named send: delivered \(named.delivered.count), "
                    + "discarded \(named.discarded.count), kept \(named.kept.count)")
        } catch {
            print("[LeaksTest] Swift send failed: \(error)")
        }
        done.signal()
    }
    if done.wait(timeout: .now() + 10) == .timedOut {
        print("[LeaksTest] Swift send timed out")
    }
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
    _ = readReports()

    // Run the pending reports through the Swift send pipeline
    exerciseSendPipeline()

    // Clean up Phase 1 reports
    deleteAllReports()

    // Generate fresh user exceptions and process them too
    reportUserExceptions()
    _ = readReports()
    exerciseSendPipeline()
    deleteAllReports()

    // Spin the run loop so the watchdog's run loop observer activates.
    // This runs inline rather than via asyncAfter so exit(0) is reached
    // even if SwiftUI's lifecycle never yields (e.g. headless CI runner).
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))

    exerciseHangDetectionAndRecovery()

    // Read and process the hang report
    _ = readReports()
    exerciseSendPipeline()
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
