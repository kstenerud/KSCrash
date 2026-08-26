//
//  Backtrace.swift
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
import KSCrashRecordingCore

/// A thread's return addresses, captured live (never from a crash handler).
public struct Backtrace: Sendable, Equatable {
    public let addresses: [UInt]
    /// Whether the capture hit `maxFrames` before the stack ended.
    public let isTruncated: Bool

    public var count: Int { addresses.count }

    /// Captures `thread`, briefly suspending it. nil when it could not be
    /// captured or `maxFrames` is not positive.
    public static func capture(thread: pthread_t, maxFrames: Int) -> Backtrace? {
        capture(maxFrames: maxFrames) { buffer, count, truncated in
            captureBacktrace(thread: thread, addresses: buffer, count: count, isTruncated: truncated)
        }
    }

    /// Captures a Mach thread, briefly suspending it. nil when it could not
    /// be captured or `maxFrames` is not positive.
    public static func capture(machThread: thread_t, maxFrames: Int) -> Backtrace? {
        capture(maxFrames: maxFrames) { buffer, count, truncated in
            captureBacktrace(machThread: machThread, addresses: buffer, count: count, isTruncated: truncated)
        }
    }

    /// The symbol and image an address belongs to; nil when unknown.
    public static func symbolicate(_ address: UInt) -> SymbolInformation? {
        var info = KSCrashRecordingCore.SymbolInformation()
        guard KSCrashRecordingCore.symbolicate(address: address, result: &info) else { return nil }
        return SymbolInformation(info)
    }

    /// `symbolicate` without the slower lookups; nil when unknown.
    public static func quickSymbolicate(_ address: UInt) -> SymbolInformation? {
        var info = KSCrashRecordingCore.SymbolInformation()
        guard KSCrashRecordingCore.quickSymbolicate(address: address, result: &info) else { return nil }
        return SymbolInformation(info)
    }

    private static func capture(
        maxFrames: Int, _ body: (UnsafeMutablePointer<UInt>, Int32, UnsafeMutablePointer<Bool>) -> Int32
    ) -> Backtrace? {
        // A frame budget can be computed from data: an invalid one is absence,
        // never a fabricated frame or a trap. Guarded before any allocation
        // or thread suspension; the upper bound is the capture's Int32 count.
        guard maxFrames > 0, maxFrames <= Int(Int32.max) else { return nil }
        var buffer = [UInt](repeating: 0, count: maxFrames)
        var truncated = false
        let captured = buffer.withUnsafeMutableBufferPointer { pointer in
            Int(body(pointer.baseAddress!, Int32(pointer.count), &truncated))
        }
        guard captured > 0 else { return nil }
        return Backtrace(addresses: Array(buffer.prefix(captured)), isTruncated: truncated)
    }
}

/// What `Backtrace.symbolicate` knows about an address.
public struct SymbolInformation: Sendable, Equatable {
    public let returnAddress: UInt
    public let callInstruction: UInt
    public let symbolAddress: UInt
    public let symbolName: String?
    public let imageName: String?
    public let imageUUID: UUID?
    public let imageAddress: UInt
    public let imageSize: UInt64

    init(_ info: KSCrashRecordingCore.SymbolInformation) {
        returnAddress = info.returnAddress
        callInstruction = info.callInstruction
        symbolAddress = info.symbolAddress
        symbolName = info.symbolName.map { String(cString: $0) }
        imageName = info.imageName.map { String(cString: $0) }
        imageUUID = info.imageUUID.map { bytes in
            UUID(
                uuid: (
                    bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                    bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
                ))
        }
        imageAddress = info.imageAddress
        imageSize = info.imageSize
    }
}
