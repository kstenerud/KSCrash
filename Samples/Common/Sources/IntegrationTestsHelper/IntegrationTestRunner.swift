//
//  IntegrationTestRunner.swift
//
//  Created by Nikolay Volosatov on 2024-08-11.
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

#if canImport(UIKit) && !os(watchOS)
    import UIKit
#endif

public final class IntegrationTestRunner {

    public struct RunConfig: Codable, Sendable {
        var delay: TimeInterval?
        var stateSavePath: String?
        var runEarly: Bool?
        var completionMarkerPath: String?

        public init(
            delay: TimeInterval? = nil,
            stateSavePath: String? = nil,
            runEarly: Bool? = nil,
            completionMarkerPath: String? = nil
        ) {
            self.delay = delay
            self.stateSavePath = stateSavePath
            self.runEarly = runEarly
            self.completionMarkerPath = completionMarkerPath
        }
    }

    private struct Script: Codable {
        var install: InstallConfig?
        var userReport: UserReportConfig?
        var crashTrigger: CrashTriggerConfig?
        var report: ReportConfig?

        var config: RunConfig?
    }

    public static let runScriptAccessabilityId = "run-integration-test"

    public static var isTestRun: Bool {
        ProcessInfo.processInfo.environment[Self.envKey] != nil
    }

    /// Call first thing at app launch. In a test run, sets up what the harness relies on.
    public static func prepareIfNeeded() {
        guard isTestRun else { return }
        #if os(watchOS)
            exitOnTermination()
        #endif
    }

    #if os(watchOS)
        /// Set once at launch, on the main thread, and kept for the life of the process.
        nonisolated(unsafe) private static var terminationSource: DispatchSourceSignal?

        /// The harness ends a running app with SIGTERM, which KSCrash records as a clean exit
        /// through its signal monitor. watchOS has no signal monitor, so there the process just
        /// dies and the next launch reports an unexplained termination. Exiting on SIGTERM
        /// instead goes through KSCrash's exit hook, which records it as clean.
        private static func exitOnTermination() {
            signal(SIGTERM, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            source.setEventHandler { exit(0) }
            source.resume()
            terminationSource = source
        }
    #endif

    /// Runs the script during app init, before the app becomes active.
    /// Only executes if `config.runEarly` is true.
    public static func runEarlyIfNeeded() {
        guard let script = decodeScript(), script.config?.runEarly == true else {
            return
        }
        executeScript(script)
    }

    /// Runs the script from onAppear, after the app is active.
    /// Skips if `config.runEarly` is true (already handled).
    public static func runIfNeeded() {
        guard let script = decodeScript(), script.config?.runEarly != true else {
            return
        }
        executeScript(script)
    }

    private static func decodeScript() -> Script? {
        guard let scriptString = ProcessInfo.processInfo.environment[envKey],
            let data = Data(base64Encoded: scriptString),
            let script = try? JSONDecoder().decode(Script.self, from: data)
        else {
            return nil
        }
        return script
    }

    private static func executeScript(_ script: Script) {
        if let installConfig = script.install {
            try! installConfig.install()
        }
        if let statePath = script.config?.stateSavePath {
            try! KSCrashState.collect().save(to: statePath)
        }

        let act: @Sendable () -> Void = {
            if let crashTrigger = script.crashTrigger {
                crashTrigger.crash()
            }
            if let userReport = script.userReport {
                userReport.report()
            }
            // The report send is awaited, so the marker below is written only
            // once the delivered reports are on disk.
            Task { @MainActor in
                if let report = script.report {
                    await report.report()
                }
                if let completionMarkerPath = script.config?.completionMarkerPath {
                    try! Data().write(to: URL(fileURLWithPath: completionMarkerPath))
                }
            }
        }

        #if canImport(UIKit) && !os(watchOS)
            if script.config?.runEarly == true {
                // Act inside the launch pass itself, while the app is still Launching. An
                // asyncAfter from app init can run after the app has begun foregrounding,
                // which is a different case for anything that depends on launch state.
                launchObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didFinishLaunchingNotification, object: nil, queue: nil
                ) { _ in
                    act()
                }
                return
            }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + (script.config?.delay ?? 0), execute: act)
    }

    #if canImport(UIKit) && !os(watchOS)
        /// Kept so the observer outlives the call that registers it; set once at launch.
        nonisolated(unsafe) private static var launchObserver: NSObjectProtocol?
    #endif

}

/// API for tests
extension IntegrationTestRunner {
    public static let envKey = "KSCrashIntegrationScript"

    public static func script(crash: CrashTriggerConfig, install: InstallConfig? = nil, config: RunConfig? = nil) throws
        -> String
    {
        let data = try JSONEncoder().encode(Script(install: install, crashTrigger: crash, config: config))
        return data.base64EncodedString()
    }

    public static func script(userReport: UserReportConfig, install: InstallConfig? = nil, config: RunConfig? = nil)
        throws -> String
    {
        let data = try JSONEncoder().encode(Script(install: install, userReport: userReport, config: config))
        return data.base64EncodedString()
    }

    public static func script(report: ReportConfig, install: InstallConfig? = nil, config: RunConfig? = nil) throws
        -> String
    {
        let data = try JSONEncoder().encode(Script(install: install, report: report, config: config))
        return data.base64EncodedString()
    }

    public static func script(install: InstallConfig? = nil, config: RunConfig? = nil) throws -> String {
        let data = try JSONEncoder().encode(Script(install: install, config: config))
        return data.base64EncodedString()
    }
}
