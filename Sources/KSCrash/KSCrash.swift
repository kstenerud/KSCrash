//
//  KSCrash.swift
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
import KSCrashSwiftCore

/// The crash reporter. One per process, over the C recording core.
public final class KSCrash: Sendable {
    public static let shared = KSCrash()

    private struct State {
        var configuration: InstallConfiguration?
    }

    private let state = UnfairLock(State())

    private init() {}

    /// Install the reporter. Synchronous; monitors are live when it returns.
    /// A configuration that cannot be installed as given throws `InstallError.invalidConfiguration`
    /// before anything is touched; a second install throws `InstallError.alreadyInstalled`.
    public func install(_ configuration: InstallConfiguration) throws {
        try configuration.validate()
        let locations = try configuration.locations
        try state.withLock { state in
            if state.configuration != nil {
                throw InstallError.alreadyInstalled
            }
            try configuration.install(at: locations)
            state.configuration = configuration
        }
    }

    /// The configuration the reporter was installed with; nil until `install` succeeds.
    public var installConfiguration: InstallConfiguration? {
        state.withLock { $0.configuration }
    }

    /// The registered plugin of this type, nil before install or when none was registered.
    public func installedPlugin<Plugin: MonitorPlugin>(_ type: Plugin.Type) -> Plugin? {
        installConfiguration?.plugins.lazy.compactMap { $0 as? Plugin }.first
    }
}
