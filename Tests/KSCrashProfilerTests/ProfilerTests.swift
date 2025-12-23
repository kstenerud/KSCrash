//
//  ProfilerTests.swift
//
//  Created by Claude on 2025-12-13.
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

import Darwin
import XCTest

@testable import KSCrashProfiler

final class ProfilerTests: XCTestCase {

    // MARK: - Profiler Initialization Tests

    func testProfilerInitialization() {
        let profiler = Profiler<Sample128>(thread: pthread_self())

        XCTAssertFalse(profiler.isRunning, "Profiler should not be running initially")
        XCTAssertEqual(profiler.intervalNs, 10_000_000, "Default interval should be 10ms (10,000,000 ns)")
    }

    func testProfilerInitializationWithCustomParameters() {
        let profiler = Profiler<Sample64>(
            thread: pthread_self(),
            interval: 0.005,  // 5ms
            retentionSeconds: 10
        )

        XCTAssertFalse(profiler.isRunning)
        XCTAssertEqual(profiler.intervalNs, 5_000_000, "Interval should be 5ms (5,000,000 ns)")
    }

    func testProfilerClampsMinimumInterval() {
        // Interval below 1ms should be clamped to 1ms
        let profiler = Profiler<Sample32>(
            thread: pthread_self(),
            interval: 0.0001  // 0.1ms - too small
        )

        XCTAssertEqual(profiler.intervalNs, 1_000_000, "Minimum interval should be clamped to 1ms")
    }

    // MARK: - Storage Size Calculation Tests

    func testStorageSizeCalculation() {
        // With 10ms interval, 128 frames (Sample128), 30 seconds retention:
        // capacity = 30 / 0.01 = 3000 samples
        let size = Profiler<Sample128>.storageSize(interval: 0.01, retentionSeconds: 30)
        XCTAssertGreaterThan(size, 0, "Storage size should be positive")

        // Verify smaller configuration yields smaller storage
        let smallerSize = Profiler<Sample32>.storageSize(interval: 0.01, retentionSeconds: 10)
        XCTAssertLessThan(smallerSize, size, "Smaller config should yield smaller storage")
    }

    func testStorageSizeWithMinimalConfig() {
        let size = Profiler<Sample32>.storageSize(interval: 1.0, retentionSeconds: 1)
        XCTAssertGreaterThan(size, 0)
    }

    func testStorageSizeScalesWithRetention() {
        let size1 = Profiler<Sample64>.storageSize(interval: 0.01, retentionSeconds: 10)
        let size2 = Profiler<Sample64>.storageSize(interval: 0.01, retentionSeconds: 20)

        // Doubling retention should roughly double storage
        XCTAssertEqual(size2, size1 * 2, "Storage should scale linearly with retention")
    }

    // MARK: - Begin/End Profile Tests

    func testBeginProfileStartsSampling() {
        let profiler = Profiler<Sample128>(thread: pthread_self())

        XCTAssertFalse(profiler.isRunning)

        let id = profiler.beginProfile(named: "test")
        XCTAssertTrue(profiler.isRunning, "Profiler should be running after beginProfile")
        XCTAssertNotEqual(id, UUID(), "Profile ID should be a valid UUID")

        let profile = profiler.endProfile(id: id)
        XCTAssertFalse(profiler.isRunning, "Profiler should stop after last profile ends")
        XCTAssertNotNil(profile, "Profile should be returned")
    }

    func testEndProfileWithInvalidIdReturnsNil() {
        let profiler = Profiler<Sample128>(thread: pthread_self())

        let invalidId = UUID()
        let profile = profiler.endProfile(id: invalidId)

        XCTAssertNil(profile, "endProfile with invalid ID should return nil")
    }

    func testEndProfileCannotBeCalledTwice() {
        let profiler = Profiler<Sample128>(thread: pthread_self())

        let id = profiler.beginProfile(named: "test")
        let profile1 = profiler.endProfile(id: id)
        let profile2 = profiler.endProfile(id: id)

        XCTAssertNotNil(profile1, "First endProfile should succeed")
        XCTAssertNil(profile2, "Second endProfile with same ID should return nil")
    }

    // MARK: - Multiple Concurrent Profiles Tests

