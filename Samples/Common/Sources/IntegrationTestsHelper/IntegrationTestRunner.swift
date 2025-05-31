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

public final class IntegrationTestRunner {

    public struct RunConfig: Codable {
        var delay: TimeInterval?
        var stateSavePath: String?

        public init(delay: TimeInterval? = nil, stateSavePath: String? = nil) {
            self.delay = delay
            self.stateSavePath = stateSavePath
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

    public static func runIfNeeded() {
        guard let scriptString = ProcessInfo.processInfo.environment[Self.envKey],
            let data = Data(base64Encoded: scriptString),
            let script = try? JSONDecoder().decode(Script.self, from: data)
        else {
            return
        }

        if let installConfig = script.install {
            try! installConfig.install()
        }
        if let statePath = script.config?.stateSavePath {
            try! KSCrashState.collect().save(to: statePath)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (script.config?.delay ?? 0)) {
            if let crashTrigger = script.crashTrigger {
                crashTrigger.crash()
            }
            if let userReport = script.userReport {
                userReport.report()
            }
            if let report = script.report {
                report.report()
            }
        }
    }

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
