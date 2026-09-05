//
//  KCDataParserTests.swift
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
import KSCrashReportModel
import XCTest

@testable import KSCrashCrashReportExtension

final class KCDataParserTests: XCTestCase {

    // kcdata item type numbers (verified in the handoff).
    private let kBegin: UInt32 = 0xDEAD_F157
    private let kEnd: UInt32 = 0xF191_58ED
    private let kExceptionCodes: UInt32 = 0x80E
    private let kExitReasonSnapshot: UInt32 = 0x1001
    private let kCrashedThreadID: UInt32 = 0x81A
    private let kProcName: UInt32 = 0x809

    private func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
    private func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * $0)) & 0xFF) } }

    /// Build a kcdata crash-info buffer: a BEGIN marker, the given items, then an END marker, each a
    /// 16-byte TLV header (type, size, flags) plus payload, padded to 16 bytes.
    private func buildKCData(_ items: [(type: UInt32, payload: [UInt8])]) -> Data {
        var buf = [UInt8]()
        func appendItem(_ type: UInt32, _ payload: [UInt8]) {
            buf += le32(type)
            buf += le32(UInt32(payload.count))
            buf += le64(0)  // flags
            buf += payload
            while buf.count % 16 != 0 { buf.append(0) }
        }
        appendItem(kBegin, [])
        for item in items { appendItem(item.type, item.payload) }
        appendItem(kEnd, [])
        return Data(buf)
    }

    // MARK: - Tests (mirror the handoff's verified device samples)

    func testNullDeref() {
        let data = buildKCData([(kExceptionCodes, le64(0x0B10_0001) + le64(0))])
        let info = KCDataParser.parse(data, exception: EXC_BAD_ACCESS)?.crashInfo
        XCTAssertEqual(info?.signal, .SIGSEGV)
        XCTAssertEqual(info?.machException, .EXC_BAD_ACCESS)
        XCTAssertEqual(info?.subcode, 1)  // KERN_INVALID_ADDRESS
        XCTAssertEqual(info?.faultAddress, 0)  // real fault address is 0 for a null deref
    }

    func testBadPointerCarriesFaultAddress() {
        // The key finding: the real fault address lives in the kcdata subcode word, not CrashReason.
        let fault: UInt64 = 0x1_0A94_0000
        let info = KCDataParser.parse(
            buildKCData([(kExceptionCodes, le64(0x0B10_0001) + le64(fault))]), exception: EXC_BAD_ACCESS)?.crashInfo
        XCTAssertEqual(info?.faultAddress, fault)
        XCTAssertEqual(info?.machException, .EXC_BAD_ACCESS)
    }

    // The code word is a packed CrashReporter value, not a Mach code: reporting it verbatim
    // would write mach.code 0x0B100001 where an in-process report writes KERN_INVALID_ADDRESS.
    func testMachCodeUnpacksOrdinaryCrashes() {
        let info = KCDataParser.parse(
            buildKCData([(kExceptionCodes, le64(0x0B10_0001) + le64(0))]), exception: EXC_BAD_ACCESS)?.crashInfo
        XCTAssertEqual(info?.exceptionCode, 0x0B10_0001)
        XCTAssertEqual(info?.machCode(for: .EXC_BAD_ACCESS), 1)
    }

    // EXC_RESOURCE and EXC_GUARD define the whole word as a payload, so it passes through.
    func testMachCodeKeepsPayloadCarryingExceptions() {
        let resourceCode: UInt64 = 0x6400_0000_0900_0D30
        let resource = KCDataParser.parse(
            buildKCData([(kExceptionCodes, le64(resourceCode) + le64(0))]), exception: EXC_RESOURCE)?.crashInfo
        XCTAssertEqual(resource?.machCode(for: .EXC_RESOURCE), resourceCode)

        let guardCode: UInt64 = 0x2000_0002_0000_0005
        let guarded = KCDataParser.parse(
            buildKCData([(kExceptionCodes, le64(guardCode) + le64(0))]), exception: EXC_GUARD)?.crashInfo
        XCTAssertEqual(guarded?.machCode(for: .EXC_GUARD), guardCode)
    }

    // No Mach exception in the packed word (an EXC_CRASH from a signal) leaves no code to report.
    func testMachCodeIsZeroWithoutAMachException() {
        let info = KCDataParser.parse(
            buildKCData([(kExceptionCodes, le64(0x0600_0000) + le64(0))]), exception: EXC_CRASH)?.crashInfo
        XCTAssertNil(info?.machException)
        XCTAssertEqual(info?.machCode(for: .EXC_CRASH), 0)
    }

    func testUncaughtNSExceptionIsAbort() {
        let info = KCDataParser.parse(
            buildKCData([(kExceptionCodes, le64(0x0600_0000) + le64(0))]), exception: EXC_CRASH)?.crashInfo
        XCTAssertEqual(info?.signal, .SIGABRT)
        XCTAssertNil(info?.machException)
        XCTAssertNil(info?.faultAddress)
    }

    func testOOMResourceAndExitReason() {
        let info = KCDataParser.parse(
            buildKCData([
                (kExceptionCodes, le64(0x6400_0000_0900_0D30) + le64(0)),
                (kExitReasonSnapshot, le32(1) + le64(7) + le64(0)),  // namespace 1 (jetsam), code 7
            ]), exception: EXC_RESOURCE)?.crashInfo
        XCTAssertEqual(info?.resource?.type, .RESOURCE_TYPE_MEMORY)
        XCTAssertEqual(info?.resource?.flavor, .FLAVOR_HIGH_WATERMARK)
        XCTAssertEqual(info?.resource?.limitMB, 3376)
        XCTAssertEqual(info?.exitReason?.namespace, .OS_REASON_JETSAM)
        // code 7 is a jetsam reason (JETSAM_REASON_MEMORY_PERPROCESSLIMIT), not a magic code, so it is
        // preserved as the raw value rather than a named constant.
        XCTAssertEqual(info?.exitReason?.code.rawValue, 7)
    }

    // The HWM limit occupies bits [15:0] (EXC_RESOURCE_HWM_LIMIT_MASK); a narrower mask
    // silently truncated limits of 8192 MB and up (extended-memory iPads, Catalyst).
    func testResourceMemoryLimitAbove8GB() {
        let code: UInt64 = (3 << 61) | (1 << 58) | 12288
        let info = KCDataParser.parse(
            buildKCData([(kExceptionCodes, le64(code) + le64(0))]), exception: EXC_RESOURCE)?.crashInfo
        XCTAssertEqual(info?.resource?.type, .RESOURCE_TYPE_MEMORY)
        XCTAssertEqual(info?.resource?.limitMB, 12288)
    }

    // dyld/RunningBoard termination descriptions embed newlines ("Library not loaded: ...\n
    // Referenced from: ..."); they must survive verbatim, not be rejected as corruption.
    func testMultilineExitReasonDescriptionSurvives() {
        let kExitReasonUserDesc: UInt32 = 0x1002
        let desc = "Library not loaded: @rpath/Gone.framework\n  Referenced from: <ABC> /App\n\tReason: tried"
        let info = KCDataParser.parse(
            buildKCData([(kExitReasonUserDesc, Array(desc.utf8) + [0])]), exception: EXC_CRASH)?.crashInfo
        XCTAssertEqual(info?.exitReasonDescription, desc)
    }

    func testDescriptionWithOtherControlCharactersIsRejected() {
        let kExitReasonUserDesc: UInt32 = 0x1002
        let info = KCDataParser.parse(
            buildKCData([(kExitReasonUserDesc, Array("bad\u{01}data".utf8) + [0])]), exception: EXC_CRASH)?.crashInfo
        XCTAssertNil(info?.exitReasonDescription)
    }

    func testProcessContextFields() {
        let info = KCDataParser.parse(
            buildKCData([
                (kCrashedThreadID, le64(0x1234)),
                (kProcName, Array("MyApp".utf8) + [0]),
            ]), exception: EXC_CRASH)?.crashInfo
        XCTAssertEqual(info?.crashedThreadID, 0x1234)
        XCTAssertEqual(info?.processName, "MyApp")
    }

    func testRejectsNonCrashInfoBuffer() {
        XCTAssertNil(KCDataParser.parse(Data([0, 1, 2, 3]), exception: EXC_CRASH))
        XCTAssertNil(KCDataParser.parse(Data(le32(0xDEAD_BEEF) + le32(0) + le64(0)), exception: EXC_CRASH))
    }

    func testDecodesRusageAsVersionedPrefix() {
        let uuid: [UInt8] = Array(1...16)
        // A v3-sized item: uuid + 27 u64s, ending at servicedSystemTime. Later fields stay nil.
        let v3 = uuid + (1...27).flatMap { le64(UInt64($0)) }
        let rusage = KCDataParser.parse(buildKCData([(0x808, v3)]), exception: EXC_CRASH)?.rusage
        XCTAssertEqual(rusage?.userTime, 1)
        XCTAssertEqual(rusage?.physFootprint, 8)
        XCTAssertEqual(rusage?.servicedSystemTime, 27)
        XCTAssertNil(rusage?.logicalWrites)
        XCTAssertNotNil(rusage?.uuid)

        // An oversized item (a future rusage version): every known field fills, the tail is ignored.
        let future = uuid + (1...60).flatMap { le64(UInt64($0)) }
        let full = KCDataParser.parse(buildKCData([(0x808, future)]), exception: EXC_CRASH)?.rusage
        XCTAssertEqual(full?.pageCacheHits, 50)
    }

    func testDecodesProcessCodeSigningLedgersAndWorkqueue() {
        let uuid: [UInt8] = Array(1...16)
        var triage = [UInt8](repeating: 0, count: 640)
        triage.replaceSubrange(0..<5, with: Array("VM - ".utf8))
        triage.replaceSubrange(128..<131, with: Array("foo".utf8))

        let decoded = KCDataParser.parse(
            buildKCData([
                (0x806, le32(99)),  // ppid
                (0x818, le32(1)),  // responsible pid
                (0x802, uuid + le64(42) + le64(41) + le64(0) + le64(0) + le64(0)),  // bsdinfo with uniqid
                (0x826, le64(123_456)),  // ledger: phys footprint
                (0x82A, le64(789)),  // ledger: wired
                (0x82B, le32(200)),  // persona id (sits inside the ledger id range)
                (0x836, triage),  // kernel triage strings
                (0x83B, Array("com.example.app".utf8) + [0]),  // cs signing id
                (0x83E, le32(4)),  // cs trust level
                (0x817, le32(4) + le32(2) + le32(1) + le32(0)),  // workqueue info
                (0x846, le64(7) + le32(11) + le32(12)),  // voucher
                (0x848, [0x34, 0x12]),  // psa flags (u16)
            ]), exception: EXC_CRASH)

        XCTAssertEqual(decoded?.process?.ppid, 99)
        XCTAssertEqual(decoded?.process?.responsiblePid, 1)
        XCTAssertEqual(decoded?.process?.uniqueID, 42)
        XCTAssertEqual(decoded?.process?.parentUniqueID, 41)
        XCTAssertNotNil(decoded?.process?.executableUUID)
        XCTAssertEqual(decoded?.process?.personaID, 200)
        XCTAssertEqual(decoded?.process?.psaFlags, 0x1234)
        XCTAssertEqual(decoded?.process?.voucher?.threadID, 7)
        XCTAssertEqual(decoded?.process?.voucher?.originatorPid, 11)
        XCTAssertEqual(decoded?.process?.voucher?.proximatePid, 12)

        XCTAssertEqual(decoded?.ledgers?.physFootprint, 123_456)
        XCTAssertEqual(decoded?.ledgers?.wiredMemory, 789)
        XCTAssertNil(decoded?.ledgers?.internalMemory)

        XCTAssertEqual(decoded?.kernelTriage, ["VM - ", "foo"])

        XCTAssertEqual(decoded?.codeSigning?.signingID, "com.example.app")
        XCTAssertEqual(decoded?.codeSigning?.trustLevel, 4)

        XCTAssertEqual(decoded?.workqueue?.totalThreads, 4)
        XCTAssertEqual(decoded?.workqueue?.runningThreads, 2)
        XCTAssertEqual(decoded?.workqueue?.blockedThreads, 1)
    }

    func testDecodesExitReasonCompanionItems() {
        let info = KCDataParser.parse(
            buildKCData([
                (kExitReasonSnapshot, le32(4) + le64(2) + le64(0x8)),  // namespace, code, flags
                (0x1005, le64(0xABC)),  // workloop id
                (0x1006, le64(3)),  // dispatch queue number
                (0x1003, [1, 2, 3, 4]),  // user payload
            ]), exception: EXC_CRASH)?.crashInfo
        XCTAssertEqual(info?.exitReason?.flags, 0x8)
        XCTAssertEqual(info?.exitReason?.workloopID, 0xABC)
        XCTAssertEqual(info?.exitReason?.dispatchQueueNo, 3)
        XCTAssertEqual(info?.exitReason?.userPayload, Data([1, 2, 3, 4]))
    }

    func testEmptySectionsStayNil() {
        let decoded = KCDataParser.parse(
            buildKCData([(kCrashedThreadID, le64(1))]), exception: EXC_CRASH)
        XCTAssertNil(decoded?.rusage)
        XCTAssertNil(decoded?.ledgers)
        XCTAssertNil(decoded?.kernelTriage)
        XCTAssertNil(decoded?.codeSigning)
        XCTAssertNil(decoded?.process)
        XCTAssertNil(decoded?.workqueue)
    }
}