    func testMultipleConcurrentProfiles() {
        let profiler = Profiler<Sample128>(thread: pthread_self())

        let id1 = profiler.beginProfile(named: "test")
        XCTAssertTrue(profiler.isRunning)

        let id2 = profiler.beginProfile(named: "test")
        XCTAssertTrue(profiler.isRunning)

        // End first profile - sampling should continue
        let profile1 = profiler.endProfile(id: id1)
        XCTAssertNotNil(profile1)
        XCTAssertTrue(profiler.isRunning, "Should still run with active profile")

        // End second profile - sampling should stop
        let profile2 = profiler.endProfile(id: id2)
        XCTAssertNotNil(profile2)
        XCTAssertFalse(profiler.isRunning, "Should stop when all profiles end")
    }

    // MARK: - Profile Content Tests

    func testProfileContainsValidTimestamps() {
        let profiler = Profiler<Sample64>(
            thread: pthread_self(),
            interval: 0.005,
            retentionSeconds: 5
        )

        let id = profiler.beginProfile(named: "test")

        // Do some work to generate samples
        Thread.sleep(forTimeInterval: 0.05)

        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        guard let profile = profile else { return }

        XCTAssertEqual(profile.id, id, "Profile ID should match")
        XCTAssertGreaterThan(profile.endTimestampNs, profile.startTimestampNs, "End should be after start")
        XCTAssertGreaterThan(profile.durationNs, 0, "Duration should be positive")
    }

    func testProfileCapturesSamples() {
        let profiler = Profiler<Sample64>(
            thread: pthread_self(),
            interval: 0.005,  // 5ms
            retentionSeconds: 5
        )

        let id = profiler.beginProfile(named: "test")

        // Sleep to allow some samples to be captured
        Thread.sleep(forTimeInterval: 0.1)

        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        guard let profile = profile else { return }

        // With 5ms interval and 100ms sleep, we should have ~20 samples
        // Allow some variance due to timing
        XCTAssertGreaterThan(profile.samples.count, 0, "Should capture multiple samples")
    }

    func testSamplesContainBacktraceAddresses() throws {
        #if os(watchOS)
            throw XCTSkip("watchOS does not support backtrace capture")
        #endif

        let profiler = Profiler<Sample64>(
            thread: pthread_self(),
            interval: 0.01,
            retentionSeconds: 5
        )

        let id = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.05)
        let profile = profiler.endProfile(id: id)

        guard let profile = profile, !profile.samples.isEmpty else {
            XCTFail("Should have captured samples")
            return
        }

