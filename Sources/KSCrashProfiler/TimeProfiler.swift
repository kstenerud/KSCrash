//
//  TimeProfiler.swift
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
import KSCrashRecordingCore
import SwiftCore
import os

/// A sampling profiler that captures backtraces of a specific thread at regular intervals.
///
/// The profiler uses a pre-allocated flat ring buffer of frame addresses to store captured
/// backtraces, plus a parallel array of per-slot metadata. Samples are written into the
/// ring directly during capture; when the buffer is full, the oldest samples are
/// overwritten.
///
/// Multiple profile sessions can be active simultaneously on the same profiler instance.
/// Sampling runs continuously as long as at least one session is active, and samples are
/// shared across overlapping sessions based on their time windows.
///
/// ## Usage
///
/// ```swift
/// let profiler = TimeProfiler(thread: pthread_self())
/// let id = profiler.beginProfile(named: "MyOperation")
/// // ... do work ...
/// let profile = profiler.endProfile(id: id)!
/// print("Captured \(profile.samples.count) samples")
/// ```
///
/// ## Report Writing
///
/// To write a crash report containing the profile data, call `writeReport()` on the
/// returned profile. Since this performs synchronous disk I/O, it should be called
/// from a background queue:
///
/// ```swift
/// let profile = profiler.endProfile(id: id)!
/// DispatchQueue.global().async {
///     if let url = profile.writeReport() {
///         print("Report written to: \(url.path)")
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// All public methods are thread-safe. The profiler uses an unfair lock to protect
/// internal state and the ring buffer.
///
/// - Note: On watchOS, backtrace capture is not supported and samples will contain empty addresses.
public final class TimeProfiler: Profiler, @unchecked Sendable {

    public typealias ProfileResult = TimeProfile

    /// The mach thread being profiled
    public let machThread: thread_t

    /// The interval between samples in nanoseconds
    public let intervalNs: UInt64

    /// Maximum number of frames captured per backtrace.
    public let maxFrames: Int

    /// Set of unwind methods the profiler tries per frame. Configured at init.
    /// See `KSBacktraceUnwindMethods` for trade-offs and presets like `.fast` /
    /// `.accurate`.
    public let unwindMethods: KSBacktraceUnwindMethods

    /// Maximum number of samples to retain in the ring buffer.
    public let capacity: Int

    /// The queue on which sampling occurs.
    let samplingQueue: DispatchQueue

    /// Lock for thread-safe access.
    let lock = UnfairLock()

    /// Per-slot metadata (timing + addressCount). One entry per ring slot.
    var slots: ContiguousArray<SampleSlot>

    /// Flat address pool: `capacity` slots × `maxFrames` `UInt`s each.
    /// Slot `i` occupies `addressPool[i*maxFrames ..< i*maxFrames + maxFrames]`.
    let addressPool: UnsafeMutablePointer<UInt>

    /// Scratch buffer used by the timer to unwind into without holding the lock.
    /// Owned exclusively by the sampling queue.
    let scratchAddresses: UnsafeMutablePointer<UInt>

    /// Next write position in ring buffer.
    var writeIndex: Int = 0

    /// Number of valid samples in buffer (0...capacity).
    var sampleCount: Int = 0

    /// Active profile sessions.
    var activeSessions: [ProfileID: ActiveProfile] = [:]

    /// The timer used for periodic sampling.
    var timer: DispatchSourceTimer?

    /// Whether profiling is currently active.
    public var isRunning: Bool {
        lock.withLock { !activeSessions.isEmpty }
    }

    /// Calculates the memory footprint in bytes for a profiler with the given configuration.
    /// Counts only the ring storage (address pool + slot metadata + scratch).
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
        // Mirror init's clamp so storageSize and the actual allocation agree, and so the
        // `frames * MemoryLayout<UInt>.size` term below can't overflow on extreme inputs.
        let frames = max(1, min(maxFrames, Int(KSSC_MAX_STACK_DEPTH)))

        let pool = capacity.multipliedReportingOverflow(by: frames * MemoryLayout<UInt>.size)
        let slots = capacity.multipliedReportingOverflow(by: MemoryLayout<SampleSlot>.size)
        let scratch = frames * MemoryLayout<UInt>.size

