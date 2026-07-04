//
//  CrashClassificationTests.swift
//
//  Created by Alexander Cohen on 2026-06-28.
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
import XCTest

@testable import KSCrashReportModel

final class CrashClassificationTests: XCTestCase {

    // MARK: - Closed enum (Signal)

    func testClosedEnumMapsKnownValues() {
        XCTAssertEqual(Signal(rawValue: 11), .SIGSEGV)
        XCTAssertEqual(Signal.SIGSEGV.rawValue, 11)
        XCTAssertEqual(Signal(rawValue: 6), .SIGABRT)
    }

    func testClosedEnumReturnsNilForUnknownValue() {
        // The Darwin signal set is genuinely fixed, so a value outside it has no case.
        XCTAssertNil(Signal(rawValue: 99))
    }

    func testClosedEnumEncodesAsBareIntAndRoundTrips() throws {
        let data = try JSONEncoder().encode([Signal.SIGSEGV])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[11]")
        XCTAssertEqual(try JSONDecoder().decode([Signal].self, from: data), [.SIGSEGV])
    }

    // MARK: - Mach exceptions (open: the kernel grows the set)

    func testMachExceptionTypeMapsKnownValues() {
        XCTAssertEqual(MachExceptionType(rawValue: 1), .EXC_BAD_ACCESS)
        XCTAssertEqual(MachExceptionType.EXC_CRASH.rawValue, 10)
        XCTAssertEqual(MachExceptionType(rawValue: 13), .EXC_CORPSE_NOTIFY)
    }

    func testMachExceptionTypePreservesUnknownValues() {
        // EXC_GUARD and EXC_CORPSE_NOTIFY were both kernel additions: a value we have no
        // constant for yet must classify and round-trip, never abort a capture or a decode.
        let future = MachExceptionType(rawValue: 42)
        XCTAssertEqual(future.rawValue, 42)
        XCTAssertEqual(try JSONDecoder().decode([MachExceptionType].self, from: Data("[42]".utf8)), [future])
    }

    // MARK: - Open structs (ResourceType, ResourceFlavor, ExitReasonNamespace, ExitReasonCode)

    func testOpenStructsExposeKnownConstants() {
        XCTAssertEqual(ResourceType.RESOURCE_TYPE_MEMORY.rawValue, 3)
        XCTAssertEqual(ResourceType(rawValue: 3), .RESOURCE_TYPE_MEMORY)
        XCTAssertEqual(ExitReasonNamespace.OS_REASON_JETSAM.rawValue, 1)
        XCTAssertEqual(ExitReasonNamespace.OS_REASON_SECINIT.rawValue, 47)
        XCTAssertEqual(ExitReasonCode.watchdogTimeout.rawValue, 0x8BAD_F00D)
    }

    func testOpenStructsPreserveUnknownValues() {
        // The point of the open types: a value we have no constant for is kept, never dropped.
        XCTAssertEqual(ResourceType(rawValue: 99).rawValue, 99)
        XCTAssertEqual(ExitReasonNamespace(rawValue: 999).rawValue, 999)
        XCTAssertEqual(ExitReasonCode(rawValue: 0xABCD).rawValue, 0xABCD)
        XCTAssertNotEqual(ExitReasonNamespace(rawValue: 999), .OS_REASON_JETSAM)
    }

    func testOpenStructEncodesAsBareIntAndRoundTripsIncludingUnknown() throws {
        // A known constant encodes as a bare int and round-trips.
        let known = try JSONEncoder().encode([ExitReasonNamespace.OS_REASON_JETSAM])
        XCTAssertEqual(String(decoding: known, as: UTF8.self), "[1]")
        XCTAssertEqual(try JSONDecoder().decode([ExitReasonNamespace].self, from: known), [.OS_REASON_JETSAM])

        // An unknown value round-trips too, with no throw. This is what the open types buy over enums.
        let unknown = try JSONEncoder().encode([ExitReasonNamespace(rawValue: 999)])
        XCTAssertEqual(String(decoding: unknown, as: UTF8.self), "[999]")
        XCTAssertEqual(try JSONDecoder().decode([ExitReasonNamespace].self, from: unknown).first?.rawValue, 999)
    }

    func testResourceFlavorPacksTypeAndFlavorPair() throws {
        // Flavor numbers repeat across resource types, so a flavor is built from the (type, flavor) pair
        // and its raw value packs both.
        XCTAssertEqual(ResourceFlavor(type: 3, flavor: 1), .FLAVOR_HIGH_WATERMARK)
        XCTAssertEqual(ResourceFlavor(type: 1, flavor: 1), .FLAVOR_CPU_MONITOR)
        XCTAssertEqual(ResourceFlavor.FLAVOR_HIGH_WATERMARK.rawValue, 31)

        // An unrecognized pair is preserved via the packed value and round-trips.
        let unknown = ResourceFlavor(type: 7, flavor: 3)
        XCTAssertEqual(unknown.rawValue, 73)
        let data = try JSONEncoder().encode([unknown])
        XCTAssertEqual(try JSONDecoder().decode([ResourceFlavor].self, from: data), [unknown])
    }

    func testExitReasonInfoDecodesTheNamespaceAndFlagsACorpseReportCarries() throws {
        // The corpse stitch writes namespace and flags alongside code. A model that knows only
        // code would drop both on decode, so the enrichment would be invisible to every typed
        // consumer and stripped from any report that is decoded and re-encoded.
        let json = Data(#"{"code":2343432205,"namespace":1,"flags":7}"#.utf8)
        let decoded = try JSONDecoder().decode(ExitReasonInfo.self, from: json)
        XCTAssertEqual(decoded.code, 0x8BAD_F00D)
        XCTAssertEqual(decoded.namespace, .OS_REASON_JETSAM)
        XCTAssertEqual(decoded.flags, 7)

        // Survives a round trip rather than being silently dropped on re-encode.
        let reencoded = try JSONEncoder().encode(decoded)
        XCTAssertEqual(try JSONDecoder().decode(ExitReasonInfo.self, from: reencoded), decoded)

        // Reports the in-process writer produced carry only a code, and must still decode.
        let codeOnly = try JSONDecoder().decode(ExitReasonInfo.self, from: Data(#"{"code":10}"#.utf8))
        XCTAssertEqual(codeOnly.code, 10)
        XCTAssertNil(codeOnly.namespace)
        XCTAssertNil(codeOnly.flags)
    }
}
