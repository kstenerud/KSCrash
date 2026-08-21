//
//  SendDriver.swift
//
//  Created by Alexander Cohen on 2026-08-18.
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
import KSCrashSwiftCore
import os

/// What distinguishes one payload kind's send from another's: how its items
/// are listed, identified, read, and removed. Everything else is the driver's.
struct SendKind<Payload: SendPayload, Item: Sendable>: Sendable {
    /// Names the kind in logs.
    let label: String

    /// The pending items in send order, from the store's listing for this
    /// kind only. Throws when that listing cannot be read.
    let list: @Sendable (Store) throws -> [Item]

    let id: @Sendable (Item) -> Payload.ID

    /// One item's payload. nil is "not this send's item": a stale listing
    /// entry, a read failure to retry next time, or an exclusion; the item
    /// leaves no trace in the result. A throw is "read but undecodable" and
    /// becomes a kept item carrying the error.
    let read: @Sendable (Store, Item) throws -> Payload?

    let remove: @Sendable (Store, Item) throws -> Void
}

/// The send loop shared by every payload kind: the pending items, newest
/// first, one at a time through the pipeline, each outcome mapped onto disk.
/// Payloads exist one at a time, inside the loop, and are never accumulated.
enum SendDriver {

    // Pinned off the caller's actor wherever the attribute exists (Swift 6.2+);
    // older toolchains run nonisolated async functions off-actor by default, so
    // the guarantee holds under every supported compiler.
    #if hasAttribute(concurrent)
        @concurrent
    #endif
    static func send<Payload: SendPayload, Item: Sendable>(
        store: Store?,
        kind: SendKind<Payload, Item>,
        pipeline: [AnyPipelineStage<Payload>],
        maxRunCount: Int,
        only selection: Set<Payload.ID>?,
        claims: SendClaims<Payload.ID>
    ) async throws -> SendResult<Payload> {
        // A send with no stages can only mean a misconfigured caller, so it
        // throws regardless of install state instead of quietly purging.
        guard !pipeline.isEmpty else {
            throw SendError.emptyPipeline
        }

        // Not installed (no resolved locations): an empty result rather than
        // an error.
        guard let store else {
            return SendResult(items: [])
        }

        // Run-summary retention is enforced on every bulk send, so an app
        // that only ever sends reports still cannot grow `.run` files
        // without bound. Pruning before the listing keeps files that are
        // about to be deleted out of it. A selective send never prunes: it
        // touches only the items it names, and pruning here would delete
        // beyond-cap runs the caller is deliberately retrying.
        if selection == nil {
            store.pruneRunSummaries(keepingNewest: maxRunCount)
        }

        var items = try kind.list(store)
        if let selection {
            // Unselected items are not this send's: untouched on disk and
            // absent from the result, exactly like items claimed by a
            // concurrent send.
            items = items.filter { selection.contains(kind.id($0)) }
        }
        // However the send ends past this point (exhausted, cancelled, or a
        // crash of a stage's task), sweep once: the reclaim is reference-aware
        // and idempotent, so it is safe on every exit path.
        defer { store.reclaimOrphans() }

        var results: [SendResult<Payload>.Item] = []
        for item in items {
            // Between items is the clean stopping point: no item is ever half
            // processed, and everything not yet sent stays for next time.
            if Task.isCancelled {
                break
            }
            let id = kind.id(item)
            // Claiming is what lets concurrent sends partition the pending
            // work instead of duplicating it: an item another send holds is
            // not this send's item and is not reported by it.
            guard claims.claim(id) else {
                continue
            }
            defer { claims.release(id) }

            let start = DispatchTime.now()
            func finish(_ outcome: SendResult<Payload>.Outcome) {
                let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                results.append(
                    SendResult.Item(id: id, outcome: outcome, duration: TimeInterval(elapsedNs) / 1_000_000_000))
            }

            // Under the claim, deletes are ours alone, so a nil read is a
            // race-free "not an item" check.
            let payload: Payload
            do {
                guard let read = try kind.read(store, item) else {
                    continue
                }
                payload = read
            } catch {
                finish(.kept(error))
                continue
            }

            let outcome = await runPipeline(payload, through: pipeline)
            if case .kept = outcome {
            } else {
                remove(item, id: id, kind: kind, from: store)
            }
            finish(outcome)
        }
        return SendResult(items: results)
    }

    // A failed delete is logged, not thrown: the item was already processed,
    // and the file will be re-sent or pruned later, which is the retry-safe
    // direction.
    private static func remove<Payload: SendPayload, Item: Sendable>(
        _ item: Item, id: Payload.ID, kind: SendKind<Payload, Item>, from store: Store
    ) {
        do {
            try kind.remove(store, item)
        } catch {
            os_log(.error, "Failed to delete %{public}@ %{public}@", kind.label, String(describing: id))
        }
    }
}

/// The items currently being processed by any send of one kind, so concurrent
/// sends partition the pending work: claiming is first-wins, and a claim is
/// held only while its item is being processed.
final class SendClaims<ID: Hashable & Sendable>: Sendable {
    private let claimed = UnfairLock(Set<ID>())

    func claim(_ id: ID) -> Bool {
        claimed.withLock { $0.insert(id).inserted }
    }

    func release(_ id: ID) {
        claimed.withLock { _ = $0.remove(id) }
    }
}
