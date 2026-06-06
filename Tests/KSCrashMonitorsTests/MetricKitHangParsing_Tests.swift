//
//  MetricKitHangParsing_Tests.swift
//
//  Created by Alexander Cohen on 2026-06-06.
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

import KSCrashReportModel
import XCTest

@testable import KSCrashMonitors

// These exercise the pure trie -> weighted-sample conversion, which is independent of
// MetricKit, so they run on every platform (no KSCRASH_HAS_METRICKIT guard).
final class MetricKitHangParsingTests: XCTestCase {

    // A two-thread sampled trie. Thread 0 has two branches summing to its root; thread 1
    // reuses thread 0's addresses (A/B/D) to exercise cross-thread frame dedup, plus a new
    // address F. Frame E omits binaryName/binaryUUID to exercise unmapped-frame tolerance.
    //
    // Addresses: A=0x1000 B=0x2000 D=0x3000 C=0x4000 E=0x5000 F=0x6000
    private let fixture = """
        {
          "callStacks": [
            {
              "threadAttributed": false,
              "callStackRootFrames": [
                {
                  "address": 4096, "offsetIntoBinaryTextSegment": 256,
                  "binaryName": "dyld", "binaryUUID": "AAAAAAAA-0000-0000-0000-000000000000",
                  "sampleCount": 5,
                  "subFrames": [
                    {
                      "address": 8192, "offsetIntoBinaryTextSegment": 512,
                      "binaryName": "App", "binaryUUID": "BBBBBBBB-0000-0000-0000-000000000000",
                      "sampleCount": 3,
                      "subFrames": [
                        {
                          "address": 12288, "offsetIntoBinaryTextSegment": 768,
                          "binaryName": "Foundation", "binaryUUID": "CCCCCCCC-0000-0000-0000-000000000000",
                          "sampleCount": 3
                        }
                      ]
                    },
                    {
                      "address": 16384, "offsetIntoBinaryTextSegment": 1024,
                      "binaryName": "App", "binaryUUID": "BBBBBBBB-0000-0000-0000-000000000000",
                      "sampleCount": 2,
                      "subFrames": [
                        { "address": 20480, "offsetIntoBinaryTextSegment": 1280, "sampleCount": 2 }
                      ]
                    }
                  ]
                }
              ]
            },
            {
              "threadAttributed": false,
              "callStackRootFrames": [
                {
                  "address": 4096, "offsetIntoBinaryTextSegment": 256,
                  "binaryName": "dyld", "binaryUUID": "AAAAAAAA-0000-0000-0000-000000000000",
                  "sampleCount": 4,
                  "subFrames": [
                    {
                      "address": 8192, "offsetIntoBinaryTextSegment": 512,
                      "binaryName": "App", "binaryUUID": "BBBBBBBB-0000-0000-0000-000000000000",
                      "sampleCount": 4,
                      "subFrames": [
                        { "address": 24576, "offsetIntoBinaryTextSegment": 1536,
                          "binaryName": "libswiftCore.dylib", "binaryUUID": "DDDDDDDD-0000-0000-0000-000000000000",
                          "sampleCount": 1 },
                        { "address": 12288, "offsetIntoBinaryTextSegment": 768,
                          "binaryName": "Foundation", "binaryUUID": "CCCCCCCC-0000-0000-0000-000000000000",
                          "sampleCount": 3 }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
        """

    private func decodeFixture() throws -> CallStackTreeRepresentation {
        let data = Data(fixture.utf8)
        return try JSONDecoder().decode(CallStackTreeRepresentation.self, from: data)
    }

    func testThreadCountAndPrimaryDefaultsToZero() throws {
        let tree = try decodeFixture()
        let profile = buildProfileData(from: tree)

        XCTAssertEqual(profile.threads.count, 2)
        XCTAssertEqual(profile.threads[0].index, 0)
        XCTAssertEqual(profile.threads[1].index, 1)
        // No thread is attributed, so primary falls back to index 0.
        XCTAssertTrue(profile.threads[0].primary)
        XCTAssertFalse(profile.threads[1].primary)
    }

