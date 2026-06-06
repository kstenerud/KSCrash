//
//  MXCallStackTree+Parsing.swift
//
//  Created by Alexander Cohen on 2026-01-31.
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
import os.log

// MARK: - Output

struct CallStackData {
    let threads: [BasicCrashReport.Thread]
    /// Index of the crashed thread, or nil if no thread was attributed.
    let crashedThreadIndex: Int?
    let binaryImages: [BinaryImage]
}

/// Per-thread weighted samples extracted from a sampled call-stack tree (e.g. a hang),
/// shaped for a profile report: a shared frame table plus per-thread samples that carry a
/// multiplicity `count` instead of timing.
struct ProfileData {
    let frames: [StackFrame]
    let threads: [ProfileThread]
}

// MARK: - MXCallStackTree JSON Model

// Decodable mirror of MXCallStackTree's JSON representation. Kept outside the MetricKit
// availability guard so the pure tree-walking logic below can be unit-tested from JSON
// without MetricKit.
struct CallStackTreeRepresentation: Decodable {
    let callStacks: [CallStack]

    struct CallStack: Decodable {
        let threadAttributed: Bool?
        let callStackRootFrames: [Frame]?
    }

    struct Frame: Decodable {
        let address: UInt64
        let binaryUUID: String?
        let binaryName: String?
        let offsetIntoBinaryTextSegment: UInt64?
        // Number of samples that passed through this frame. A crash tree omits it (one
        // snapshot); a hang tree sets it on every node.
        let sampleCount: Int?
        let subFrames: [Frame]?

        init(
            address: UInt64,
            binaryUUID: String? = nil,
            binaryName: String? = nil,
            offsetIntoBinaryTextSegment: UInt64? = nil,
            sampleCount: Int? = nil,
            subFrames: [Frame]? = nil
        ) {
            self.address = address
            self.binaryUUID = binaryUUID
            self.binaryName = binaryName
            self.offsetIntoBinaryTextSegment = offsetIntoBinaryTextSegment
            self.sampleCount = sampleCount
            self.subFrames = subFrames
        }
    }
}

// MARK: - Crash extraction (single snapshot -> linear backtrace)

// A crash diagnostic's per-thread tree is effectively linear, so flattening it depth-first
// yields the correct backtrace. Do NOT use this for a hang tree, which branches: see
// `buildProfileData`.
func buildCallStackData(from tree: CallStackTreeRepresentation) -> CallStackData {
    var threads: [BasicCrashReport.Thread] = []
    var crashedIndex: Int?
    var seenUUIDs = Set<String>()
    var images: [BinaryImage] = []

    for (index, callStack) in tree.callStacks.enumerated() {
        let isAttributed = callStack.threadAttributed ?? false
        if isAttributed {
            crashedIndex = index
        }

        let flatFrames = flattenFrames(callStack.callStackRootFrames ?? [])

        let stackFrames = flatFrames.map { frame in
            let objectAddr = frame.offsetIntoBinaryTextSegment.map { frame.address - $0 }
            return StackFrame(
                instructionAddr: frame.address,
                objectAddr: objectAddr,
                objectName: frame.binaryName,
                objectUUID: frame.binaryUUID
            )
        }

        // Collect unique binary images
        for frame in flatFrames {
            guard let binaryUUID = frame.binaryUUID,
                !seenUUIDs.contains(binaryUUID)
            else {
                continue
            }
            seenUUIDs.insert(binaryUUID)

            images.append(
                BinaryImage(
                    imageAddr: frame.address - (frame.offsetIntoBinaryTextSegment ?? 0),
                    name: frame.binaryName ?? "unknown",
                    uuid: binaryUUID
                ))
        }

        let backtrace = Backtrace(contents: stackFrames, skipped: 0)
        let thread = BasicCrashReport.Thread(
            backtrace: backtrace,
            crashed: isAttributed,
            currentThread: isAttributed,
            index: index
        )
        threads.append(thread)
    }

    return CallStackData(
        threads: threads,
        crashedThreadIndex: crashedIndex,
        binaryImages: images
    )
}

