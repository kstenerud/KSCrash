//
//  SwiftAsyncCrashTrigger.swift
//
//  Created by Gleb Linnik on 28.07.2026.
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

import CrashCallback
import Foundation

// Reports a fatal user exception from inside a suspended Swift async call chain.
//
// `reportUserException` captures the current thread through `kssc_initSelfThread`, so with
// `enableSwiftAsyncStackTraces` on, the callers below are reported by `backtrace_async()` as
// continuation frames rather than as ordinary frame-pointer return addresses.

/// Source names of the helpers below, for the integration test to assert on.
public let swiftAsyncOuterFuncName = "swiftAsyncTriggerOuter"
public let swiftAsyncMiddleFuncName = "swiftAsyncTriggerMiddle"
public let swiftAsyncInnerFuncName = "swiftAsyncTriggerInner"

@inline(never)
func swiftAsyncTriggerInner() async -> Int {
    UserReportConfig.UserException(
        name: "Swift Async Exception",
        reason: "Reported from a Swift async continuation",
        language: "Swift",
        lineOfCode: swiftAsyncInnerFuncName,
        logAllThreads: true,
        terminateProgram: true
    ).report()
    return 1
}

/// The `+ 1` on the callee's result has to run *after* the await resumes, which stops the
/// compiler turning these into tail calls and collapsing the continuations the test asserts on.
/// A bare `await callee()` body would be a tail call and the frame could vanish under `-O`.
@inline(never)
func swiftAsyncTriggerMiddle() async -> Int {
    // Force a real suspension so the caller chain becomes async continuations rather than
    // plain frames the frame-pointer walker would have found anyway.
    //
    // This must not hop to the main actor: the trigger is dispatched on the main queue and the
    // handler below blocks that thread, so awaiting main-actor work here would deadlock.
    // Task.sleep resumes on the generic cooperative executor instead.
    try? await Task.sleep(nanoseconds: 10_000_000)
    return await swiftAsyncTriggerInner() + 1
}

@inline(never)
func swiftAsyncTriggerOuter() async -> Int {
    return await swiftAsyncTriggerMiddle() + 1
}

/// Registers the Swift implementation of the `user/swiftAsync` trigger. Call once at startup,
/// so both the integration-test script and the sample app's own trigger list can use it.
public func registerSwiftAsyncCrashTrigger() {
    setIntegrationTestSwiftAsyncTrigger {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            _ = await swiftAsyncTriggerOuter()
            semaphore.signal()
        }
        // The trigger API is synchronous; block until the async chain has reported.
        // `terminateProgram: true` means this normally never returns.
        _ = semaphore.wait(timeout: .now() + 30)
    }
}
