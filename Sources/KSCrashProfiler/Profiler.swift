//
//  Profiler.swift
//
//  Created by Alexander Cohen on 2026-05-10.
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

/// A profiler that records sessions delimited by ``beginProfile(named:)`` and
/// ``endProfile(id:)``, producing a `Profile` when each session ends.
///
/// This protocol describes the public surface every profiler kind shares (time-sampled,
/// allocation-tracking, future variants). Concrete profilers (`TimeProfiler`, future
/// `AllocationProfiler`) carry their own configuration on `init` (sampling interval,
/// thread, allocation hook strategy) — the protocol is only the begin/end contract.
///
/// Callers that hold a concrete profiler get the concrete `ProfileResult` type and can
/// read kind-specific data directly. Callers that hold `any Profiler` can drive sessions
/// generically; to inspect kind-specific data on the returned profile, downcast to the
/// concrete type.
public protocol Profiler: AnyObject, Sendable {
    /// The concrete profile type produced by `endProfile(id:)`.
    associatedtype ProfileResult: Profile

    /// Begins a new profile session.
    ///
    /// - Parameter named: A human-readable name for this profile session
    ///   (e.g., "AppLaunch", "NetworkRequest").
    /// - Returns: A unique identifier for the session; pass to `endProfile(id:)` to complete it.
    func beginProfile(named: String) -> ProfileID

    /// Ends a profile session and returns the captured profile.
    ///
    /// - Parameter id: The profile session identifier returned by `beginProfile(named:)`.
    /// - Returns: The completed profile, or `nil` if the id is invalid or already ended.
    func endProfile(id: ProfileID) -> ProfileResult?

    /// Whether at least one profile session is currently active.
    var isRunning: Bool { get }
}
