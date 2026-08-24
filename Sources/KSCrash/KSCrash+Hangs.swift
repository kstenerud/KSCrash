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
        AsyncStream { continuation in
            let box = Unmanaged.passRetained(HangObserverBox(continuation))
            let token = kshang_addHangObserver(
                { change, start, end, context in
                    guard let context, let change = HangEvent.Change(change) else { return }
                    Unmanaged<HangObserverBox>.fromOpaque(context).takeUnretainedValue().continuation
                        .yield(HangEvent(change: change, startTimestamp: start, endTimestamp: end))
                }, box.toOpaque())
            if token == KSHangObserverTokenNotFound {
                box.release()
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in
                kshang_removeHangObserver(token)
                box.release()
            }
        }
    }
}

private final class HangObserverBox {
    let continuation: AsyncStream<HangEvent>.Continuation
    init(_ continuation: AsyncStream<HangEvent>.Continuation) {
        self.continuation = continuation
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
