//
//  EnhancedSecurityTests.swift
//
//  Created by Alexander Cohen on 2026-10-03.
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
import IntegrationTestsHelper
import XCTest

/// Checks, in the lane that builds the Sample the way an app adopting Xcode's Enhanced Security
/// capability is built, that the app under test really is that app. Without these the rest of
/// that lane's suite would pass just the same against a build that lost its arm64e slice or its
/// entitlements. On a machine that does not enforce the entitlements, the enforcement check is
/// skipped with that reason rather than passed.
///
/// The lane sets KSCRASH_IT_ENHANCED_SECURITY (TEST_RUNNER_KSCRASH_IT_ENHANCED_SECURITY through
/// xcodebuild); everywhere else these are skipped.
final class EnhancedSecurityTests: IntegrationTestBase {
    override class var platforms: Set<TargetPlatform> { [.macOS] }

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KSCRASH_IT_ENHANCED_SECURITY"] != nil,
            "Only the Enhanced Security lane builds the Sample with that capability")
    }

    func testAppRunsAsArm64e() throws {
        try launchAndCrash(.mach_badAccess)
        let report = try launchAndReportCrash()
        XCTAssertEqual(report.system?.binaryArch, "arm64e")
    }

    func testRuntimePlatformRestrictionsAreEnforced() throws {
        // macOS enforces the restrictions only with System Integrity Protection on. Where it is off
        // the check cannot be made, which is not the same as a pass; any Mac with it on runs it.
        try XCTSkipUnless(
            Self.isSystemIntegrityProtectionEnabled,
            "System Integrity Protection is off here, so the restrictions are not enforced")

        // The kernel kills a process that breaks a restriction with SIGKILL; it returns normally
        // where they are not enforced (a build without the entitlements), and then the app is still
        // running at the deadline.
        try launchAndCrash(.mach_forbiddenExceptionBehavior)
        // The script writes the state file right after installing KSCrash and before the trigger, so
        // its presence ties the kill to the trigger rather than to the launch or the install.
        XCTAssertNoThrow(try readState(), "The app did not get as far as the trigger")
        XCTAssertEqual(app.terminatingSignal, SIGKILL)
    }

    private static var isSystemIntegrityProtectionEnabled: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        process.arguments = ["status"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        // When the status cannot be read, run the check rather than skip it.
        guard (try? process.run()) != nil else { return true }
        let status = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return !status.contains("disabled")
    }
}
