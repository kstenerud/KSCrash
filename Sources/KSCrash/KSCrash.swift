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
import os

/// The crash reporter. One per process, over the C recording core.
public final class KSCrash: Sendable {
    public static let shared = KSCrash()

    private struct State {
        var configuration: InstallConfiguration?
        var installing = false
    }

    private let state = UnfairLock(State())

    /// The run's metadata, written through to the crash reporter as it changes.
    public let metadata = LiveMetadata()

    let sessionRecorder = SessionRecorder()

    // Serializes the metadata write + session cut pair in setUserID; each half
    // locks internally, but only this keeps concurrent calls from
    // cross-attributing the two.
    let userIDLock = UnfairLock(())

    private init() {}

    /// Install the reporter. Synchronous; monitors are live when it returns.
    /// A configuration that cannot be installed as given throws `InstallError.invalidConfiguration`
    /// before anything is touched; a second install throws `InstallError.alreadyInstalled`.
    public func install(_ configuration: InstallConfiguration) throws {
        try configuration.validate()
        let locations = try configuration.locations
        // The lock guards only the state transitions. The C install and the
        // attach work run outside it: they call plugin callbacks that may
        // reasonably read KSCrash.shared, and the lock is not reentrant.
        try state.withLock { state in
            if state.configuration != nil || state.installing {
                throw InstallError.alreadyInstalled
            }
            state.installing = true
        }
        do {
            try configuration.install(at: locations)
            // Crash capture is armed; a metadata-store failure degrades metadata
            // only, recorded as metadata.unavailableReason, never a failed install.
            do {
                // The same path provider the monitors use; it also creates the run directory.
                var sidecarPath = [CChar](repeating: 0, count: Int(KSCRS_MAX_PATH_LENGTH))
                guard
                    kscrs_getRunSidecarFilePath(
                        KSCRS_MONITOR_ID_USERINFO, &sidecarPath, sidecarPath.count,
                        kscrash_getReportStoreConfiguration())
                else {
                    throw InstallError.metadataStoreUnavailable("no run sidecar path for the metadata store")
                }
                try metadata.attach(path: String(cString: sidecarPath))
            } catch let error as InstallError {
                metadata.markUnavailable(error)
                os_log(.error, "Live metadata is unavailable: %{public}@", String(describing: error))
            }
            var sessionsPath = [CChar](repeating: 0, count: Int(KSCRS_MAX_PATH_LENGTH))
            if kscrs_getSummarySidecarFilePath(
                kscrash_getRunID(), KSCRS_SESSIONS_FILENAME_EXTENSION, &sessionsPath, sessionsPath.count,
                kscrash_getReportStoreConfiguration())
            {
                // The path getter is pure; the writer's call site owns directory creation.
                let path = String(cString: sessionsPath)
                do {
                    try FileManager.default.createDirectory(
                        at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
                    sessionRecorder.attach(path: path)
                } catch {
                    os_log(
                        .error, "Session recording is unavailable: %{public}@", String(describing: error))
                }
            } else {
                os_log(.error, "Session recording is unavailable: no sessions path")
            }
        } catch {
            state.withLock { $0.installing = false }
            throw error
        }
        state.withLock { state in
            state.configuration = configuration
            state.installing = false
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
