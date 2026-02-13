//
//  MetricKitRunIdHandler.swift
//
//  Created by Alexander Cohen on 2026-02-03.
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

#if SWIFT_PACKAGE
    import KSCrashRecording
    import Report
#endif

/// Encodes a run ID into a parked thread's call stack using KSCrashThreadcrumb,
/// then writes a sidecar file mapping the stack hash to the run ID.
@available(iOS 14.0, macOS 12.0, *)
public final class MetricKitRunIdHandler {

    /// Expected number of data frames (UUID without hyphens = 32 hex characters).
    static let expectedDataFrameCount = 32

    /// Total frames in a parked threadcrumb stack (39 frames).
    /// Stack is ordered top-to-bottom (index 0 = most recent frame).
    /// Layout:
    ///   0-3:   overhead (semaphore_wait, dispatch, __kscrash_threadcrumb_end__)
    ///   4-35:  data frames (32 characters, in reverse order - last char at 4, first at 35)
    ///   36-38: overhead (__kscrash_threadcrumb_start__, pthread)
    static let expectedTotalFrameCount = 39

    /// Index where data frames start in the parked stack.
    static let dataStartIndex = 4

    private let threadcrumb = KSCrashThreadcrumb(identifier: "com.kscrash.run_id")

    /// Callback type for obtaining sidecar file URLs.
    public typealias SidecarPathProvider = (_ name: String, _ extension: String) -> URL?

    public init() {}

    /// Encode a run ID into the thread's call stack and write a sidecar file.
    ///
    /// - Parameters:
    ///   - runId: The run ID (UUID string, hyphens will be stripped)
    ///   - pathProvider: Callback to get the sidecar file path for a given name and extension
    /// - Returns: true if successful
    @discardableResult
    public func encode(runId: String, pathProvider: SidecarPathProvider) -> Bool {
        // Strip hyphens for encoding (expectedDataFrameCount hex chars)
        let stripped = runId.replacingOccurrences(of: "-", with: "")

        guard stripped.count == Self.expectedDataFrameCount else {
            return false
        }

        // Encode into threadcrumb stack - returns just the data frames
        let addresses = threadcrumb.log(stripped)

        guard addresses.count == Self.expectedDataFrameCount else {
            return false
        }

        // Compute hash from addresses
        let hash = Self.computeHash(from: addresses)

        // Get sidecar URL from callback
        let name = String(format: "%016llx", hash)
        guard let url = pathProvider(name, "stacksym") else {
            return false
        }

        do {
            try runId.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Decode a run ID from MetricKit call stack data.
    ///
    /// Looks for a thread with exactly 39 frames and extracts data from indices 4-35.
    ///
    /// - Parameters:
    ///   - callStackData: Parsed call stack data from MXCallStackTree
    ///   - pathProvider: Callback to get the sidecar file path for a given name and extension
    /// - Returns: The run ID if found
    func decode(from callStackData: CallStackData, pathProvider: SidecarPathProvider) -> String? {
        for thread in callStackData.threads {
            guard let backtrace = thread.backtrace else { continue }
            let frames = backtrace.contents

            // Must have exactly 39 frames for a threadcrumb stack
            guard frames.count == Self.expectedTotalFrameCount else { continue }

            // Extract data frames at indices 4-35 (32 frames)
            let dataFrames = Array(
                frames[Self.dataStartIndex..<(Self.dataStartIndex + Self.expectedDataFrameCount)])

            // Convert to addresses for hashing
            let addresses = dataFrames.map { NSNumber(value: $0.instructionAddr) }
            let hash = Self.computeHash(from: addresses)

            // Look up sidecar
            let name = String(format: "%016llx", hash)
            guard let url = pathProvider(name, "stacksym") else {
                continue
            }

            guard let runId = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }

            // remove the sidecar
            try? FileManager.default.removeItem(at: url)

            // trim and return
            return runId.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }

        return nil
    }

    /// Compute hash from stack addresses (XOR with rotation).
    static func computeHash(from addresses: [NSNumber]) -> UInt64 {
        var hash: UInt64 = 0
        for (i, addr) in addresses.enumerated() {
            let val = addr.uint64Value
            let shift = UInt64((i % 63) + 1)
            let rotated = (val << shift) | (val >> (64 - shift))
            hash ^= rotated
        }
        return hash
    }
}
