//
//  Profiler.swift
//
//  Created by Alexander Cohen on 2025-12-12.
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
import os

#if SWIFT_PACKAGE
    import KSCrashRecordingCore
#endif

/// A sampling profiler that captures backtraces of a specific thread at regular intervals.
///
/// Multiple profile sessions can be active simultaneously. Sampling runs as long as
/// at least one session is active.
///
/// ```swift
/// let profiler = Profiler(thread: pthread_self())
/// let id = profiler.beginProfile()
/// // ... do work ...
/// let profile = profiler.endProfile(id: id)
/// ```
///
/// - Note: On watchOS, backtrace capture is not supported and samples will contain empty addresses.
public final class Profiler: @unchecked Sendable {
    /// The mach thread being profiled
    let machThread: mach_port_t

    /// The interval between samples in nanoseconds
    let intervalNs: UInt64

    /// The maximum number of frames to capture per backtrace
    let maxFrames: Int

    /// Ring buffer capacity (samples) derived from retentionSeconds / interval
    let capacity: Int

    /// The queue on which sampling occurs
    let queue: DispatchQueue

    /// Lock for thread-safe access
    let lock = OSAllocatedUnfairLock()

    /// Backing storage for all captured addresses
    var addressStorage: UnsafeMutableBufferPointer<UInt>?

    /// Per-sample metadata ring
    var metas: ContiguousArray<SampleMeta>?

    /// Next slot to write
    var writeIndex: Int = 0

    /// Number of valid entries (<= capacity)
    var count: Int = 0

    /// Active profile sessions
    var activeSessions: [ProfileID: ActiveProfile] = [:]

    /// The timer used for periodic sampling
    var timer: DispatchSourceTimer?

    /// Whether profiling is currently active
    public var isRunning: Bool {
        lock.withLock { !activeSessions.isEmpty }
    }

    /// Calculates the memory footprint in bytes for a profiler with the given configuration.
    /// - Parameters:
    ///   - interval: The time interval between samples
    ///   - maxFrames: The maximum number of frames to capture per backtrace
    ///   - retentionSeconds: How many seconds of samples to retain
    /// - Returns: The total memory footprint in bytes
    public static func storageSize(
        interval: TimeInterval,
        maxFrames: Int,
        retentionSeconds: Int
    ) -> Int {
        let clampedInterval = max(0.001, interval)
        let capacity = max(1, Int((Double(retentionSeconds) / clampedInterval).rounded(.toNearestOrAwayFromZero)))
        let addressStorageSize = capacity * max(1, maxFrames) * MemoryLayout<UInt>.size
        let metasStorageSize = capacity * MemoryLayout<SampleMeta>.size
        return addressStorageSize + metasStorageSize
    }

    /// Creates a new profiler
    /// - Parameters:
    ///   - thread: The pthread to profile
    ///   - interval: The time interval between samples (default: 10ms)
    ///   - maxFrames: The maximum number of frames to capture per backtrace (default: 128)
    ///   - retentionSeconds: How many seconds of samples to retain in the ring buffer (default: 30)
    public init(
        thread: pthread_t,
        interval: TimeInterval = 0.01,
        maxFrames: Int = 128,
        retentionSeconds: Int = 30
    ) {
        self.machThread = pthread_mach_thread_np(thread)
        self.maxFrames = max(1, maxFrames)

        let clampedInterval = max(0.001, interval)
        self.intervalNs = UInt64(clampedInterval * 1_000_000_000)
        self.queue = DispatchQueue(label: "com.kscrash.profiler", qos: .userInteractive)

        let computed = Int((Double(retentionSeconds) / clampedInterval).rounded(.toNearestOrAwayFromZero))
        self.capacity = max(1, computed)

        let bytes = Self.storageSize(interval: interval, maxFrames: maxFrames, retentionSeconds: retentionSeconds)
        if bytes > 20 * 1024 * 1024 {
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
            os_log(
                .error,
                "Profiler storage size is very large: %{public}@. Consider reducing maxFrames or retentionSeconds.",
                formatted
            )
        }
    }

    /// Begins a new profile session.
    ///
    /// If this is the first active session, starts sampling.
    ///
    /// - Returns: A unique identifier for this profile session
    public func beginProfile() -> ProfileID {
        let id = ProfileID()
        let startTime = Date()
        let timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let profile = ActiveProfile(id: id, startTime: startTime, startTimestampNs: timestamp)

        lock.withLock {
            let wasEmpty = activeSessions.isEmpty
            activeSessions[id] = profile
            if wasEmpty {
                startLocked()
            }
        }

        return id
    }

    /// Ends a profile session and returns the captured profile.
    ///
    /// If this is the last active session, stops sampling.
    ///
    /// - Parameter id: The profile session identifier returned by `beginProfile()`
    /// - Returns: The completed profile with timing info and samples, or `nil` if the id is invalid
    public func endProfile(id: ProfileID) -> Profile? {
        let endTimestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        return lock.withLock {
            guard let activeProfile = activeSessions.removeValue(forKey: id) else {
                return nil
            }

            let samples = samplesInRangeLocked(from: activeProfile.startTimestampNs, to: endTimestamp)

            if activeSessions.isEmpty {
                stopLocked()
            }

            return Profile(
                id: id,
                startTime: activeProfile.startTime,
                startTimestampNs: activeProfile.startTimestampNs,
                endTimestampNs: endTimestamp,
                expectedSampleIntervalNs: intervalNs,
                samples: samples
            )
        }
    }

    deinit {
        lock.withLock {
            stopLocked()
            if let storage = addressStorage {
                storage.baseAddress?.deinitialize(count: storage.count)
                storage.baseAddress?.deallocate()
            }
        }
    }
}

// MARK: - Private

