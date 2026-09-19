//
//  CorpseHostApp.swift
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

import CrashTriggers
import KSCrash
import KSCrashCrashReportExtension
import SwiftUI

/// The app half of the corpse integration, and the example a developer reads to
/// see how the two sides fit together.
///
/// The install here is an ordinary one that registers the extension monitor as a
/// plugin. Only the send configuration names the shared area. That is exactly
/// the documented integration, and building the test around anything else would
/// be testing a shape no user would write.
@main
struct CorpseHostApp: App {

    @State private var verdict: CorpseVerdict?

    /// Why the install failed, if it did. Surfaced through the UI because it is
    /// otherwise invisible: a failed install shows up only as a missing run id,
    /// which reads like a capture problem rather than a setup one.
    static var installError: String?

    init() {
        var config = InstallConfiguration(namespace: CorpseArea.namespace)
        config.container = .appGroup(CorpseArea.appGroup)
        config.plugins = [CrashReportExtensionMonitor.plugin()]
        // No in-process detectors at all, written explicitly because the default
        // set is not empty. This is what makes the test mean something: with the
        // signal and Mach handlers installed, they would catch these crashes
        // too and write their own reports, and a verdict built from one of those
        // would pass without the extension ever having run. With them off, any
        // report that arrives can only have come from the corpse.
        config.monitors = []
        do {
            try KSCrash.shared.install(config)
        } catch {
            // Deliberately not fatal: the verifier reports the absence of a
            // report, which is a more useful failure than a dead host.
            Self.installError = "\(error)"
        }

        // Written for every run, because the launch-hang case has no chance to
        // show it on screen before the watchdog kills the process.
        if let runID = KSCrash.shared.runID?.description {
            CorpseArea.recordRunID(runID)
        }

        // Before any scene exists, which is the point: the watchdog polices
        // launch, so the hang has to happen inside it.
        if case .crash(LaunchHang.triggerID) = LaunchPlan.fromLaunchArguments() {
            LaunchHang.hangUntilKilled()
        }
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                // Published before the crash so the test can pin which run it is
                // about to kill, and after the send so a mismatch is legible.
                Text(KSCrash.shared.runID?.description ?? "no-run-id")
                    .accessibilityIdentifier("corpse.runid")
                Text(verdict?.summary ?? "ready")
                    .accessibilityIdentifier("corpse.status")
                Text(verdict?.detail ?? Self.installError.map { "install failed: \($0)" } ?? "")
                    .accessibilityIdentifier("corpse.detail")
                    .font(.footnote)
                    .multilineTextAlignment(.center)

                if case .crash(let trigger) = LaunchPlan.fromLaunchArguments() {
                    // The test taps this rather than the app crashing on launch,
                    // so the run id above is definitely on screen and read before
                    // the process dies. Crashing from `.task` raced the read.
                    Button("crash") {
                        CrashTriggersHelper.runTrigger(CrashTriggerId(rawValue: trigger))
                    }
                    .accessibilityIdentifier("corpse.trigger")
                }
            }
            .padding()
            .task { await act() }
        }
    }

    private func act() async {
        guard case .verify = LaunchPlan.fromLaunchArguments() else { return }
        let arguments = ProcessInfo.processInfo.arguments
        let expectation =
            CorpseExpectation.reusingExistingTriggers.first { arguments.contains($0.triggerID) }
            ?? CorpseExpectation.reusingExistingTriggers[0]
        // The run the test watched die. Without pinning it, a leftover report
        // from an earlier case would satisfy every other assertion here.
        let expectedRun =
            arguments.firstIndex(of: "--corpse-expect-run").map { arguments[$0 + 1] }
            ?? CorpseArea.recordedRunID()
        verdict = await CorpseVerifier.run(expecting: expectation, fromRun: expectedRun)
    }
}
