//
//  LiveMetadata.swift
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
import KSCrashMonitorPlugins
import KSCrashRecordingCore
import KSCrashReportModel
import KSCrashSwiftCore
import os

/// The run's metadata as the crash reporter records it: values set here are
/// attached to the run's reports and run summary when they are delivered.
/// Before install there is no store: reads are nil, and a set traps in debug
/// as a misuse signal (the value is dropped in release).
///
/// Dates range from 1677-09-21 to 2262-04-11; assigning one outside that range
/// removes the key instead of storing it.
public final class LiveMetadata: MetadataStore, Sendable {
    /// The store's shapes. Readers need no configuration, so these bound only
    /// what a writer accepts; a write with a longer key or string is rejected.
    private enum StoreLimits {
        static let initialCapacity: UInt32 = 4096
        static let maxKeyLength: UInt16 = 256
        static let maxStringLength: UInt16 = 1024
    }

    private struct State {
        var store: SidecarMetadata?
        var unavailableReason: InstallError?
    }

    private let state = UnfairLock(State())

    init() {}

    /// Why the live store could not be created; nil while the store works or
    /// before install. Crash reporting is unaffected: with no store, sets are
    /// no-ops and reads are nil.
    public var unavailableReason: InstallError? {
        state.withLock { $0.unavailableReason }
    }

    /// Opens the store at `path`. Called once by install; a second call
    /// keeps the first store. A failure is recorded as `unavailableReason`
    /// and thrown.
    func attach(path: String) throws {
        try state.withLock { state in
            guard state.store == nil else { return }
            let config = KSKVSConfig(
                initialCapacity: StoreLimits.initialCapacity,
                maxKeyLength: StoreLimits.maxKeyLength,
                maxStringLength: StoreLimits.maxStringLength)
            do {
                state.store = try SidecarMetadata.creating(at: path, config: config)
                state.unavailableReason = nil
            } catch let error as SidecarMetadata.OpenError {
                let reason = InstallError.metadataStoreUnavailable(
                    "creating the store failed (status \(error.status.rawValue))")
                state.unavailableReason = reason
                throw reason
            }
        }
    }

    /// Records why install could not reach a store path; the store stays absent.
    func markUnavailable(_ reason: InstallError) {
        state.withLock { state in
            guard state.store == nil else { return }
            state.unavailableReason = reason
        }
    }

    // The store operation itself runs inside the lock: the kvs is
    // caller-synchronized, and this lock is its synchronization.
    public subscript<Value: MetadataValueRepresentable>(key: String) -> Value? {
        get { state.withLock { $0.store?[key] } }
        set {
            state.withLock { state in
                guard let store = state.store else {
                    return notedDroppedWrite(unavailableReason: state.unavailableReason, key: key)
                }
                store[key] = newValue
            }
        }
    }

    public func removeValue(forKey key: String) {
        state.withLock { state in
            guard let store = state.store else {
                return notedDroppedWrite(unavailableReason: state.unavailableReason, key: key)
            }
            store.removeValue(forKey: key)
        }
    }

    /// A write with no store: loud in debug when the cause is calling before
    /// install (a programmer error); quiet when install degraded, which
    /// `unavailableReason` already records.
    private func notedDroppedWrite(unavailableReason: InstallError?, key: String) {
        guard unavailableReason == nil else { return }
        os_log(.error, "Metadata write for key \"%{public}@\" dropped: not installed yet", key)
        assertionFailure("metadata write for key \"\(key)\" before install; the value is dropped")
    }

    public var keys: [String] {
        state.withLock { $0.store?.keys ?? [] }
    }
}
