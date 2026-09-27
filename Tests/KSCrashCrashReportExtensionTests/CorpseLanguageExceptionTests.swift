//
//  CorpseLanguageExceptionTests.swift
//
//  Created by Alexander Cohen on 2026-09-27.
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

@testable import KSCrashCrashReportExtension

/// Stands in for an app's own NSException subclass, which the stitch can look up because it
/// runs in the app that crashed.
@objc(CorpseTestExceptionSubclass)
final class CorpseTestExceptionSubclass: NSException {}

/// Every message here is one a device wrote (iOS 27.0), copied byte for byte out of corpse
/// reports, except where a test says it is built to probe an edge.
final class CorpseLanguageExceptionTests: XCTestCase {

    static let coreFoundationPath = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    static let cxxABIPath = "/usr/lib/libc++abi.dylib"
    static let libcPath = "/usr/lib/system/libsystem_c.dylib"

    // CoreFoundation's messages, one per case. Each ends in the newline CoreFoundation writes.

    static let queueException = """
        *** Terminating app due to uncaught exception 'GCDException', reason: 'On a queue'
        *** First throw call stack:
        (0x19a203190 0x199f80380 0x19a2677a4 0x1010b1e28 0x1c865fccc 0x1c8679fb4 0x1c8664450 0x1c86729f8 \
        0x1c86730e4 0x19a0ab1fc 0x19a0aa910)\n
        """

    static let rangeException = """
        *** Terminating app due to uncaught exception 'NSRangeException', reason: '*** -[NSConstantArray objectAtIndex:]: index 10 beyond bounds [0 .. 2]'
        *** First throw call stack:
        (0x19a203190 0x199f80380 0x19a1e5a80 0x104789d2c 0x10478942c 0x104695874 0x1a47d9188 0x1a47d6e0c \
        0x1a47d90c8 0x1a47d8f34 0x1a47d8df0 0x1a4dab2ec 0x1a47d8cec 0x1a47d6e0c 0x1a47d8cb4 0x1a47d74b4 \
        0x1a2025990 0x1a1fe7b30 0x1a44e6058 0x1a4fce65c 0x1a1faee88 0x1a1faf0b4 0x1a1f7f1a8 0x1a1f7f4a8 \
        0x1a205a29c 0x1a47d8b28 0x1a47d6d5c 0x19e9b198c 0x19e9b17fc 0x19e9b1580 0x19e4aeb30 0x19e4ae984 \
        0x1a3d10dac 0x1a409bacc 0x1a3d11514 0x1a3d0e87c 0x1a3d1e608 0x19e4b441c 0x19e4b6298 0x19e9af874 \
        0x1a3ab5c60 0x19e4acbdc 0x19e434d78 0x19e433b88 0x19e433928 0x2ccf63bc0 0x19a1917cc 0x19a1b524c \
        0x19a1b545c 0x19a1a5634 0x19a1a67f4 0x244868f24 0x19e4841cc 0x1a4473404 0x1a446cb50 0x1a446ca10 \
        0x104696008 0x199ff75b8)\n
        """

    static let nilReasonException = """
        *** Terminating app due to uncaught exception 'NilReasonException', reason: '(null)'
        *** First throw call stack:
        (0x19a203190 0x199f80380 0x19a2677a4 0x1041d1e84 0x1041d1498 0x1040dd874 0x1a47d9188 0x1a47d6e0c \
        0x1a47d90c8 0x1a47d8f34 0x1a47d8df0 0x1a4dab2ec 0x1a47d8cec 0x1a47d6e0c 0x1a47d8cb4 0x1a47d74b4 \
        0x1a2025990 0x1a1fe7b30 0x1a44e6058 0x1a4fce65c 0x1a1faee88 0x1a1faf0b4 0x1a1f7f1a8 0x1a1f7f4a8 \
        0x1a205a29c 0x1a47d8b28 0x1a47d6d5c 0x19e9b198c 0x19e9b17fc 0x19e9b1580 0x19e4aeb30 0x19e4ae984 \
        0x1a3d10dac 0x1a409bacc 0x1a3d11514 0x1a3d0e87c 0x1a3d1e608 0x19e4b441c 0x19e4b6298 0x19e9af874 \
        0x1a3ab5c60 0x19e4acbdc 0x19e434d78 0x19e433b88 0x19e433928 0x2ccf63bc0 0x19a1917cc 0x19a1b524c \
        0x19a1b545c 0x19a1a5634 0x19a1a67f4 0x244868f24 0x19e4841cc 0x1a4473404 0x1a446cb50 0x1a446ca10 \
        0x1040de008 0x199ff75b8)\n
        """

