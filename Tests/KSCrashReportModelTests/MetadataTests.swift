//
//  MetadataTests.swift
//
//  Created by Alexander Cohen on 2026-08-09.
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

final class MetadataTests: XCTestCase {
    private func asJSONObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Native input and typed retrieval

    func test_setAndGet_nativeScalars() {
        var bag = Metadata()
        let name = "Alex"  // runtime values
        bag.set(name, forKey: "name")
        bag.set(42, forKey: "age")
        bag.set(true, forKey: "enabled")
        bag.set(98.5, forKey: "score")

        XCTAssertEqual(bag.value(forKey: "name"), "Alex")
        XCTAssertEqual(bag.value(forKey: "age", as: Int.self), 42)
        XCTAssertEqual(bag.value(forKey: "enabled"), true)
        XCTAssertEqual(bag["score", as: Double.self], 98.5)
    }

    func test_get_wrongTypeReturnsNil() {
        var bag = Metadata()
        bag.set(42, forKey: "age")
        XCTAssertNil(bag.value(forKey: "age", as: String.self))
        XCTAssertNil(bag.value(forKey: "missing", as: Int.self))
    }

    func test_subscript_setGetAndNilRemoves() {
        var bag = Metadata()
        bag["age"] = 42
        let name = "Alex"
        bag["name"] = name
        let age: Int? = bag["age"]
        let n: String? = bag["name"]
        XCTAssertEqual(age, 42)
        XCTAssertEqual(n, "Alex")
        let none: Int? = nil
        bag["age"] = none
        XCTAssertFalse(bag.contains("age"))
    }

    func test_removeAndEmpty() {
        var bag = Metadata()
        bag.set(1, forKey: "a")
        bag.removeValue(forKey: "a")
        XCTAssertTrue(bag.isEmpty)
    }

    // MARK: - Codable wire form

    func test_wireFormat_isRawJSON() throws {
        var bag = Metadata()
        bag.set("gold", forKey: "tier")
        bag.set(["a", "b"], forKey: "tags")
        let json = try asJSONObject(JSONEncoder().encode(bag))
        XCTAssertEqual(json["tier"] as? String, "gold")
        XCTAssertEqual(json["tags"] as? [String], ["a", "b"])
    }

    func test_roundTrip_throughHostType() throws {
        struct Host: Codable, Equatable {
            let name: String
            let metadata: Metadata
        }
        var bag = Metadata()
        bag.set("gold", forKey: "tier")
        bag.set(42, forKey: "score")
        let original = Host(name: "x", metadata: bag)
        let decoded = try JSONDecoder().decode(Host.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Whole-bag typed access

    private struct Extras: Codable, Equatable {
        let tier: String
        let score: Int
    }

    func test_from_buildsBagFromCodable() throws {
        let bag = try Metadata.from(Extras(tier: "gold", score: 42))
        XCTAssertEqual(bag.value(forKey: "tier"), "gold")
        XCTAssertEqual(bag.value(forKey: "score", as: Int.self), 42)
    }

    func test_decoded_readsBagAsCodable() throws {
        var bag = Metadata()
        bag.set("gold", forKey: "tier")
        bag.set(42, forKey: "score")
        let extras = try bag.decoded(as: Extras.self)
        XCTAssertEqual(extras, Extras(tier: "gold", score: 42))
    }

    func test_from_then_decoded_roundTrips() throws {
        let original = Extras(tier: "silver", score: 7)
        let back = try Metadata.from(original).decoded(as: Extras.self)
        XCTAssertEqual(back, original)
    }

    func test_date_roundTripsAsSecondsSince1970() throws {
        var bag = Metadata()
        let date = Date(timeIntervalSince1970: 1_700_000_000.25)
        bag.set(date, forKey: "when")

        XCTAssertEqual(bag.value(forKey: "when", as: Date.self), date)
        // The wire form is a plain JSON double.
        XCTAssertEqual(bag.value(forKey: "when", as: Double.self), 1_700_000_000.25)
        let json = try String(decoding: JSONEncoder().encode(bag), as: UTF8.self)
        XCTAssertTrue(json.contains("1700000000.25"), json)
    }
}
