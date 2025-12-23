//
//  Thread.swift
//
//  Created by Alexander Cohen on 2024-12-09.
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

extension CrashReport {
    /// Information about a thread at the time of crash.
    public struct Thread: Decodable, Sendable {
        /// Stack backtrace for this thread.
        public let backtrace: Backtrace?

        /// Whether this thread crashed.
        public let crashed: Bool

        /// Whether this is the current thread being executed.
        public let currentThread: Bool

        /// Dispatch queue this thread was executing on (if any).
        public let dispatchQueue: String?

        /// Thread index.
        public let index: Int

        /// Thread name (if set).
        public let name: String?

        /// Notable memory addresses and their contents.
        public let notableAddresses: [String: NotableAddress]?

        /// CPU register values.
        public let registers: Registers?

        /// Stack memory dump.
        public let stack: StackDump?

        /// Thread state (e.g., "TH_STATE_RUNNING", "TH_STATE_WAITING").
        public let state: String?

        enum CodingKeys: String, CodingKey {
            case backtrace
            case crashed
            case currentThread = "current_thread"
            case dispatchQueue = "dispatch_queue"
            case index
            case name
            case notableAddresses = "notable_addresses"
            case registers
            case stack
            case state
        }
    }
}