    static let quotedException = """
        *** Terminating app due to uncaught exception 'Quoted'Name', reason: 'it's "quoted"', reason: 'fake
        second line'
        *** First throw call stack:
        (0x19a203190 0x199f80380 0x19a2677a4 0x1023d5ee4 0x1023d54bc 0x1022e1874 0x1a47d9188 0x1a47d6e0c \
        0x1a47d90c8 0x1a47d8f34 0x1a47d8df0 0x1a4dab2ec 0x1a47d8cec 0x1a47d6e0c 0x1a47d8cb4 0x1a47d74b4 \
        0x1a2025990 0x1a1fe7b30 0x1a44e6058 0x1a4fce65c 0x1a1faee88 0x1a1faf0b4 0x1a1f7f1a8 0x1a1f7f4a8 \
        0x1a205a29c 0x1a47d8b28 0x1a47d6d5c 0x19e9b198c 0x19e9b17fc 0x19e9b1580 0x19e4aeb30 0x19e4ae984 \
        0x1a3d10dac 0x1a409bacc 0x1a3d11514 0x1a3d0e87c 0x1a3d1e608 0x19e4b441c 0x19e4b6298 0x19e9af874 \
        0x1a3ab5c60 0x19e4acbdc 0x19e434d78 0x19e433b88 0x19e433928 0x2ccf63bc0 0x19a1917cc 0x19a1b524c \
        0x19a1b545c 0x19a1a5634 0x19a1a67f4 0x244868f24 0x19e4841cc 0x1a4473404 0x1a446cb50 0x1a446ca10 \
        0x1022e2008 0x199ff75b8)\n
        """

    static let subclassException = """
        *** Terminating app due to uncaught exception 'TestNSExceptionSubclass', reason: 'Subclass Test'
        *** First throw call stack:
        (0x19a203190 0x199f80380 0x19a2677a4 0x100345cf0 0x100345408 0x100251874 0x1a47d9188 0x1a47d6e0c \
        0x1a47d90c8 0x1a47d8f34 0x1a47d8df0 0x1a4dab2ec 0x1a47d8cec 0x1a47d6e0c 0x1a47d8cb4 0x1a47d74b4 \
        0x1a2025990 0x1a1fe7b30 0x1a44e6058 0x1a4fce65c 0x1a1faee88 0x1a1faf0b4 0x1a1f7f1a8 0x1a1f7f4a8 \
        0x1a205a29c 0x1a47d8b28 0x1a47d6d5c 0x19e9b198c 0x19e9b17fc 0x19e9b1580 0x19e4aeb30 0x19e4ae984 \
        0x1a3d10dac 0x1a409bacc 0x1a3d11514 0x1a3d0e87c 0x1a3d1e608 0x19e4b441c 0x19e4b6298 0x19e9af874 \
        0x1a3ab5c60 0x19e4acbdc 0x19e434d78 0x19e433b88 0x19e433928 0x2ccf63bc0 0x19a1917cc 0x19a1b524c \
        0x19a1b545c 0x19a1a5634 0x19a1a67f4 0x244868f24 0x19e4841cc 0x1a4473404 0x1a446cb50 0x1a446ca10 \
        0x100252008 0x199ff75b8)\n
        """

    static let handlerAbortsException = """
        *** Terminating app due to uncaught exception 'HandlerAbortsException', reason: 'App handler aborts'
        *** First throw call stack:
        (0x19a203190 0x199f80380 0x19a2677a4 0x1046c5f50 0x1046c54e0 0x1045d1874 0x1a47d9188 0x1a47d6e0c \
        0x1a47d90c8 0x1a47d8f34 0x1a47d8df0 0x1a4dab2ec 0x1a47d8cec 0x1a47d6e0c 0x1a47d8cb4 0x1a47d74b4 \
        0x1a2025990 0x1a1fe7b30 0x1a44e6058 0x1a4fce65c 0x1a1faee88 0x1a1faf0b4 0x1a1f7f1a8 0x1a1f7f4a8 \
        0x1a205a29c 0x1a47d8b28 0x1a47d6d5c 0x19e9b198c 0x19e9b17fc 0x19e9b1580 0x19e4aeb30 0x19e4ae984 \
        0x1a3d10dac 0x1a409bacc 0x1a3d11514 0x1a3d0e87c 0x1a3d1e608 0x19e4b441c 0x19e4b6298 0x19e9af874 \
        0x1a3ab5c60 0x19e4acbdc 0x19e434d78 0x19e433b88 0x19e433928 0x2ccf63bc0 0x19a1917cc 0x19a1b524c \
        0x19a1b545c 0x19a1a5634 0x19a1a67f4 0x244868f24 0x19e4841cc 0x1a4473404 0x1a446cb50 0x1a446ca10 \
        0x1045d2008 0x199ff75b8)\n
        """