/// Internal state for an active profile session.
///
/// Tracks the session's unique identifier and start times for correlating
/// samples with the profile's time window.
struct ActiveProfile {
    /// Unique identifier for the profile session.
    let id: ProfileID
    /// Wall-clock time when the session started.
    let startTime: Date
    /// Monotonic timestamp (in nanoseconds) when the session started.
    let startTimestampNs: UInt64
}

/// Internal ring-buffer metadata for a captured sample.
///
/// Stores timing and frame count information for each sample in the ring buffer.
/// The actual frame addresses are stored separately in `addressStorage`.
struct SampleMeta: Sendable {
    /// Monotonic timestamp (in nanoseconds) when the sample capture began.
    var timestampBeginNs: UInt64
    /// Monotonic timestamp (in nanoseconds) when the sample capture ended.
    var timestampEndNs: UInt64
    /// Number of stack frames captured in this sample.
    var frameCount: Int
}

extension Profiler {
    /// Starts the sampling timer and allocates storage if needed.
    ///
    /// Lazily allocates `addressStorage` and `metas` on first call, then resets
    /// the ring buffer state and starts a repeating timer that calls `captureSample()`.
    ///
    /// - Important: Must be called while holding `lock`.
    func startLocked() {
        // Lazy allocation of storage
        if addressStorage == nil {
            let storageSize = capacity * maxFrames
            let pointer = UnsafeMutablePointer<UInt>.allocate(capacity: storageSize)
            pointer.initialize(repeating: 0, count: storageSize)
            addressStorage = UnsafeMutableBufferPointer(start: pointer, count: storageSize)
        }
        if metas == nil {
            metas = ContiguousArray(
                repeating: SampleMeta(
                    timestampBeginNs: 0,
                    timestampEndNs: 0,
                    frameCount: 0
                ),
                count: capacity
            )
        }

        // Reset ring state
        writeIndex = 0
        count = 0

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: Double(intervalNs) / 1_000_000_000,
            leeway: .milliseconds(1)
        )
        timer.setEventHandler { [weak self] in
            self?.captureSample()
        }
        timer.resume()
        self.timer = timer
    }

    /// Stops the sampling timer.
    ///
    /// Cancels and releases the timer. Does not deallocate storage.
    ///
    /// - Important: Must be called while holding `lock`.
    func stopLocked() {
        timer?.cancel()
        timer = nil
    }

    /// Retrieves samples from the ring buffer that overlap the given time range.
    ///
    /// Iterates through the ring buffer and returns samples whose capture time
    /// overlaps with `[startNs, endNs]`.
    ///
    /// - Parameters:
    ///   - startNs: Start of the time range (monotonic nanoseconds).
    ///   - endNs: End of the time range (monotonic nanoseconds).
    /// - Returns: Array of samples that overlap the time range.
    ///
    /// - Important: Must be called while holding `lock`.
    func samplesInRangeLocked(from startNs: UInt64, to endNs: UInt64) -> [Sample] {
        guard let metas = metas, let storage = addressStorage, let base = storage.baseAddress else { return [] }
        guard count > 0 else { return [] }

        var result: [Sample] = []

        // Oldest sample is at writeIndex - count (mod capacity)
        let oldest = (writeIndex - count + capacity) % capacity

        for i in 0..<count {
            let slot = (oldest + i) % capacity
            let meta = metas[slot]

            // Skip samples that do not overlap our time range
            // Include samples that have any overlap with [startNs, endNs]
            guard meta.timestampEndNs >= startNs && meta.timestampBeginNs <= endNs else { continue }

            let fc = meta.frameCount
            guard fc > 0 else { continue }

            let baseOffset = slot * maxFrames
            let addresses = Array(UnsafeBufferPointer(start: base + baseOffset, count: fc))

            result.append(
                Sample(
                    timestampBeginNs: meta.timestampBeginNs,
                    timestampEndNs: meta.timestampEndNs,
                    addresses: addresses
                ))
        }

        return result
    }

    /// Captures a single backtrace sample from the profiled thread.
    ///
    /// Called by the timer on the profiler's dispatch queue. Uses a three-phase
    /// approach to minimize lock contention:
    /// 1. Reserve a ring buffer slot and get the storage pointer (under lock)
    /// 2. Capture the backtrace (without lock)
    /// 3. Commit the sample metadata (under lock)
    ///
    /// If no active sessions exist or storage is unavailable, returns early.
    func captureSample() {
        // Phase 1: Reserve a slot and get the storage pointer under the lock
        let (slot, base): (Int, UnsafeMutablePointer<UInt>?) = lock.withLockUnchecked {
            guard !activeSessions.isEmpty else { return (-1, nil) }
            guard metas != nil, let storage = addressStorage else { return (-1, nil) }

            let slot = writeIndex
            writeIndex = (writeIndex + 1) % capacity

            // Invalidate slot while we capture
            metas![slot].frameCount = 0

            return (slot, storage.baseAddress)
        }

        guard slot >= 0, let base = base else { return }

        // Phase 2: Capture backtrace WITHOUT holding the lock
        let baseOffset = slot * maxFrames
        let timestampBegin = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        let rawCount = Int(
            captureBacktrace(
                thread: machThread,
                addresses: base.advanced(by: baseOffset),
                count: Int32(maxFrames)
            )
        )

        let timestampEnd = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        // Phase 3: Commit the sample under the lock
        lock.withLock {
            guard !activeSessions.isEmpty else { return }
            guard metas != nil else { return }

            let fc = max(0, min(rawCount, maxFrames))
            guard fc > 0 else {
                return
            }

            metas![slot].timestampBeginNs = timestampBegin
            metas![slot].timestampEndNs = timestampEnd
            metas![slot].frameCount = fc

            if count < capacity {
                count += 1
            }
        }
    }
}
