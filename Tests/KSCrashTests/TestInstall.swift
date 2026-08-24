//
//  TestInstall.swift
//
//  Created by Alexander Cohen on 2026-08-22.
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
import KSCrashMonitorPlugins
import KSCrashRecording
import KSCrashRecordingCore
import XCTest

@testable import KSCrash

/// The one install the test process makes: the C core installs once, so every
/// test that needs an installed reporter shares this one.
/// The last report id the did-write crash-time callback delivered; the
/// callback must stay non-capturing, so this is file scope.
nonisolated(unsafe) var didWriteWitness: String?

enum TestInstall {
    /// A plugin over a minimal C monitor table, to prove registration round-trips.
    final class Plugin: MonitorPlugin, @unchecked Sendable {
        private static let monitorID: UnsafePointer<CChar> = UnsafePointer(strdup("KSCrashTestsPlugin")!)
        let api: UnsafeMutablePointer<KSCrashMonitorAPI>

        init() {
            api = .allocate(capacity: 1)
            api.initialize(to: KSCrashMonitorAPI())
            // The core calls these without a NULL check; the rest may stay NULL.
            api.pointee.`init` = { _, _ in }
            api.pointee.monitorId = { _ in Plugin.monitorID }
            api.pointee.monitorFlags = { _ in KSCrashMonitorFlagPlugin }
            api.pointee.setEnabled = { _, _ in }
            api.pointee.isEnabled = { _ in true }
            api.pointee.addContextualInfoToEvent = { _, _ in }
            api.pointee.notifyPostSystemEnable = { _ in }
        }
    }

    static let plugin = Plugin()
    static let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("KSCrashTests-\(UUID().uuidString)", isDirectory: true)
    static let configuration: InstallConfiguration = {
        var config = InstallConfiguration(namespace: "Tests")
        config.container = .url(base)
        config.monitors = [.hangs]
        config.plugins = [plugin]
        var callbacks = UnsafeCrashTimeCallbacks()
        callbacks.didWriteReport = { _, reportID in
            didWriteWitness = String(cString: reportID)
        }
        config.unsafeCrashTimeCallbacks = callbacks
        return config
    }()

    private static let result: Result<Void, Error> = Result { try KSCrash.shared.install(configuration) }

    /// Installs on first use; rethrows the install's error on every use after a failure.
    static func ensure() throws {
        try result.get()
    }
}