func flattenFrames(_ frames: [CallStackTreeRepresentation.Frame]) -> [CallStackTreeRepresentation.Frame] {
    var result: [CallStackTreeRepresentation.Frame] = []
    for frame in frames {
        result.append(frame)
        if let subFrames = frame.subFrames {
            result.append(contentsOf: flattenFrames(subFrames))
        }
    }
    return result
}

// MARK: - Profile extraction (sampled tree -> weighted per-thread samples)

// A hang tree is a sample-merged trie: each node's `sampleCount` equals the sum of its
// children's, so the per-node "self" samples live at the leaves and each root->leaf path is
// one observed stack. We emit one weighted `ProfileSample` per path (count = the path's self
// samples), deduping frames by address into one shared table. Frames are stored deepest-first
// to match KSCrash's `Sample.addresses` convention.
//
// `primaryThreadIndex` selects the thread of interest. The caller passes index 0 for a
// "Main Runloop Hang" (the main thread); when nil we fall back to the attributed thread, then
// to 0 — `threadAttributed` alone is unreliable (often unset, or a low-sample worker).
func buildProfileData(from tree: CallStackTreeRepresentation, primaryThreadIndex: Int? = nil) -> ProfileData {
    var frameIndexByAddr: [UInt64: Int] = [:]
    var frames: [StackFrame] = []

    func indexFor(_ f: CallStackTreeRepresentation.Frame) -> Int {
        if let i = frameIndexByAddr[f.address] { return i }
        let objectAddr = f.offsetIntoBinaryTextSegment.map { f.address - $0 }
        let i = frames.count
        frames.append(
            StackFrame(
                instructionAddr: f.address,
                objectAddr: objectAddr,
                objectName: f.binaryName,
                objectUUID: f.binaryUUID
            ))
        frameIndexByAddr[f.address] = i
        return i
    }

    let attributed = tree.callStacks.firstIndex { $0.threadAttributed ?? false }
    let primary = primaryThreadIndex ?? attributed ?? 0

    var threads: [ProfileThread] = []
    for (index, callStack) in tree.callStacks.enumerated() {
        var samples: [ProfileSample] = []
        var path: [Int] = []

        func walk(_ f: CallStackTreeRepresentation.Frame) {
            path.append(indexFor(f))
            let subs = f.subFrames ?? []
            let childSum = subs.reduce(0) { $0 + ($1.sampleCount ?? 0) }
            let selfCount = (f.sampleCount ?? 0) - childSum
            if selfCount > 0 {
                // path is root->leaf; reverse to deepest-first (this frame first, root last).
                samples.append(ProfileSample(count: selfCount, frames: Array(path.reversed())))
            }
            for s in subs { walk(s) }
            path.removeLast()
        }

        for rootFrame in callStack.callStackRootFrames ?? [] { walk(rootFrame) }

        threads.append(
            ProfileThread(
                index: index,
                primary: index == primary,
                name: nil,
                samples: samples
            ))
    }

    return ProfileData(frames: frames, threads: threads)
}

#if KSCRASH_HAS_METRICKIT
    import MetricKit

    // MARK: - MXCallStackTree Parsing

    @available(iOS 14.0, macOS 12.0, *)
    extension MXCallStackTree {

        func extractCallStackData() -> CallStackData {
            guard let tree = decodeTree() else {
                return CallStackData(threads: [], crashedThreadIndex: nil, binaryImages: [])
            }
            return buildCallStackData(from: tree)
        }

        func extractProfileData(primaryThreadIndex: Int? = nil) -> ProfileData {
            guard let tree = decodeTree() else {
                return ProfileData(frames: [], threads: [])
            }
            return buildProfileData(from: tree, primaryThreadIndex: primaryThreadIndex)
        }

        private func decodeTree() -> CallStackTreeRepresentation? {
            let jsonData = jsonRepresentation()
            guard let tree = try? JSONDecoder().decode(CallStackTreeRepresentation.self, from: jsonData)
            else {
                os_log(
                    .error, log: metricKitLog,
                    "[MONITORS] Failed to decode MXCallStackTree JSON representation")
                return nil
            }
            return tree
        }
    }

#endif