    static let objCObjectException = "*** Terminating app due to uncaught exception of class '__NSCFConstantString'"

    static func images(_ messages: [(path: String, message: String)]) -> [[String: Any]] {
        messages.map { ["name": $0.path, "crash_info_message": $0.message] }
    }

    func testFixturesAreTheLengthTheDeviceWrote() {
        XCTAssertEqual(Self.queueException.utf8.count, 245)
        XCTAssertEqual(Self.rangeException.utf8.count, 873)
        XCTAssertEqual(Self.nilReasonException.utf8.count, 811)
        XCTAssertEqual(Self.quotedException.utf8.count, 839)
        XCTAssertEqual(Self.subclassException.utf8.count, 823)
        XCTAssertEqual(Self.handlerAbortsException.utf8.count, 827)
        XCTAssertEqual(Self.objCObjectException.utf8.count, 77)
    }

    // MARK: - CoreFoundation

    func testCoreFoundationMessageYieldsNameReasonAndThrowStack() {
        XCTAssertEqual(
            CorpseLanguageException.parseCoreFoundation(Self.queueException),
            .objC(
                name: "GCDException", reason: "On a queue",
                throwAddresses: [
                    0x19a2_03190, 0x199f_80380, 0x19a2_677a4, 0x1010_b1e28, 0x1c86_5fccc, 0x1c86_79fb4,
                    0x1c86_64450, 0x1c86_729f8, 0x1c86_730e4, 0x19a0_ab1fc, 0x19a0_aa910,
                ]))
    }

    /// The name, the reason, and how many addresses the throw stack held with its ends.
    private func assertObjC(
        _ message: String, name: String, reason: String?, frames: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard
            case .objC(let actualName, let actualReason, let addresses) =
                CorpseLanguageException.parseCoreFoundation(message)
        else {
            return XCTFail("not read as an Objective-C exception", file: file, line: line)
        }
        XCTAssertEqual(actualName, name, file: file, line: line)
        XCTAssertEqual(actualReason, reason, file: file, line: line)
        XCTAssertEqual(addresses.count, frames, file: file, line: line)
        XCTAssertEqual(addresses.first, 0x19a2_03190, file: file, line: line)
        XCTAssertEqual(addresses.last, 0x199f_f75b8, file: file, line: line)
    }

    func testSystemExceptionReasonKeepsItsPunctuation() {
        assertObjC(
            Self.rangeException, name: "NSRangeException",
            reason: "*** -[NSConstantArray objectAtIndex:]: index 10 beyond bounds [0 .. 2]", frames: 58)
    }

    func testNilReasonReadsAsNoReason() {
        assertObjC(Self.nilReasonException, name: "NilReasonException", reason: nil, frames: 58)
    }

    func testQuotesAndNewlinesInsideNameAndReasonSurvive() {
        // CoreFoundation writes both unescaped. This reason even repeats the separator.
        assertObjC(
            Self.quotedException, name: "Quoted'Name", reason: "it's \"quoted\"', reason: 'fake\nsecond line",
            frames: 58)
    }

    func testReasonEndingInANewlineIsKeptWhole() {
        // Built: the newline inside the quotes is the reason's; the ones after are
        // CoreFoundation's.
        XCTAssertEqual(
            CorpseLanguageException.parseCoreFoundation(
                "*** Terminating app due to uncaught exception 'Name', reason: 'line\n'\n"
                    + "*** First throw call stack:\n(0x19a203190)\n"),
            .objC(name: "Name", reason: "line\n", throwAddresses: [0x19a2_03190]))
        XCTAssertEqual(
            CorpseLanguageException.parseCoreFoundation(
                "*** Terminating app due to uncaught exception 'Name', reason: 'line\n'\n"),
            .objC(name: "Name", reason: "line\n", throwAddresses: []))
    }

