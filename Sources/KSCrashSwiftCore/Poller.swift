//
//  Poller.swift
//
//  Created by Alexander Cohen on 2025-12-14.
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

/// A repeating background task: fires every `interval`, first fire one
/// `interval` after `start`. `start` and `stop` are idempotent; the handler
/// runs on `queue`.
public final class Poller: @unchecked Sendable {
    private let interval: TimeInterval
    private let leeway: DispatchTimeInterval
    private let queue: DispatchQueue
    private let handler: @Sendable () -> Void
    private let timer = UnfairLock<DispatchSourceTimer?>(nil)

    /// nil unless `interval` is a positive, finite number of seconds: a knob
    /// like this can arrive from remote configuration, so a bad value must
    /// surface as absence, never as a trap or a busy loop.
    public init?(
        every interval: TimeInterval, leeway: DispatchTimeInterval? = nil,
        queue: DispatchQueue, handler: @escaping @Sendable () -> Void
    ) {
        guard interval > 0, interval.isFinite else { return nil }
        self.interval = interval
        // Apple's timer-tolerance guidance: at least 10% of the interval, so
        // the system can coalesce wake-ups. Saturate at Int.max, whatever its
        // width: Double(Int.max) rounds to one past the maximum on 64-bit, so
        // any value at or above it is unconvertible, and on 32-bit Int
        // (arm64_32 watches) that starts at intervals near 21 seconds.
        let nanoseconds = interval * 0.1 * Double(NSEC_PER_SEC)
        self.leeway = leeway ?? .nanoseconds(nanoseconds >= Double(Int.max) ? Int.max : Int(nanoseconds))
        self.queue = queue
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() {
        timer.withLock { timer in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
            source.setEventHandler(handler: handler)
            source.resume()
            timer = source
        }
    }

    public func stop() {
        timer.withLock { timer in
            timer?.cancel()
            timer = nil
        }
    }
}
