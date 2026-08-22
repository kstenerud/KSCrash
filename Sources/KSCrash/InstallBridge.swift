//
//  InstallBridge.swift
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

extension InstallConfiguration {
    /// The C configuration this one bridges to. The caller releases it with
    /// `KSCrashCConfiguration_Release`; every string and table in it is a copy.
    func makeCConfiguration() -> KSCrashCConfiguration {
        var config = KSCrashCConfiguration_Default()
        config.maxReportCount = Int32(maxReportCount)
        config.maxRunSummaryCount = Int32(maxRunSummaryCount)
        config.monitors = monitors.cValue
        config.enableQueueNameSearch = searchesQueueNames
        switch memoryIntrospection {
        case .disabled:
            config.enableMemoryIntrospection = false
        case .enabled(let excludedClasses):
            config.enableMemoryIntrospection = true
            if !excludedClasses.isEmpty {
                let strings = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: excludedClasses.count)
                for (index, name) in excludedClasses.enumerated() {
                    strings[index] = UnsafePointer(strdup(name))
                }
                config.doNotIntrospectClasses.strings = strings
                config.doNotIntrospectClasses.length = Int32(excludedClasses.count)
            }
        }
        config.addConsoleLogToReport = includesConsoleLog
        config.printPreviousLogOnStartup = printsPreviousLog
        config.enableSwapCxaThrow = swapsCxaThrow
        config.enableSwiftAsyncStackTraces = usesSwiftAsyncStackTraces
        config.enableHangReporting = reportsResolvedHangs
        config.enableCPUExceptionReporting = reportsCPUExceptions
        config.enableCompactBinaryImages = compactsBinaryImages
        config.willWriteReportCallback = unsafeCrashTimeCallbacks?.willWriteReport
        config.isWritingReportCallback = unsafeCrashTimeCallbacks?.isWritingReport
        config.didWriteReportCallback = unsafeCrashTimeCallbacks?.didWriteReport

        if !plugins.isEmpty {
            // The core copies each table into its own storage during install;
            // this array only carries them there.
            let apis = UnsafeMutablePointer<KSCrashMonitorAPI>.allocate(capacity: plugins.count)
            for (index, plugin) in plugins.enumerated() {
                apis[index] = plugin.api.pointee
            }
            config.plugins.apis = apis
            config.plugins.length = Int32(plugins.count)
            config.plugins.release = { apis in free(apis) }
        }

        return config
    }

    /// Runs the C install with this configuration at `locations`.
    func install(at locations: Locations) throws {
        var config = makeCConfiguration()
        defer { KSCrashCConfiguration_Release(&config) }
        let code = kscrash_install(locations.root.path, &config)
        if code != KSCrashInstallError.Code.none {
            throw InstallError(code: code)
        }
    }
}
