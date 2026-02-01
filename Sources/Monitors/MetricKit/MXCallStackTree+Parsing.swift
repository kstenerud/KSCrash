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
import Report

#if os(iOS) || os(macOS)
    import MetricKit

    // MARK: - MXCallStackTree JSON Model

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
            let subFrames: [Frame]?
        }
    }

    // MARK: - Output

    struct CallStackData {
        let threads: [BasicCrashReport.Thread]
        let crashedThreadIndex: Int
        let binaryImages: [BinaryImage]
    }

    // MARK: - Parsing

    @available(iOS 14.0, macOS 12.0, *)
    extension MXCallStackTree {

        func extractCallStackData() -> CallStackData {
            let jsonData = jsonRepresentation()
            guard let tree = try? JSONDecoder().decode(CallStackTreeRepresentation.self, from: jsonData) else {
                return CallStackData(threads: [], crashedThreadIndex: 0, binaryImages: [])
            }

            var threads: [BasicCrashReport.Thread] = []
            var crashedIndex = 0
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
    }

    // MARK: - Frame Flattening

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

#endif
