//
//  MonitorRegistryTrapTests.swift
//
//  Created by Alexander Cohen on 2026-07-19.
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

// Exit tests spawn a child process, so they exist only where a process can be spawned, and
// the API itself arrived in Swift Testing 6.2, so older toolchains must not see it.
#if os(macOS) && compiler(>=6.2)

    import KSCrashRecordingCore
    import Testing

    private let duplicateID = strdup("DuplicateMonitorID")

    private func monitorWithDuplicateID() -> UnsafeMutablePointer<KSCrashMonitorAPI> {
        let api = UnsafeMutablePointer<KSCrashMonitorAPI>.allocate(capacity: 1)
        api.initialize(to: KSCrashMonitorAPI())
        api.pointee.monitorId = { _ in UnsafePointer(duplicateID) }
        // kscm_addMonitor calls init on a monitor it accepted; the rest stay null, since a
        // registration this test never completes reaches nothing else.
        api.pointee.`init` = { _, _ in }
        return api
    }

    /// Registering an id that is already taken is a programmer error: ids route report sections,
    /// sidecar directories and stitching, so the registry refuses the monitor and traps in debug.
    /// The trap kills the process, hence an exit test rather than a plain assertion.
    ///
    /// Any abnormal exit counts, not SIGABRT specifically: under a sanitizer the abort surfaces
    /// as a different signal. The monitor's callbacks are stubbed so the assert is the only
    /// thing that can kill the child.
    @Test func duplicateMonitorIDTrapsInDebugBuilds() async {
        await #expect(processExitsWith: .failure) {
            _ = kscm_addMonitor(monitorWithDuplicateID())
            _ = kscm_addMonitor(monitorWithDuplicateID())
        }
    }

#endif
