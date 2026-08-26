//
//  KSCrash+Hangs.swift
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
import KSCrashRecording
import KSCrashSwiftCore

/// One change in the main thread's hang state, as the hang monitor sees it.
public struct HangEvent: Sendable, Equatable {
    public enum Change: Sendable {
        case started
        case updated
        case ended
    }

    public let change: Change
    /// Monotonic nanoseconds, as the monitor measures them.
    public let startTimestamp: UInt64
    public let endTimestamp: UInt64
}

extension KSCrash {
    /// The hang monitor's events, one stream per caller. Finishes immediately
    /// when hangs are not monitored. Events arrive from the monitor's thread.
    public var hangEvents: AsyncStream<HangEvent> {
        HangEventHub.shared.makeStream()
    }
}

/// Fans the monitor's single process-wide callback out to any number of
/// streams. The continuations live here, in Swift, so a stream's teardown
/// never races the monitor's dispatch: the monitor holds nothing to free.
private final class HangEventHub: Sendable {
    static let shared = HangEventHub()

    private struct State {
        var nextID = 0
        var continuations: [Int: AsyncStream<HangEvent>.Continuation] = [:]
        var callbackRegistered = false
    }
    private let state = UnfairLock(State())

    func makeStream() -> AsyncStream<HangEvent> {
        AsyncStream { continuation in
            guard kshang_isEnabled() else {
                continuation.finish()
                return
            }
            let id = state.withLock { state in
                if !state.callbackRegistered {
                    state.callbackRegistered = true
                    // Registered once for the process lifetime, never cleared.
                    kshang_setHangEventCallback { change, start, end in
                        HangEventHub.shared.dispatch(change, start: start, end: end)
                    }
                }
                let id = state.nextID
                state.nextID += 1
                state.continuations[id] = continuation
                return id
            }
            continuation.onTermination = { _ in
                HangEventHub.shared.endStream(id)
            }
        }
    }

    private func endStream(_ id: Int) {
        state.withLock { _ = $0.continuations.removeValue(forKey: id) }
    }

    private func dispatch(_ change: HangChangeType, start: UInt64, end: UInt64) {
        guard let change = HangEvent.Change(change) else { return }
        let event = HangEvent(change: change, startTimestamp: start, endTimestamp: end)
        // Yield outside the lock; a stream that terminated after the copy
        // ignores the yield.
        let continuations = state.withLock { Array($0.continuations.values) }
        for continuation in continuations {
            continuation.yield(event)
        }
    }
}

extension HangEvent.Change {
    fileprivate init?(_ change: HangChangeType) {
        switch change {
        case .started: self = .started
        case .updated: self = .updated
        case .ended: self = .ended
        default: return nil
        }
    }
}
