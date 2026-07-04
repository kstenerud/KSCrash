//
//  NameTableParityTests.swift
//
//  Created by Alexander Cohen on 2026-07-04.
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

import Darwin
import KSCrashRecordingCore
import KSCrashReportModel
import XCTest

/// The Swift report model deliberately duplicates the C name tables (KSCrashReportModel is pure
/// Swift and cannot import C). Reports carry C-derived name strings (`SignalError.name`,
/// `MachError.exceptionName`) that must agree with the Swift case names, so these tests tie the
/// two tables together and catch drift in either direction.
final class NameTableParityTests: XCTestCase {

    func testSignalCaseNamesMatchCTable() {
        var compared = 0
        for signal in Signal.allCases {
            // The C table only names the fatal signals it monitors; those it names must agree.
            guard let cName = kssignal_signalName(signal.rawValue) else { continue }
            XCTAssertEqual(String(cString: cName), String(describing: signal), "Signal \(signal.rawValue)")
            compared += 1
        }
        // A table that stopped naming anything would otherwise skip every comparison and pass,
        // which is precisely the drift this test exists to catch.
        XCTAssertGreaterThan(compared, 0, "the C signal table named nothing, so nothing was compared")
    }

    func testSignalCoverageOfCTable() {
        // Every signal the C side can report must exist as a Swift case.
        var count: Int32 = 0
        guard let fatalSignals = kssignal_fatalSignals() else {
            XCTFail("No fatal signal table")
            return
        }
        count = kssignal_numFatalSignals()
        for i in 0..<Int(count) {
            let sigNum = fatalSignals[i]
            XCTAssertNotNil(Signal(rawValue: sigNum), "Missing Swift case for signal \(sigNum)")
        }
    }

    func testMachExceptionConstantNamesMatchCTable() {
        // MachExceptionType is an open struct, so the known constants are enumerated here
        // with their names; the C table's names must agree with the Swift constants'.
        let known: [(MachExceptionType, String)] = [
            (.EXC_BAD_ACCESS, "EXC_BAD_ACCESS"),
            (.EXC_BAD_INSTRUCTION, "EXC_BAD_INSTRUCTION"),
            (.EXC_ARITHMETIC, "EXC_ARITHMETIC"),
            (.EXC_EMULATION, "EXC_EMULATION"),
            (.EXC_SOFTWARE, "EXC_SOFTWARE"),
            (.EXC_BREAKPOINT, "EXC_BREAKPOINT"),
            (.EXC_SYSCALL, "EXC_SYSCALL"),
            (.EXC_MACH_SYSCALL, "EXC_MACH_SYSCALL"),
            (.EXC_RPC_ALERT, "EXC_RPC_ALERT"),
            (.EXC_CRASH, "EXC_CRASH"),
            (.EXC_RESOURCE, "EXC_RESOURCE"),
            (.EXC_GUARD, "EXC_GUARD"),
            (.EXC_CORPSE_NOTIFY, "EXC_CORPSE_NOTIFY"),
        ]
        var compared = 0
        for (exception, name) in known {
            // The C table stops at EXC_RESOURCE; the names it has must agree.
            guard let cName = ksmach_exceptionName(Int64(exception.rawValue)) else { continue }
            XCTAssertEqual(String(cString: cName), name, "Exception \(exception.rawValue)")
            compared += 1
        }
        // Same reasoning as the signal table: no comparisons is a failure, not a pass.
        XCTAssertGreaterThan(compared, 0, "the C exception table named nothing, so nothing was compared")

        // The Swift constants are the other half of the parity: a new or renamed one must show
        // up here, so pin the count the list is meant to cover.
        XCTAssertEqual(known.count, 13, "add new MachExceptionType constants to the parity list")
    }
}
