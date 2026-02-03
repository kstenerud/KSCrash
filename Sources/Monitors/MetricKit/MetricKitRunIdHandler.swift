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
import Report

#if os(iOS) || os(macOS)

    #if SWIFT_PACKAGE
        import KSCrashRecording
    #endif

    /// Encodes a run ID into a parked thread's call stack using KSCrashThreadcrumb,
    /// then writes a sidecar file mapping the stack hash to the run ID.
    @available(iOS 14.0, macOS 12.0, *)
    public final class MetricKitRunIdHandler {

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
            // Strip hyphens for encoding (32 hex chars)
            let stripped = runId.replacingOccurrences(of: "-", with: "")

            // Encode into threadcrumb stack
            let addresses = threadcrumb.log(stripped)

            guard addresses.count == stripped.count else {
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
        /// - Parameters:
        ///   - callStackData: Parsed call stack data from MXCallStackTree
        ///   - pathProvider: Callback to get the sidecar file path for a given name and extension
        /// - Returns: The run ID if found
        func decode(from callStackData: CallStackData, pathProvider: SidecarPathProvider) -> String? {
            for thread in callStackData.threads {
                guard let backtrace = thread.backtrace else { continue }
                let frames = backtrace.contents
                guard let crumbFrames = extractThreadcrumbFrames(from: frames),
                    crumbFrames.count >= 32
                else {
                    continue
                }

                // Use the first 32 frames (UUID without hyphens)
                let addresses = crumbFrames.prefix(32).map { NSNumber(value: $0.instructionAddr) }
                let hash = Self.computeHash(from: Array(addresses))

                // Look up sidecar
                let name = String(format: "%016llx", hash)
                guard let url = pathProvider(name, "stacksym") else {
                    continue
                }

                if let runId = try? String(contentsOf: url, encoding: .utf8) {
                    return runId.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                }
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

        // MARK: - Private

        /// Find the largest contiguous group of frames from the same binary.
        private func extractThreadcrumbFrames(from frames: [StackFrame]) -> [StackFrame]? {
            var currentUUID: String?
            var currentGroup: [StackFrame] = []
            var bestGroup: [StackFrame] = []

            for frame in frames {
                if frame.objectUUID == currentUUID {
                    currentGroup.append(frame)
                } else {
                    if currentGroup.count > bestGroup.count {
                        bestGroup = currentGroup
                    }
                    currentUUID = frame.objectUUID
                    currentGroup = [frame]
                }
            }
            if currentGroup.count > bestGroup.count {
                bestGroup = currentGroup
            }

            return bestGroup.isEmpty ? nil : bestGroup
        }
    }

#endif