    func testTextStartingWithACombiningMarkDoesNotHideTheSeparators() {
        // Built: a mark after a quote or space would fuse with it into one character.
        XCTAssertEqual(
            CorpseLanguageException.parseCoreFoundation(
                "*** Terminating app due to uncaught exception '\u{301}Name', reason: '\u{301}why'\n"
                    + "*** First throw call stack:\n(0x19a203190)\n"),
            .objC(name: "\u{301}Name", reason: "\u{301}why", throwAddresses: [0x19a2_03190]))
        XCTAssertEqual(
            CorpseLanguageException.parseCxxABI(
                "terminating due to uncaught exception of type std::runtime_error: \u{FE0F}what"),
            .cpp(name: "std::runtime_error", reason: "\u{FE0F}what"))
    }

    func testReasonEndingInAPrependCharacterKeepsItsReasonAndStack() {
        // Built: U+0600 fuses with the character after it, here the closing quote.
        XCTAssertEqual(
            CorpseLanguageException.parseCoreFoundation(
                "*** Terminating app due to uncaught exception 'Name', reason: 'why\u{600}'\n"
                    + "*** First throw call stack:\n(0x19a203190)\n"),
            .objC(name: "Name", reason: "why\u{600}", throwAddresses: [0x19a2_03190]))
        XCTAssertEqual(
            CorpseLanguageException.parseCoreFoundation(
                "*** Terminating app due to uncaught exception 'Name', reason: 'why\u{600}'\n"),
            .objC(name: "Name", reason: "why\u{600}", throwAddresses: []))
    }

    func testASignedAddressIsNoAddress() {
        // Built: Swift's integer parser would take the sign.
        XCTAssertEqual(
            CorpseLanguageException.parseCoreFoundation(
                "*** Terminating app due to uncaught exception 'Name', reason: 'Reason'\n"
                    + "*** First throw call stack:\n(0x19a203190 0x+1f)\n"),
            .objC(name: "Name", reason: "Reason", throwAddresses: []))
    }

    func testMessageWithoutAThrowStackStillNamesTheException() {
        // Built: the stack section is what a later OS would most plausibly drop or move.
        let message = "*** Terminating app due to uncaught exception 'Name', reason: 'Reason'\n"
        XCTAssertEqual(
            CorpseLanguageException.parseCoreFoundation(message),
            .objC(name: "Name", reason: "Reason", throwAddresses: []))
    }

    func testAThrowStackWithAnyUnreadableTokenIsDroppedWhole() {
        // Built: one token that is not an address.
        let message =
            "*** Terminating app due to uncaught exception 'Name', reason: 'Reason'\n"
            + "*** First throw call stack:\n(0x19a203190 garbage 0x199f80380)\n"
        XCTAssertEqual(
            CorpseLanguageException.parseCoreFoundation(message),
            .objC(name: "Name", reason: "Reason", throwAddresses: []))
    }

    func testAnObjectThatIsNotAnNSExceptionIsNotReadFromCoreFoundation() {
        // `@throw @"string"`: CoreFoundation words it differently and gives no reason or stack.
        XCTAssertNil(CorpseLanguageException.parseCoreFoundation(Self.objCObjectException))
    }

    // MARK: - libc++abi

    func testCxxExceptionWithAWhat() {
        XCTAssertEqual(
            CorpseLanguageException.parseCxxABI(
                "terminating due to uncaught exception of type std::runtime_error: C++ exception"),
            .cpp(name: "std::runtime_error", reason: "C++ exception"))
    }

    func testCxxExceptionWithoutAWhat() {
        XCTAssertEqual(
            CorpseLanguageException.parseCxxABI("terminating due to uncaught exception of type int"),
            .cpp(name: "int", reason: nil))
    }

    func testCxxWhatEndingInANewlineIsKeptWhole() {
        // Built: libc++abi adds no newline of its own, so this one is what()'s.
        XCTAssertEqual(
            CorpseLanguageException.parseCxxABI(
                "terminating due to uncaught exception of type std::runtime_error: message\n"),
            .cpp(name: "std::runtime_error", reason: "message\n"))
    }

