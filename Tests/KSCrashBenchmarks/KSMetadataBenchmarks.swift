//
//  KSMetadataBenchmarks.swift
//
//  Created by Alexander Cohen on 2026-08-30.
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
import XCTest

/// The Swift metadata model layer: the conversion and JSON encoding a store
/// write drives, and the decoding and null resolution a read defers to. The
/// store file itself is measured by the KVS benchmarks; these cover the model
/// work that sits on top of it, so an encoder or decoder is allocated per
/// operation exactly as the shipping paths do.
final class KSMetadataBenchmarks: KSBenchmarkTestCase {

    /// A 100-leaf container; `nullEvery > 0` salts it with nulls at that stride.
    private func makeContainer(nullEvery: Int) -> MetadataValue {
        var members: [String: MetadataValue] = [:]
        for i in 0..<20 {
            var elements: [MetadataValue] = []
            for j in 0..<5 {
                let n = i * 5 + j
                if nullEvery > 0 && n % nullEvery == 0 {
                    elements.append(.null)
                } else {
                    elements.append(.string("value-\(i)-\(j)"))
                }
            }
            members["key\(i)"] = .array(elements)
        }
        return .object(members)
    }

    // MARK: - Writes (hot path)

    /// 100 scalar writes: the per-set conversion cost.
    func testBenchmarkWriteScalars() {
        // keys sorts, so it is checked once after the run rather than inside it.
        var bag = Metadata()
        measure {
            bag = Metadata()
            for i in 0..<25 {
                bag["string\(i)"] = "value-\(i)"
                bag["int\(i)"] = i
                bag["double\(i)"] = Double(i) * 1.5
                bag["bool\(i)"] = i % 2 == 0
            }
        }
        XCTAssertEqual(bag.keys.count, 100)
    }

    /// 20 writes of a native 100-leaf container: the recursive tree conversion.
    func testBenchmarkWriteContainers() {
        var native: [String: [String]] = [:]
        for i in 0..<20 {
            native["key\(i)"] = (0..<5).map { "value-\(i)-\($0)" }
        }
        var bag = Metadata()
        measure {
            bag = Metadata()
            for i in 0..<20 {
                bag["container\(i)"] = native
            }
        }
        XCTAssertEqual(bag.keys.count, 20)
    }

    /// 100 JSON encodes of a 100-leaf container: the sidecar write's heavy step.
    func testBenchmarkEncodeContainerBytes() {
        let container = makeContainer(nullEvery: 0)
        var lastCount = 0
        measure {
            for _ in 0..<100 {
                lastCount = (try? JSONEncoder().encode(container).count) ?? 0
            }
        }
        XCTAssertGreaterThan(lastCount, 0)
    }

    // MARK: - Reads (deferred work)

    /// 100 container reads through the store subscript (the null-resolving walk).
    func testBenchmarkReadContainers() {
        var bag = Metadata()
        bag["container"] = makeContainer(nullEvery: 0)
        var value: MetadataValue?
        measure {
            for _ in 0..<100 {
                value = bag["container"]
            }
        }
        XCTAssertNotNil(value)
    }

    /// Same read with a quarter of the leaves null: the stripping cost.
    func testBenchmarkReadContainersWithNulls() {
        var bag = Metadata()
        bag["container"] = makeContainer(nullEvery: 4)
        var value: MetadataValue?
        measure {
            for _ in 0..<100 {
                value = bag["container"]
            }
        }
        XCTAssertNotNil(value)
    }

    /// 100 decodes of persisted container bytes: the sidecar read boundary.
    func testBenchmarkDecodeContainerBytes() throws {
        let data = try JSONEncoder().encode(makeContainer(nullEvery: 0))
        var value: MetadataValue?
        measure {
            for _ in 0..<100 {
                value = try? JSONDecoder().decode(MetadataValue.self, from: data)
            }
        }
        XCTAssertNotNil(value)
    }

    /// Same decode with a quarter of the leaves null, which the decode keeps
    /// (the bag resolves them on read, not here).
    func testBenchmarkDecodeContainerBytesWithNulls() throws {
        let data = try JSONEncoder().encode(makeContainer(nullEvery: 4))
        var value: MetadataValue?
        measure {
            for _ in 0..<100 {
                value = try? JSONDecoder().decode(MetadataValue.self, from: data)
            }
        }
        XCTAssertNotNil(value)
    }
}