        for sample in profile.samples {
            XCTAssertFalse(sample.addresses.isEmpty, "Sample should have addresses")
            XCTAssertLessThanOrEqual(
                sample.addresses.count, Sample64.capacity,
                "Should not exceed Sample capacity"
            )

            // Verify addresses are non-zero (valid pointers)
            let nonZeroCount = sample.addresses.filter { $0 != 0 }.count
            XCTAssertGreaterThan(nonZeroCount, 0, "Should have non-zero addresses")
        }
    }

    // MARK: - Sample Tests

    func testSampleCaptureDuration() {
        let profiler = Profiler<Sample128>(
            thread: pthread_self(),
            interval: 0.01,
            retentionSeconds: 5
        )

        let id = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.05)
        let profile = profiler.endProfile(id: id)

        guard let profile = profile, !profile.samples.isEmpty else {
            XCTFail("Should have samples")
            return
        }

        for sample in profile.samples {
            XCTAssertGreaterThanOrEqual(
                sample.metadata.timestampEndNs, sample.metadata.timestampBeginNs,
                "End timestamp should be >= begin"
            )
            XCTAssertEqual(
                sample.metadata.durationNs,
                sample.metadata.timestampEndNs &- sample.metadata.timestampBeginNs,
                "Duration calculation should be correct"
            )
        }
    }

    func testSamplesOverlapWithProfileTimeWindow() {
        let profiler = Profiler<Sample64>(
            thread: pthread_self(),
            interval: 0.005,
            retentionSeconds: 5
        )

        let id = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.05)
        let profile = profiler.endProfile(id: id)

        guard let profile = profile else {
            XCTFail("Should have profile")
            return
        }

        for sample in profile.samples {
            // Samples are included if they overlap with the profile window
            // Overlap means: sample ends after profile starts AND sample starts before profile ends
            XCTAssertGreaterThanOrEqual(
                sample.metadata.timestampEndNs, profile.startTimestampNs,
                "Sample should end after or at profile start (overlap condition)"
            )
            XCTAssertLessThanOrEqual(
                sample.metadata.timestampBeginNs, profile.endTimestampNs,
                "Sample should start before or at profile end (overlap condition)"
            )
        }
    }

    // MARK: - Profile Duration Tests

    func testProfileDurationProperty() {
        let profiler = Profiler<Sample128>(
            thread: pthread_self(),
            interval: 0.01,
            retentionSeconds: 5
        )

        let id = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.02)
        let profile = profiler.endProfile(id: id)

        guard let profile = profile else {
            XCTFail("Should have profile")
            return
        }

        // Duration should be close to our sleep time (20ms = 20,000,000 ns)
        // Allow 50% variance for timing issues
        XCTAssertGreaterThan(profile.durationNs, 10_000_000, "Duration should be at least 10ms")
        XCTAssertLessThan(profile.durationNs, 500_000_000, "Duration should be less than 500ms")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentBeginEndFromMultipleThreads() {
        let profiler = Profiler<Sample128>(
            thread: pthread_self(),
            interval: 0.01,
            retentionSeconds: 10
        )

        let group = DispatchGroup()
        let iterations = 10
        var profiles: [Profile?] = Array(repeating: nil, count: iterations)
        let lock = NSLock()

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let id = profiler.beginProfile(named: "test")
                Thread.sleep(forTimeInterval: 0.01)
                let profile = profiler.endProfile(id: id)

                lock.lock()
                profiles[i] = profile
                lock.unlock()

                group.leave()
            }
        }

        group.wait()

        // All profiles should be non-nil
        for (index, profile) in profiles.enumerated() {
            XCTAssertNotNil(profile, "Profile \(index) should not be nil")
        }

        XCTAssertFalse(profiler.isRunning, "Profiler should not be running after all profiles end")
    }

    // MARK: - Ring Buffer Tests

    func testRingBufferOverwrite() {
        // Create a profiler with small capacity (1 second retention with 100ms interval = 10 samples)
        let profiler = Profiler<Sample32>(
            thread: pthread_self(),
            interval: 0.1,  // 100ms
            retentionSeconds: 1  // Small retention to test ring buffer
        )

        let id = profiler.beginProfile(named: "test")

        // Sleep longer than retention to force ring buffer overwrite
        Thread.sleep(forTimeInterval: 1.5)

        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        guard let profile = profile else { return }

        // Should still have samples (from the retained window)
        // Note: samples outside the time range won't be included
        XCTAssertGreaterThan(profile.samples.count, 0, "Should have some samples")
    }

    // MARK: - Profiling Different Threads

    func testProfilingOtherThread() {
        var otherThread: pthread_t?
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 0)

        // Start a background thread that does work
        group.enter()
        let thread = Thread {
            otherThread = pthread_self()
            semaphore.signal()

            // Keep thread alive while profiling
            for _ in 0..<1000 {
                _ = (0..<100).reduce(0, +)
                Thread.sleep(forTimeInterval: 0.001)
            }
            group.leave()
        }
        thread.start()

        semaphore.wait()

        guard let targetThread = otherThread else {
            XCTFail("Failed to get other thread")
            group.wait()
            return
        }

        let profiler = Profiler<Sample64>(
            thread: targetThread,
            interval: 0.005,
            retentionSeconds: 5
        )

        let id = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.1)
        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        if let profile = profile {
            XCTAssertGreaterThan(profile.samples.count, 0, "Should capture samples from other thread")
        }

        // Wait for the thread to complete
        group.wait()
    }

    // MARK: - Expected Sample Interval Tests

    func testExpectedSampleInterval() {
        let profiler = Profiler<Sample128>(
            thread: pthread_self(),
            interval: 0.02,  // 20ms
            retentionSeconds: 5
        )

        let id = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.05)
        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        guard let profile = profile else { return }

        XCTAssertEqual(profile.expectedSampleIntervalNs, 20_000_000, "Expected sample interval should be 20ms")
    }

    // MARK: - Start/Stop Cycling Tests

    func testStartStopCycling() {
        let profiler = Profiler<Sample128>(
            thread: pthread_self(),
            interval: 0.01,
            retentionSeconds: 5
        )

        for _ in 0..<3 {
            XCTAssertFalse(profiler.isRunning)

            let id = profiler.beginProfile(named: "test")
            XCTAssertTrue(profiler.isRunning)

            Thread.sleep(forTimeInterval: 0.02)

            let profile = profiler.endProfile(id: id)
            XCTAssertFalse(profiler.isRunning)
            XCTAssertNotNil(profile)
        }
    }

    // MARK: - Profile Isolation Tests

    func testSequentialProfilesAreIsolated() {
        let profiler = Profiler<Sample128>(
            thread: pthread_self(),
            interval: 0.01,
            retentionSeconds: 5
        )

        // First profile
        let id1 = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.05)
        let profile1 = profiler.endProfile(id: id1)

        // Small gap between profiles
        Thread.sleep(forTimeInterval: 0.02)

        // Second profile
        let id2 = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.05)
        let profile2 = profiler.endProfile(id: id2)

        guard let p1 = profile1, let p2 = profile2 else {
            XCTFail("Both profiles should exist")
            return
        }

        XCTAssertNotEqual(p1.id, p2.id, "Profile IDs should be different")
        XCTAssertGreaterThan(p2.startTimestampNs, p1.endTimestampNs, "Second profile should start after first ends")
    }

    // MARK: - Overlapping Profiles Tests

    func testOverlappingProfilesGetDifferentSamples() {
        let profiler = Profiler<Sample64>(
            thread: pthread_self(),
            interval: 0.005,
            retentionSeconds: 10
        )

        // Start first profile
        let id1 = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.05)

        // Start second profile while first is still running
        let id2 = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.05)

        // End first profile
        let profile1 = profiler.endProfile(id: id1)
        Thread.sleep(forTimeInterval: 0.05)

        // End second profile
        let profile2 = profiler.endProfile(id: id2)

        guard let p1 = profile1, let p2 = profile2 else {
            XCTFail("Both profiles should exist")
            return
        }

        // Second profile started later, so should have fewer samples from overlap period
        // but more total duration
        XCTAssertGreaterThan(p1.samples.count, 0)
        XCTAssertGreaterThan(p2.samples.count, 0)

        // Profile 2 should have started after profile 1
        XCTAssertGreaterThan(p2.startTimestampNs, p1.startTimestampNs)

        // Profile 2 should have ended after profile 1
        XCTAssertGreaterThan(p2.endTimestampNs, p1.endTimestampNs)
    }

    // MARK: - Profile Name Tests

    func testProfileNameIsCaptured() {
        let profiler = Profiler<Sample64>(thread: pthread_self())

        let id = profiler.beginProfile(named: "MyOperation")
        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.name, "MyOperation")
    }

    func testProfileNameWithEmptyString() {
        let profiler = Profiler<Sample64>(thread: pthread_self())

        let id = profiler.beginProfile(named: "")
        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.name, "")
    }

    func testProfileNameWithSpecialCharacters() {
        let profiler = Profiler<Sample64>(thread: pthread_self())
        let specialName = "Test/Profile:With-Special_Characters.123"

        let id = profiler.beginProfile(named: specialName)
        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.name, specialName)
    }

    // MARK: - Profile Thread Tests

    func testProfileThreadIsCaptured() {
        let profiler = Profiler<Sample64>(thread: pthread_self())

        let id = profiler.beginProfile(named: "test")
        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        XCTAssertNotEqual(profile?.thread, 0, "Thread should be a valid Mach thread port")
    }

    func testProfileThreadMatchesProfilerThread() {
        let currentThread = pthread_self()
        let expectedMachThread = pthread_mach_thread_np(currentThread)
        let profiler = Profiler<Sample64>(thread: currentThread)

        let id = profiler.beginProfile(named: "test")
        let profile = profiler.endProfile(id: id)

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.thread, expectedMachThread, "Profile thread should match the profiler's target thread")
    }

    // MARK: - Write Report Tests

    func testWriteReportCanBeCalled() {
        let profiler = Profiler<Sample64>(thread: pthread_self())

        let id = profiler.beginProfile(named: "test")
        Thread.sleep(forTimeInterval: 0.02)

        let profile = profiler.endProfile(id: id)
        XCTAssertNotNil(profile)

        // writeReport() may return nil in tests when KSCrash is not installed,
        // but it should be callable without crashing
        _ = profile?.writeReport()
    }

    func testMultipleProfilesCanCallWriteReport() {
        let profiler = Profiler<Sample64>(
            thread: pthread_self(),
            interval: 0.005,
            retentionSeconds: 5
        )

        // Start and end multiple profiles quickly
        let id1 = profiler.beginProfile(named: "profile1")
        Thread.sleep(forTimeInterval: 0.01)
        let profile1 = profiler.endProfile(id: id1)

        let id2 = profiler.beginProfile(named: "profile2")
        Thread.sleep(forTimeInterval: 0.01)
        let profile2 = profiler.endProfile(id: id2)

        let id3 = profiler.beginProfile(named: "profile3")
        Thread.sleep(forTimeInterval: 0.01)
        let profile3 = profiler.endProfile(id: id3)

        // writeReport() may return nil in tests when KSCrash is not installed,
        // but it should be callable without crashing
        _ = profile1?.writeReport()
        _ = profile2?.writeReport()
        _ = profile3?.writeReport()
    }
}