    func testBareTerminateHasNothingToName() {
        XCTAssertEqual(CorpseLanguageException.parseCxxABI("terminating"), .cpp(name: nil, reason: nil))
    }

    func testUnrecognizedCxxWordingYieldsNothing() {
        // Built: wording no device in the survey wrote.
        XCTAssertNil(CorpseLanguageException.parseCxxABI("terminating due to uncaught foreign exception"))
        XCTAssertNil(CorpseLanguageException.parseCxxABI("terminating due to uncaught exception of type "))
        XCTAssertNil(CorpseLanguageException.parseCxxABI(""))
    }

    // MARK: - Choosing between them

    func testCoreFoundationWinsOverTheSubclassNameLibcxxabiGives() {
        let images = Self.images([
            (Self.coreFoundationPath, Self.subclassException),
            (Self.libcPath, "abort() called"),
            (
                Self.cxxABIPath,
                "terminating due to uncaught exception of type KSCrashTriggersList_TestNSExceptionSubclass"
            ),
        ])
        guard case .objC(let name, let reason, _) = CorpseLanguageException.read(fromBinaryImages: images) else {
            return XCTFail("expected an Objective-C exception")
        }
        XCTAssertEqual(name, "TestNSExceptionSubclass")
        XCTAssertEqual(reason, "Subclass Test")
    }

    func testAnAppHandlerThatAbortsFirstStillLeavesTheException() {
        // CoreFoundation writes before calling the app's handler; libc++abi never gets a turn.
        let images = Self.images([
            (Self.coreFoundationPath, Self.handlerAbortsException),
            (Self.libcPath, "abort() called"),
        ])
        guard case .objC(let name, let reason, _) = CorpseLanguageException.read(fromBinaryImages: images) else {
            return XCTFail("expected an Objective-C exception")
        }
        XCTAssertEqual(name, "HandlerAbortsException")
        XCTAssertEqual(reason, "App handler aborts")
    }

    func testAnObjCObjectThatIsNotAnNSExceptionReadsAsCxx() {
        let images = Self.images([
            (Self.coreFoundationPath, Self.objCObjectException),
            (Self.libcPath, "abort() called"),
            (Self.cxxABIPath, "terminating due to uncaught exception of type __NSCFConstantString"),
        ])
        XCTAssertEqual(
            CorpseLanguageException.read(fromBinaryImages: images), .cpp(name: "__NSCFConstantString", reason: nil))
    }

    func testAnNSExceptionWithoutItsCoreFoundationMessageStaysUnclassified() {
        // What a reason long enough to push CoreFoundation's message past the reader's string
        // cap leaves behind: libc++abi's line alone.
        let images = Self.images([
            (Self.libcPath, "abort() called"),
            (Self.cxxABIPath, "terminating due to uncaught exception of type NSException"),
        ])
        XCTAssertNil(CorpseLanguageException.read(fromBinaryImages: images))
    }

    func testAnNSExceptionSubclassWithoutItsCoreFoundationMessageStaysUnclassified() {
        // Built: a CoreFoundation message in wording this does not recognize.
        let images = Self.images([
            (Self.coreFoundationPath, "*** Some later wording 'CorpseTestExceptionSubclass'"),
            (Self.cxxABIPath, "terminating due to uncaught exception of type CorpseTestExceptionSubclass"),
        ])
        XCTAssertNil(CorpseLanguageException.read(fromBinaryImages: images))
    }

    func testAPlainAbortIsNoLanguageException() {
        XCTAssertNil(CorpseLanguageException.read(fromBinaryImages: Self.images([(Self.libcPath, "abort() called")])))
        XCTAssertNil(CorpseLanguageException.read(fromBinaryImages: []))
    }

    func testNSExceptionClassCheck() {
        XCTAssertTrue(CorpseLanguageException.isNSExceptionClass(named: "NSException"))
        XCTAssertTrue(CorpseLanguageException.isNSExceptionClass(named: "CorpseTestExceptionSubclass"))
        XCTAssertFalse(CorpseLanguageException.isNSExceptionClass(named: "__NSCFConstantString"))
        XCTAssertFalse(CorpseLanguageException.isNSExceptionClass(named: "std::runtime_error"))
        XCTAssertFalse(CorpseLanguageException.isNSExceptionClass(named: "int"))
    }
}
