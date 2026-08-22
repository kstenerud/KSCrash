//
//  SendResult.swift
//
//  Created by Alexander Cohen on 2026-08-10.
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
import KSCrashReportModel

/// A payload kind the store holds and a send walks, with the identity the
/// store keys it by: `ReportID` for reports, `RunSummary.ID` for run summaries.
/// The selective sends take these ids back.
public protocol SendPayload: PipelineValue {
    associatedtype ID: Hashable & Sendable
}

extension Report: SendPayload {
    public typealias ID = ReportID
}

extension RunSummary: SendPayload {}

/// The per-item outcomes of one send, in processing order. Items being
/// processed by a concurrent send are not part of this send and do not appear.
public struct SendResult<Payload: SendPayload>: Sendable {

    /// What happened to one item.
    public enum Outcome: Sendable {
        /// The item completed the pipeline and its file is deleted. A
        /// failed delete is not surfaced here: the next send processes the
        /// item again.
        case delivered

        /// A stage returned nil: the item's file is deleted and it is never
        /// sent again. A failed delete is not surfaced here: the next send
        /// processes the item again.
        case discarded

        /// A stage threw this error, or the item was read but does not
        /// decode: the item stays on disk and is retried by the next send.
        case kept(any Error)
    }

    public struct Item: Sendable {
        public let id: Payload.ID
        public let outcome: Outcome

        /// Time spent loading and processing this item, in seconds.
        public let duration: TimeInterval
    }

    public let items: [Item]

    /// Ids of the items that completed the pipeline, in processing order.
    public var delivered: [Payload.ID] {
        items.compactMap { item in
            if case .delivered = item.outcome { return item.id }
            return nil
        }
    }

    /// Ids of the items a stage discarded, in processing order.
    public var discarded: [Payload.ID] {
        items.compactMap { item in
            if case .discarded = item.outcome { return item.id }
            return nil
        }
    }

    /// Ids of the items left on disk for the next send, in processing order.
    public var kept: [Payload.ID] {
        items.compactMap { item in
            if case .kept = item.outcome { return item.id }
            return nil
        }
    }
}
