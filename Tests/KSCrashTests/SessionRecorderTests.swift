//
//  SessionRecorderTests.swift
//
//  Created by Alexander Cohen on 2025-12-14.
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
import KSCrashRecording
import KSCrashRecordingCore
import XCTest

@testable import KSCrash

final class SessionRecorderTests: XCTestCase {
    private var directory: URL!
    private var path: String!
    private var recorder: SessionRecorder!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("run.sessions").path
        recorder = SessionRecorder()
    }

    override func tearDown() {
        recorder.detach()
        try? FileManager.default.removeItem(at: directory)
    }

    private var sessionCount: Int {
        guard let reader = kssr_open(path) else { return 0 }
        defer { kssr_close(reader) }
        return Int(kssr_count(reader))
    }

    private var lastSession: KSSessionRecord? {
        guard let reader = kssr_open(path) else { return nil }
        defer { kssr_close(reader) }
        let count = kssr_count(reader)
        guard count > 0 else { return nil }
        var record = KSSessionRecord()
        guard kssr_sessionAt(reader, count - 1, &record) else { return nil }
        return record
    }

    func test_attach_recordsTheLaunchSession() throws {
        recorder.attach(path: path)
        XCTAssertGreaterThanOrEqual(sessionCount, 1, "attach records the launch session")
        let record = try XCTUnwrap(lastSession)
        XCTAssertNotNil(UUID(uuidString: tupleString(record.guid)), "a valid session id")
        XCTAssertEqual(tupleString(record.user), "", "the launch session is anonymous until a user is set")
        XCTAssertNotNil(recorder.currentSessionID)
    }

    func test_perceptibilityFlip_cutsASession_keepingTheUser() throws {
        recorder.attach(path: path)
        // Drive to a known imperceptible state; each active/background
        // alternation from here is a guaranteed flip.
        recorder.observeTransition(.background)
        let base = sessionCount
        XCTAssertGreaterThanOrEqual(base, 1)

        recorder.observeTransition(.active)
        XCTAssertEqual(sessionCount, base + 1)
        XCTAssertEqual(try XCTUnwrap(lastSession).perceptible, true)

        recorder.observeTransition(.background)
        XCTAssertEqual(sessionCount, base + 2)
        XCTAssertEqual(try XCTUnwrap(lastSession).perceptible, false)

        recorder.observeTransition(.active)
        recorder.observeTransition(.deactivating)
        XCTAssertEqual(sessionCount, base + 3, "a non-flip transition does not cut a session")
    }

    func test_userChange_cutsASession_includingLogout() throws {
        recorder.attach(path: path)
        recorder.observeTransition(.active)
        let base = sessionCount

        recorder.observeUser("bob")
        XCTAssertEqual(sessionCount, base + 1)
        XCTAssertEqual(tupleString(try XCTUnwrap(lastSession).user), "bob")
        XCTAssertEqual(try XCTUnwrap(lastSession).perceptible, true, "a user cut keeps perceptibility")

        recorder.observeUser("bob")
        XCTAssertEqual(sessionCount, base + 1, "the same user is a no-op")

        recorder.observeUser("alice")
        XCTAssertEqual(sessionCount, base + 2)

        recorder.observeUser(nil)
        XCTAssertEqual(sessionCount, base + 3, "logout is still a session change")
        XCTAssertEqual(tupleString(try XCTUnwrap(lastSession).user), "")
    }

    func test_currentSessionID_matchesTheLastRecord() throws {
        recorder.attach(path: path)
        recorder.observeTransition(.active)
        recorder.observeUser("dave")
        XCTAssertEqual(try XCTUnwrap(recorder.currentSessionID), tupleString(try XCTUnwrap(lastSession).guid))
    }

    func test_detachedRecorder_recordsNothing() {
        recorder.observeUser("bob")
        recorder.observeTransition(.active)
        XCTAssertEqual(sessionCount, 0)
        XCTAssertNil(recorder.currentSessionID)
    }
}

/// A fixed-size C char array's contents up to its NUL.
private func tupleString<T>(_ tuple: T) -> String {
    withUnsafePointer(to: tuple) {
        String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
    }
}
