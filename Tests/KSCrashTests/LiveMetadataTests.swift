//
//  LiveMetadataTests.swift
//
//  Created by Alexander Cohen on 2026-08-22.
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

@testable import KSCrash

final class LiveMetadataTests: XCTestCase {
    override func setUpWithError() throws {
        try TestInstall.ensure()
        for key in KSCrash.shared.metadata.keys {
            KSCrash.shared.metadata.removeValue(forKey: key)
        }
    }

    func test_availableAfterInstall_hasNoUnavailableReason() {
        XCTAssertNil(KSCrash.shared.metadata.unavailableReason)
    }

    func test_unattachableStore_recordsTheReason_andStaysInert() throws {
        let metadata = LiveMetadata()
        let bogus = URL(fileURLWithPath: "/dev/null/nope/UserInfo.ksscr").path
        XCTAssertThrowsError(try metadata.attach(path: bogus)) { error in
            XCTAssertTrue(error is InstallError)
        }
        XCTAssertNotNil(metadata.unavailableReason)
        metadata["k"] = "v"
        XCTAssertNil(metadata["k"] as String?)
        XCTAssertEqual(metadata.keys, [])
    }

    func test_eachScalarTypeRoundTrips() {
        let metadata = KSCrash.shared.metadata
        let when = Date(timeIntervalSince1970: 1_700_000_000.25)
        metadata["name"] = "Alice"
        metadata["count"] = -42
        metadata["big"] = UInt64.max
        metadata["ratio"] = 0.5
        metadata["flag"] = true
        metadata["when"] = when
        XCTAssertEqual(metadata["name"] as String?, "Alice")
        XCTAssertEqual(metadata["count"] as Int?, -42)
        XCTAssertEqual(metadata["big"] as UInt64?, UInt64.max)
        XCTAssertEqual(metadata["ratio"] as Double?, 0.5)
        XCTAssertEqual(metadata["flag"] as Bool?, true)
        XCTAssertEqual(
            (metadata["when"] as Date?)?.timeIntervalSince1970 ?? 0, when.timeIntervalSince1970, accuracy: 1e-6)
    }

    func test_datesBefore1970RoundTrip() {
        let metadata = KSCrash.shared.metadata
        let birthday = Date(timeIntervalSince1970: -157_766_400)
        metadata["birthday"] = birthday
        XCTAssertEqual(
            (metadata["birthday"] as Date?)?.timeIntervalSince1970 ?? 0,
            birthday.timeIntervalSince1970, accuracy: 1e-6)
    }

    func test_unrepresentableDate_removesTheKey_ratherThanStoringAStandIn() {
        let metadata = KSCrash.shared.metadata
        for unrepresentable in [Date.distantFuture, Date.distantPast, Date(timeIntervalSince1970: .nan)] {
            metadata["when"] = Date(timeIntervalSince1970: 1_700_000_000)
            metadata["when"] = unrepresentable
            XCTAssertNil(
                metadata["when"] as Date?,
                "an unrepresentable date must not leave a stale or fabricated value behind")
            XCTAssertFalse(metadata.keys.contains("when"))
        }
    }

    func test_latestWriteWins_andNilRemoves() {
        let metadata = KSCrash.shared.metadata
        metadata["k"] = "first"
        metadata["k"] = 2
        XCTAssertEqual(metadata["k"] as Int?, 2)
        XCTAssertNil(metadata["k"] as String?, "a key read as another type is nil")
        metadata["k"] = nil as Int?
        XCTAssertNil(metadata["k"] as Int?)
        metadata["k"] = "again"
        metadata.removeValue(forKey: "k")
        XCTAssertNil(metadata["k"] as String?)
        XCTAssertNil(metadata["never"] as String?)
    }

    func test_keys_listTheLiveKeysSorted() {
        let metadata = KSCrash.shared.metadata
        metadata["b"] = 1
        metadata["a"] = 2
        metadata["c"] = 3
        metadata.removeValue(forKey: "b")
        XCTAssertEqual(metadata.keys, ["a", "c"])
    }

    func test_concurrentAccess_staysCoherent() {
        let metadata = KSCrash.shared.metadata
        // Hammer one key from many threads; the lock makes every access
        // atomic, so reads see complete values and the store never tears.
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            metadata["contended"] = "value_\(i)"
            let read: String? = metadata["contended"]
            if let read {
                XCTAssertTrue(read.hasPrefix("value_"), read)
            }
            _ = metadata.keys
            if i % 10 == 0 {
                metadata.removeValue(forKey: "contended")
            }
        }
        metadata["contended"] = "final"
        XCTAssertEqual(metadata["contended"] as String?, "final")
    }

    func test_readsLikeTheReportsMetadata() {
        // The same protocol surface on both stores.
        func theme(in store: some MetadataStore) -> String? { store["theme"] }
        KSCrash.shared.metadata["theme"] = "dark"
        var report = Metadata()
        report["theme"] = "dark"
        XCTAssertEqual(theme(in: KSCrash.shared.metadata), theme(in: report))
    }
}
