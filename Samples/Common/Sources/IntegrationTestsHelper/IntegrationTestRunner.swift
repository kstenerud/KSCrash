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

    private struct Script: Codable {
        var install: InstallConfig?
        var crashTrigger: CrashTriggerConfig?
        var report: ReportConfig?
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let crashTrigger = script.crashTrigger {
                crashTrigger.crash()
            }
            if let report = script.report {
                report.report()
            }
        }
    }

}

/// API for tests
public extension IntegrationTestRunner {
    static let envKey = "KSCrashIntegrationScript"

    static func script(crash: CrashTriggerConfig, install: InstallConfig? = nil) throws -> String {
        let data = try JSONEncoder().encode(Script(install: install, crashTrigger: crash))
        return data.base64EncodedString()
    }

    static func script(report: ReportConfig, install: InstallConfig? = nil) throws -> String {
        let data = try JSONEncoder().encode(Script(install: install, report: report))
        return data.base64EncodedString()
    }
}
