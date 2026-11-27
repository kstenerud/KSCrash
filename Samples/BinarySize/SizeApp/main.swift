//
//  main.swift
//
//  Created by Alexander Cohen on 2026-11-27.
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

// A normal install with every product an app would use, making the calls an app makes.

import KSCrash
import KSCrashBootMonitor
import KSCrashCrashReportExtension
import KSCrashDiskMonitor
import KSCrashMonitors
import KSCrashProfiler

let extensionArea = CorpseReportingConfiguration(namespace: "BinarySize", container: .appGroup("group.BinarySize"))

var configuration = InstallConfiguration(namespace: "BinarySize")
configuration.plugins = [
    DiskMonitor.plugin(),
    BootMonitor.plugin(),
    MetricKitMonitor.plugin(.init()),
    CrashReportExtensionMonitor.plugin(),
]
try KSCrash.shared.install(configuration)

let profiler = TimeProfiler.main
let profile = profiler.beginProfile(named: "BinarySize")
_ = try profiler.endProfile(id: profile)?.writeReport()

_ = Task {
    let send = SendConfiguration(reportSources: [extensionArea])
    _ = try await KSCrash.shared.sendReports(with: send)
    _ = try await KSCrash.shared.sendRunSummaries(with: send)
}
