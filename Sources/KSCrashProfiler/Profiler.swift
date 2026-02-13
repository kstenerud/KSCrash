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
/// The profiler uses a pre-allocated ring buffer of `Sample` structs to store captured backtraces.
/// Samples are captured directly into the ring buffer to minimize allocations during profiling.
/// When the buffer is full, the oldest samples are overwritten.
///
/// Multiple profile sessions can be active simultaneously on the same profiler instance.
/// Sampling runs continuously as long as at least one session is active, and samples are
/// shared across overlapping sessions based on their time windows.
///
/// ## Usage
///
/// ```swift
/// let profiler = Profiler<Sample128>(thread: pthread_self())
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
public final class Profiler<T: Sample>: @unchecked Sendable {
    /// The mach thread being profiled
    let machThread: thread_t

    /// The interval between samples in nanoseconds
    let intervalNs: UInt64

    /// Maximum number of samples to retain
    let capacity: Int

    /// The queue on which sampling occurs
    let samplingQueue: DispatchQueue

    /// Lock for thread-safe access
    let lock = UnfairLock()

    /// Ring buffer of samples (pre-allocated)
    var samples: ContiguousArray<T>

    /// Next write position in ring buffer
    var writeIndex: Int = 0

    /// Number of valid samples in buffer (0...capacity)
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
        retentionSeconds: Int
    ) -> Int {
        let clampedInterval = max(0.001, interval)
        let capacity = max(1, Int((Double(retentionSeconds) / clampedInterval).rounded(.toNearestOrAwayFromZero)))

        // Estimate: Sample struct size (includes inline address storage)
        let sampleOverhead = MemoryLayout<T>.size

        let (total, overflow) = capacity.multipliedReportingOverflow(by: sampleOverhead)

        return overflow ? Int.max : total
    }

    /// Creates a new profiler
    /// - Parameters:
    ///   - thread: The pthread to profile
    ///   - interval: The time interval between samples (default: 10ms)
    ///   - retentionSeconds: How many seconds of samples to retain in the ring buffer (default: 30)
    public convenience init(
        thread: pthread_t,
        interval: TimeInterval = 0.01,
        retentionSeconds: Int = 30
    ) {
        self.init(
            machThread: pthread_mach_thread_np(thread),
            interval: interval,
            retentionSeconds: retentionSeconds
        )
    }

    /// Creates a new profiler
    /// - Parameters:
    ///   - machThread: The mach thread to profile
    ///   - interval: The time interval between samples (default: 10ms)
    ///   - retentionSeconds: How many seconds of samples to retain in the ring buffer (default: 30)
    public init(
        machThread: thread_t,
        interval: TimeInterval = 0.01,
        retentionSeconds: Int = 30
    ) {
        self.machThread = machThread

        let clampedInterval = max(0.001, interval)
        self.intervalNs = UInt64(clampedInterval * 1_000_000_000)
        self.samplingQueue = DispatchQueue(label: "com.kscrash.profiler.sampling", qos: .userInteractive)

        let computed = Int((Double(retentionSeconds) / clampedInterval).rounded(.toNearestOrAwayFromZero))
        self.capacity = max(1, computed)

        // Pre-allocate ring buffer
        self.samples = ContiguousArray(repeating: T.make(), count: self.capacity)

        let bytes = Self.storageSize(interval: interval, retentionSeconds: retentionSeconds)
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
        let timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
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
    public func endProfile(id: ProfileID) -> Profile? {
        let endTimestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        return lock.withLock {
            guard let activeProfile = activeSessions.removeValue(forKey: id) else {
                return nil
            }

            let matchingSamples = samplesInRangeLocked(
                from: activeProfile.startTimestampNs,
                to: endTimestamp
            )

            if activeSessions.isEmpty {
                stopLocked()
            }

            return Profile(
                id: id,
                name: activeProfile.name,
                thread: machThread,
                startTime: activeProfile.startTime,
                startTimestampNs: activeProfile.startTimestampNs,
                endTimestampNs: endTimestamp,
                expectedSampleIntervalNs: intervalNs,
                samples: matchingSamples
            )
        }
    }

    deinit {
        lock.withLock {
            stopLocked()
        }
    }
}

extension Profiler where T == Sample512 {
    /// A shared profiler instance that samples the main thread.
    ///
    /// Default sampling interval (10ms) and retention (30s).
    public static let main: Profiler<Sample512> = Profiler<Sample512>(machThread: thread_t(ksthread_main()))
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

extension Profiler {
    /// Starts the sampling timer.
    ///
    /// Resets ring buffer state and starts a repeating timer that calls `captureSample()`.
    ///
    /// - Important: Must be called while holding `lock`.
    func startLocked() {
        // Reset ring buffer state
        writeIndex = 0
        count = 0

        let timer = DispatchSource.makeTimerSource(queue: samplingQueue)
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
    /// ## Implementation Notes
    ///
    /// The backtrace capture happens while holding the lock. This design choice trades
    /// some lock contention for simpler, more predictable code:
    ///
    /// - **Simplicity**: Capturing directly into the ring buffer slot eliminates the need
    ///   to copy sample data, reducing overhead and complexity.
    /// - **Correctness**: Holding the lock ensures the ring buffer slot remains valid
    ///   throughout the capture operation, avoiding race conditions with concurrent
    ///   `endProfile()` calls that read from the buffer.
    ///
    /// The lock is held for approximately 100-300µs per sample (depending on stack depth),
    /// which is acceptable for the typical 1-10ms sampling intervals.
    func captureSample() {
        lock.withLock {
            guard !activeSessions.isEmpty else { return }

            let slot = writeIndex

            // Capture directly into the ring buffer slot to avoid struct copy overhead
            samples[slot].metadata.timestampBeginNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            samples[slot].capture(
                thread: machThread,
                using: captureBacktrace(machThread:addresses:count:isTruncated:)
            )
            samples[slot].metadata.timestampEndNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

            // Advance ring buffer position
            writeIndex = (writeIndex + 1) % capacity
            if count < capacity {
                count += 1
            }
        }
    }

    /// Retrieves samples from the ring buffer that overlap the given time range.
    ///
    /// Iterates through valid samples in the ring buffer (from oldest to newest) and
    /// returns those whose capture time window overlaps with `[startNs, endNs]`.
    ///
    /// A sample overlaps the range if:
    /// - The sample's end time is at or after the range start, AND
    /// - The sample's begin time is at or before the range end
    ///
    /// - Parameters:
    ///   - startNs: Start of the time range (monotonic nanoseconds from `CLOCK_UPTIME_RAW`).
    ///   - endNs: End of the time range (monotonic nanoseconds from `CLOCK_UPTIME_RAW`).
    /// - Returns: Array of samples that overlap the time range, in chronological order.
    ///
    /// - Important: Must be called while holding `lock`.
    func samplesInRangeLocked(from startNs: UInt64, to endNs: UInt64) -> [T] {
        guard count > 0 else { return [] }

        var result: [T] = []

        // Calculate the oldest sample's position in the ring buffer
        let oldest = (writeIndex - count + capacity) % capacity

        // Iterate from oldest to newest
        for i in 0..<count {
            let slot = (oldest + i) % capacity
            let sample = samples[slot]

            // Check for time range overlap and valid capture
            guard
                sample.metadata.timestampEndNs >= startNs
                    && sample.metadata.timestampBeginNs <= endNs
                    && sample.addressCount > 0
            else { continue }

            result.append(sample)
        }

        return result
    }
}
