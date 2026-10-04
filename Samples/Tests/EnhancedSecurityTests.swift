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
/// entitlements, or on a machine that does not enforce them.
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
        // The kernel kills a process that breaks a restriction with SIGKILL; it returns normally
        // where they are not enforced (macOS without System Integrity Protection, or a build
        // without the entitlements), and then the app is still running at the deadline.
        try launchAndCrash(.mach_forbiddenExceptionBehavior)
        XCTAssertEqual(app.terminatingSignal, SIGKILL)
    }
}