        if pool.overflow || slots.overflow { return Int.max }
        let (sum1, o1) = pool.partialValue.addingReportingOverflow(slots.partialValue)
        if o1 { return Int.max }
        let (total, o2) = sum1.addingReportingOverflow(scratch)
        return o2 ? Int.max : total
    }

    /// Creates a new profiler.
    /// - Parameters:
    ///   - thread: The pthread to profile.
    ///   - interval: The time interval between samples (default: 10ms).
    ///   - maxFrames: Maximum frames captured per backtrace (default: 128).
    ///   - retentionSeconds: How many seconds of samples to retain in the ring buffer (default: 30).
    ///   - unwindMethods: Bitmask of unwind strategies. Default `.fast`
    ///     (compact unwind + frame pointer fallback). See `KSBacktraceUnwindMethods`.
    public convenience init(
        thread: pthread_t,
        interval: TimeInterval = 0.01,
        maxFrames: Int = 128,
        retentionSeconds: Int = 30,
        unwindMethods: KSBacktraceUnwindMethods = .fast
    ) {
        self.init(
            machThread: pthread_mach_thread_np(thread),
            interval: interval,
            maxFrames: maxFrames,
            retentionSeconds: retentionSeconds,
            unwindMethods: unwindMethods
        )
    }

    /// Creates a new profiler.
    /// - Parameters:
    ///   - machThread: The mach thread to profile.
    ///   - interval: The time interval between samples (default: 10ms).
    ///   - maxFrames: Maximum frames captured per backtrace (default: 128).
    ///   - retentionSeconds: How many seconds of samples to retain in the ring buffer (default: 30).
    ///   - unwindMethods: Bitmask of unwind strategies. Default `.fast`
    ///     (compact unwind + frame pointer fallback). See `KSBacktraceUnwindMethods`.
    public init(
        machThread: thread_t,
        interval: TimeInterval = 0.01,
        maxFrames: Int = 128,
        retentionSeconds: Int = 30,
        unwindMethods: KSBacktraceUnwindMethods = .fast
    ) {
        self.machThread = machThread

        let clampedInterval = max(0.001, interval)
        self.intervalNs = UInt64(clampedInterval * 1_000_000_000)
        self.samplingQueue = DispatchQueue(label: "com.kscrash.profiler.sampling", qos: .userInteractive)
        // Clamp to the unwinder's hard cap. Asking for more than KSSC_MAX_STACK_DEPTH
        // wastes pool memory: the C unwinder won't fill past that anyway, and unclamped
        // values flow into capacity * maxFrames below where they could overflow Int.
        self.maxFrames = max(1, min(maxFrames, Int(KSSC_MAX_STACK_DEPTH)))
        self.unwindMethods = unwindMethods

        let computed = Int((Double(retentionSeconds) / clampedInterval).rounded(.toNearestOrAwayFromZero))
        self.capacity = max(1, computed)

        // Pre-allocate slot metadata + flat address pool + scratch.
        self.slots = ContiguousArray(repeating: SampleSlot(), count: self.capacity)
        self.addressPool = UnsafeMutablePointer<UInt>.allocate(capacity: self.capacity * self.maxFrames)
        self.addressPool.initialize(repeating: 0, count: self.capacity * self.maxFrames)
        self.scratchAddresses = UnsafeMutablePointer<UInt>.allocate(capacity: self.maxFrames)
        self.scratchAddresses.initialize(repeating: 0, count: self.maxFrames)

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
    /// If this is the first active session, starts sampling. The profile name is used
    /// to identify this profiling session in reports and logs.
    ///
    /// - Parameter named: A human-readable name for this profile session (e.g., "AppLaunch", "NetworkRequest").
    /// - Returns: A unique identifier for this profile session. Pass this to `endProfile(id:)` to complete the session.
    public func beginProfile(named: String) -> ProfileID {
        let id = ProfileID()
        let startTime = Date()
        let timestamp = ksdate_uptimeNanoseconds()
        let profile = ActiveProfile(id: id, name: named, startTime: startTime, startTimestampNs: timestamp)

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
    /// - Parameter id: The profile session identifier returned by `beginProfile(named:)`.
    /// - Returns: The completed profile with timing info and samples, or `nil` if the id is invalid.
    public func endProfile(id: ProfileID) -> TimeProfile? {
        let endTimestamp = ksdate_uptimeNanoseconds()

        return lock.withLock {
            guard let activeProfile = activeSessions.removeValue(forKey: id) else {
                return nil
            }

            let inRange = samplesInRangeLocked(
                from: activeProfile.startTimestampNs,
                to: endTimestamp
            )

            if activeSessions.isEmpty {
                stopLocked()
            }

            return TimeProfile(
                id: id,
                name: activeProfile.name,
                thread: machThread,
                startTime: activeProfile.startTime,
                startTimestampNs: activeProfile.startTimestampNs,
                endTimestampNs: endTimestamp,
                expectedSampleIntervalNs: intervalNs,
                samples: inRange.samples,
                truncatedSampleCount: inRange.truncatedCount
            )
        }
    }

    deinit {
        // Safe to free addressPool/scratchAddresses without draining samplingQueue:
        // the timer event handler is `{ [weak self] in self?.captureSample() }`. By
        // the time deinit runs, the strong refcount is 0, so a queued handler's `self?`
        // resolves to nil and the call becomes a no-op. An in-flight captureSample
        // holds a strong-via-weak ref for the duration of the call, keeping refcount
        // ≥ 1 and blocking deinit from starting until it returns. If anyone changes
        // `[weak self]` to `[unowned self]`, both invariants break — drain the queue
        // here instead.
        lock.withLock {
            stopLocked()
        }
        addressPool.deinitialize(count: capacity * maxFrames)
        addressPool.deallocate()
        scratchAddresses.deinitialize(count: maxFrames)
        scratchAddresses.deallocate()
    }
}

extension TimeProfiler {
    /// A shared profiler instance that samples the main thread.
    ///
    /// Default sampling interval (10ms), retention (30s). Uses `maxFrames: 512`
    /// (the unwinder's hard cap) rather than the init default of 128: the main
    /// thread can run very deep stacks (SwiftUI/Combine, deeply nested callbacks),
    /// and `captureBacktrace` discards truncated samples, so a too-small cap silently
    /// drops the deepest captures instead of clipping them.
    public static let main: TimeProfiler = TimeProfiler(machThread: thread_t(ksthread_main()), maxFrames: 512)
}

// MARK: - Private

/// Internal state for an active profile session.
///
/// Tracks the session's unique identifier and start times for correlating
/// samples with the profile's time window.
struct ActiveProfile {
    /// Unique identifier for the profile session.
    let id: ProfileID
    /// Name for this profile session.
    let name: String
    /// Wall-clock time when the session started.
    let startTime: Date
    /// Monotonic timestamp (in nanoseconds) when the session started.
    let startTimestampNs: UInt64
}

/// Per-slot metadata for the ring buffer. Frame addresses live in the parallel
/// flat `addressPool` (slot `i` at offset `i * maxFrames`).
struct SampleSlot {
    var metadata: SampleMetadata = SampleMetadata()
    /// Number of valid frames in this slot's address-pool window.
    /// `Int32` since stack depths fit comfortably in 31 bits.
    var addressCount: Int32 = 0
    /// True when the unwinder produced a truncated stack (deeper than `maxFrames`).
    /// `addressCount` is forced to 0 in that case so the slot is treated as empty
    /// by `samplesInRangeLocked`'s frame loop, but the flag still lets us count
    /// the drop.
    var truncated: Bool = false
}

extension TimeProfiler {
    /// Starts the sampling timer.
    ///
    /// Resets ring buffer state and starts a repeating timer that calls `captureSample()`.
    ///
    /// - Important: Must be called while holding `lock`.
    func startLocked() {
        // Reset ring buffer state.
        writeIndex = 0
        sampleCount = 0

        let timer = DispatchSource.makeTimerSource(queue: samplingQueue)
        // Leeway scales with interval: ~10% of the interval, clamped to [10µs, 5ms].
        // The previous fixed 1ms leeway was 100% slop for a 1ms sampling interval,
        // which let the kernel coalesce wake-ups and inflate inter-sample gaps. A
        // smaller leeway tightens P95/P99 timing at a small battery cost.
        let leewayNs = max(10_000, min(5_000_000, intervalNs / 10))
        timer.schedule(
            deadline: .now(),
            repeating: Double(intervalNs) / 1_000_000_000,
            leeway: .nanoseconds(Int(leewayNs))
        )
        timer.setEventHandler { [weak self] in
            self?.captureSample()
        }
        timer.resume()
        self.timer = timer
    }

    /// Stops the sampling timer.
    ///
    /// Cancels and releases the timer.
    ///
    /// - Important: Must be called while holding `lock`.
    func stopLocked() {
        timer?.cancel()
        timer = nil
    }

    /// Captures a single backtrace sample from the profiled thread.
    ///
    /// Called periodically by the timer on the profiler's dispatch queue.
    ///
    /// The expensive part — the backtrace unwind itself — runs lock-free into
    /// `scratchAddresses`. Only the brief publish step (memcpy into the slot's
    /// pool window plus index bump) holds `lock`. Lock hold time drops from
    /// the unwind duration (~100–300 µs) to a small memcpy (8 × addressCount
    /// bytes), so concurrent `beginProfile`/`endProfile` callers no longer
    /// wait on the unwind.
    ///
    /// `scratchAddresses` is exclusively owned by the sampling queue: the
    /// timer is serialized, and `captureSample` is the only function that
    /// touches it. No locking is required around the unwind.
    func captureSample() {
        // Unwind into scratch without holding the publish lock.
        let beginNs = ksdate_uptimeNanoseconds()
        var isTruncated = false
        let captured = captureBacktrace(
            machThread: machThread,
            addresses: scratchAddresses,
            count: Int32(maxFrames),
            isTruncated: &isTruncated,
            methods: unwindMethods
        )
        let endNs = ksdate_uptimeNanoseconds()

        // Discard truncated backtraces (incomplete) — match prior behaviour.
        let count = isTruncated ? 0 : Int(captured)

        // Briefly take the lock to publish into the ring.
        lock.withLock {
            guard !activeSessions.isEmpty else { return }
            let slot = writeIndex
            slots[slot] = SampleSlot(
                metadata: SampleMetadata(timestampBeginNs: beginNs, timestampEndNs: endNs),
                addressCount: Int32(count),
                truncated: isTruncated
            )
            if count > 0 {
                addressPool.advanced(by: slot * maxFrames).update(from: scratchAddresses, count: count)
            }
            writeIndex = (writeIndex + 1) % capacity
            if sampleCount < capacity {
                sampleCount += 1
            }
        }
    }

    /// Retrieves samples whose unwind began inside the given time range.
    ///
    /// Membership rule: a sample belongs to the range when its `timestampBeginNs`
    /// (the moment its unwind started) falls in `[startNs, endNs]`. A sample whose
    /// unwind began before `startNs` is excluded even if its `timestampEndNs`
    /// crosses into the range — that capture sampled thread state from before the
    /// profile window opened, so attributing it here would be misleading. This
    /// also prevents an in-flight capture that publishes after a new profile
    /// starts from being attributed to the new profile.
    ///
    /// Samples are written to the ring in timer order, so logical-index ordering
    /// matches chronological ordering. Binary-search for the first slot whose
    /// `timestampBeginNs >= startNs`, then walk forward until a slot's
    /// `timestampBeginNs > endNs`. This avoids scanning the prefix of stale
    /// samples that fall before the range, which matters when the retention
    /// buffer is much longer than the profiled span (e.g., a 5s profile inside
    /// a 30s ring).
    ///
    /// Materialization makes a deep copy of each matching slot's frame addresses
    /// out of the address pool, so the returned `[Sample]` survives subsequent
    /// ring overwrites.
    ///
    /// - Parameters:
    ///   - startNs: Start of the time range (monotonic nanoseconds from `CLOCK_UPTIME_RAW`).
    ///   - endNs: End of the time range (monotonic nanoseconds from `CLOCK_UPTIME_RAW`).
    /// - Returns: A pair of (samples whose unwind began inside the range, in chronological order;
    ///   count of slots inside the range whose unwind produced a truncated stack).
    ///
    /// - Important: Must be called while holding `lock`.
    func samplesInRangeLocked(from startNs: UInt64, to endNs: UInt64) -> (samples: [Sample], truncatedCount: Int) {
        guard sampleCount > 0 else { return ([], 0) }

        // Calculate the oldest sample's position in the ring buffer.
        let oldest = (writeIndex - sampleCount + capacity) % capacity

        @inline(__always) func physicalSlot(_ logicalIndex: Int) -> Int {
            (oldest + logicalIndex) % capacity
        }

        // Binary search for the first sample whose begin timestamp is >= startNs.
        // Logical indices preserve capture order, so begin timestamps are non-decreasing.
        var lo = 0
        var hi = sampleCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if slots[physicalSlot(mid)].metadata.timestampBeginNs < startNs {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        var result: [Sample] = []
        result.reserveCapacity(sampleCount - lo)
        var truncatedCount = 0

        for i in lo..<sampleCount {
            let slot = physicalSlot(i)
            let s = slots[slot]

            // Past the range — no later sample can match either.
            if s.metadata.timestampBeginNs > endNs { break }

            if s.truncated {
                // Slot's unwind produced a truncated stack; count it but don't
                // synthesize a Sample (no usable frames).
                truncatedCount += 1
                continue
            }
            // Skip slots that are simply empty (no frames captured, not truncated).
            if s.addressCount <= 0 { continue }

            let n = Int(s.addressCount)
            var addrs = [UInt](repeating: 0, count: n)
            addrs.withUnsafeMutableBufferPointer { dst in
                let src = addressPool.advanced(by: slot * maxFrames)
                dst.baseAddress?.update(from: src, count: n)
            }
            result.append(Sample(metadata: s.metadata, addresses: addrs))
        }

        return (result, truncatedCount)
    }
}
