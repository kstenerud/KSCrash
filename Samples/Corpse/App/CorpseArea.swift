//
//  CorpseArea.swift
//
//  Created by Alexander Cohen on 2026-09-19.
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

/// The app's half of the two-target integration.
///
/// This is deliberately a separate declaration from the extension's, built from
/// the same app group rather than from a shared constant. The two processes are
/// built and signed independently in a real integration, and the only thing that
/// makes them agree is that both derive the same area from the same group. A
/// shared constant would paper over a mismatch that a real app would hit.
enum CorpseArea {
    static let appGroup = "group.com.github.kstenerud.KSCrash.Corpse"
    static let namespace = "KSCrashCorpseTests"

    static var configuration: CorpseReportingConfiguration {
        CorpseReportingConfiguration(namespace: namespace, container: .appGroup(appGroup))
    }

    /// Where a run about to die records its own id.
    ///
    /// Most cases let the test read the id off the screen before killing the
    /// app, which keeps the pin independent of the code under test. A launch
    /// hang cannot: the watchdog kills the process before any UI exists, so the
    /// dying run writes the id itself and the next launch reads it back.
    static var runIDReceipt: URL? {
        // The app's own container. Only this app writes it and only this app
        // reads it back; the extension has no interest in it, so it has no
        // business in the shared group.
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("last-run-id.txt")
    }

    static func recordRunID(_ id: String) {
        guard let url = runIDReceipt else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(id.utf8).write(to: url)
    }

    static func recordedRunID() -> String? {
        guard let url = runIDReceipt, let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// A hang the OS actually punishes.
///
/// iOS only watchdogs transitions it polices, launch above all: an app that has
/// not finished launching within roughly twenty seconds is killed with
/// 0x8badf00d. A main thread blocked *after* launch is merely unresponsive, and
/// the system leaves it alone, which is why the sample's existing watchdog
/// trigger has to SIGKILL itself and therefore produces no corpse.
///
/// So this burns the main thread with real work during launch, before any scene
/// exists, and waits to be killed.
enum LaunchHang {
    static let triggerID = "corpse-launch-hang"

    static func hangUntilKilled() {
        let deadline = Date().addingTimeInterval(120)
        var sink = 0.0
        // Real work rather than sleep: a sleeping main thread and a busy one are
        // not the same to the watchdog, and busy is what a real launch hang is.
        while Date() < deadline {
            for i in 1...200_000 {
                sink += (Double(i) * 1.000_001).squareRoot()
            }
        }
        // Never reached; keeps the compiler from discarding the work above.
        if sink == .infinity { abort() }
    }
}

/// How the UI test drives the app. Everything the app does is decided by launch
/// arguments, because the test has to control a process that is about to die and
/// then inspect what a *later* launch makes of it.
enum LaunchPlan {
    /// Install, then die in the requested way.
    case crash(trigger: String)
    /// Install, drain the extension's area, send, and publish a verdict.
    case verify
    /// Neither: the app just sits there.
    case idle

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchPlan {
        if let index = arguments.firstIndex(of: "--corpse-crash"), index + 1 < arguments.count {
            return .crash(trigger: arguments[index + 1])
        }
        if arguments.contains("--corpse-verify") {
            return .verify
        }
        return .idle
    }
}