    func testPrimaryThreadOverride() throws {
        let tree = try decodeFixture()
        let profile = buildProfileData(from: tree, primaryThreadIndex: 1)

        XCTAssertFalse(profile.threads[0].primary)
        XCTAssertTrue(profile.threads[1].primary)
    }

    func testSampleCountsSumToRoot() throws {
        let tree = try decodeFixture()
        let profile = buildProfileData(from: tree)

        // Thread 0: two leaves with counts 3 and 2, summing to the root's 5.
        let t0 = profile.threads[0].samples.map { $0.effectiveCount }.sorted()
        XCTAssertEqual(t0, [2, 3])
        XCTAssertEqual(profile.threads[0].samples.reduce(0) { $0 + $1.effectiveCount }, 5)

        // Thread 1: leaves with counts 1 and 3, summing to 4.
        let t1 = profile.threads[1].samples.map { $0.effectiveCount }.sorted()
        XCTAssertEqual(t1, [1, 3])
        XCTAssertEqual(profile.threads[1].samples.reduce(0) { $0 + $1.effectiveCount }, 4)
    }

    func testFrameTableDedupsAcrossThreads() throws {
        let tree = try decodeFixture()
        let profile = buildProfileData(from: tree)

        // Six distinct addresses across both threads (A, B, D, C, E, F); dyld/App/Foundation
        // are shared between the threads and must appear once.
        XCTAssertEqual(profile.frames.count, 6)

        // dyld (address 0x1000) appears exactly once in the shared table.
        XCTAssertEqual(profile.frames.filter { $0.instructionAddr == 0x1000 }.count, 1)
        // objectAddr is address - offset.
        let dyld = try XCTUnwrap(profile.frames.first { $0.instructionAddr == 0x1000 })
        XCTAssertEqual(dyld.objectAddr, 0x1000 - 256)
    }

    func testFramesAreDeepestFirst() throws {
        let tree = try decodeFixture()
        let profile = buildProfileData(from: tree)

        // Thread 0's count-3 sample is the path dyld -> App -> Foundation; deepest-first means
        // Foundation (0x3000) is first and dyld (0x1000) is last.
        let sample = try XCTUnwrap(profile.threads[0].samples.first { $0.effectiveCount == 3 })
        XCTAssertEqual(profile.frames[sample.frames.first!].instructionAddr, 0x3000)
        XCTAssertEqual(profile.frames[sample.frames.last!].instructionAddr, 0x1000)

        // Every index is valid.
        for thread in profile.threads {
            for s in thread.samples {
                for idx in s.frames {
                    XCTAssertTrue(idx >= 0 && idx < profile.frames.count)
                }
            }
        }
    }

    func testUnmappedFrameToleratesMissingNameAndUUID() throws {
        let tree = try decodeFixture()
        let profile = buildProfileData(from: tree)

        // Frame E (0x5000) had no binaryName/binaryUUID.
        let e = try XCTUnwrap(profile.frames.first { $0.instructionAddr == 0x5000 })
        XCTAssertNil(e.objectName)
        XCTAssertNil(e.objectUUID)
        // It still resolves an object address from its offset.
        XCTAssertEqual(e.objectAddr, 0x5000 - 1280)
    }

    func testAttributedThreadSelectedWhenNoOverride() throws {
        // When a thread is attributed and no override is passed, that thread becomes primary.
        let json = """
            {
              "callStacks": [
                { "threadAttributed": false, "callStackRootFrames": [ { "address": 1, "sampleCount": 1 } ] },
                { "threadAttributed": true, "callStackRootFrames": [ { "address": 2, "sampleCount": 1 } ] }
              ]
            }
            """
        let tree = try JSONDecoder().decode(CallStackTreeRepresentation.self, from: Data(json.utf8))
        let profile = buildProfileData(from: tree)
        XCTAssertFalse(profile.threads[0].primary)
        XCTAssertTrue(profile.threads[1].primary)
    }
}
