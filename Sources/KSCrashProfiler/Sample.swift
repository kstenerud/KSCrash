//
//  Sample.swift
//
//  Created by Alexander Cohen on 2025-12-12.
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

// MARK: - Protocol

/// Protocol for backtrace samples with fixed-size inline storage.
///
/// Sample types use tuple-based storage to hold stack frame addresses inline,
/// avoiding heap allocations during capture. Each concrete type (Sample32, Sample64, etc.)
/// provides storage for a different maximum number of frames.
///
/// ## Choosing a Sample Type
///
/// Choose based on your expected maximum stack depth:
/// - `Sample32`: Shallow stacks (UI code, simple callbacks)
/// - `Sample64`: Common case (most application code)
/// - `Sample128`: Deep stacks (recursive algorithms, deep call chains)
/// - `Sample256`: Very deep stacks (complex frameworks)
/// - `Sample512`: Extremely deep stacks (rare edge cases)
///
/// Using a smaller sample type reduces memory usage but may truncate deep stacks.
public protocol Sample: Sendable {
    /// The tuple type used for inline address storage.
    associatedtype Storage

    /// Maximum number of stack frames this sample type can hold.
    static var capacity: Int { get }

    /// Number of valid addresses captured (0...capacity).
    var addressCount: Int { get set }

    /// Timing metadata for this sample.
    var metadata: SampleMetadata { get set }

    /// Inline tuple storage for stack frame addresses.
    var storage: Storage { get set }

    /// Creates a new zero-initialized sample.
    init()
}

// MARK: - Default Implementations

extension Sample {
    /// Returns the captured stack frame addresses as an array.
    ///
    /// This creates a new array from the inline storage. For performance-critical
    /// code paths, prefer accessing `storage` directly via `withUnsafeBytes`.
    public var addresses: [UInt] {
        withUnsafeBytes(of: storage) { ptr in
            Array(ptr.bindMemory(to: UInt.self).prefix(addressCount))
        }
    }

    /// Captures a backtrace from the specified thread into this sample's storage.
    ///
    /// - Parameters:
    ///   - thread: The mach thread port to capture the backtrace from.
    ///   - captureBacktrace: The backtrace capture function (typically from KSCrashRecordingCore).
    ///
    /// After capture, `addressCount` contains the number of valid frames captured.
    public mutating func capture(
        thread: mach_port_t,
        using captureBacktrace: (mach_port_t, UnsafeMutablePointer<UInt>, Int32) -> Int32
    ) {
        addressCount = withUnsafeMutableBytes(of: &storage) { ptr in
            Int(
                captureBacktrace(
                    thread,
                    ptr.baseAddress!.assumingMemoryBound(to: UInt.self),
                    Int32(Self.capacity)
                ))
        }
    }

    /// Creates a new zero-initialized sample instance.
    public static func make() -> Self {
        Self()
    }
}

// MARK: - Metadata

/// Timing metadata for a captured sample.
///
/// Contains timestamps that mark the beginning and end of the backtrace capture operation.
///
/// - `timestampBeginNs`: When backtrace capture began.
/// - `timestampEndNs`: When backtrace capture completed.
/// - `durationNs`: Time spent capturing the backtrace (computed).
public struct SampleMetadata: Sendable {
    /// Monotonic timestamp when backtrace capture began (nanoseconds from `CLOCK_UPTIME_RAW`).
    public var timestampBeginNs: UInt64 = 0

    /// Monotonic timestamp when backtrace capture completed (nanoseconds from `CLOCK_UPTIME_RAW`).
    public var timestampEndNs: UInt64 = 0

    /// Duration of the backtrace capture in nanoseconds.
    public var durationNs: UInt64 { timestampEndNs &- timestampBeginNs }

    public init() {}
}

// MARK: - Concrete Sample Types

/// A sample with storage for up to 32 frames (shallow stacks).
public struct Sample32: Sample {
    public static let capacity = 32
    public var addressCount: Int = 0
    public var metadata = SampleMetadata()
    public var storage: Storage32 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
    public init() {}
}

/// A sample with storage for up to 64 frames (common case).
public struct Sample64: Sample {
    public static let capacity = 64
    public var addressCount: Int = 0
    public var metadata = SampleMetadata()
    public var storage: Storage64 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
    public init() {}
}

/// A sample with storage for up to 128 frames (deep stacks).
public struct Sample128: Sample {
    public static let capacity = 128
    public var addressCount: Int = 0
    public var metadata = SampleMetadata()
    public var storage: Storage128 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
    public init() {}
}

/// A sample with storage for up to 256 frames (very deep stacks).
public struct Sample256: Sample {
    public static let capacity = 256
    public var addressCount: Int = 0
    public var metadata = SampleMetadata()
    public var storage: Storage256 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
    public init() {}
}

/// A sample with storage for up to 512 frames (extremely deep stacks).
public struct Sample512: Sample {
    public static let capacity = 512
    public var addressCount: Int = 0
    public var metadata = SampleMetadata()
    public var storage: Storage512 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
    public init() {}
}

// MARK: - Storage Typealiases

public typealias Storage32 = (
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt
)

public typealias Storage64 = (
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt
)

public typealias Storage128 = (
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt
)

public typealias Storage256 = (
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt
)

public typealias Storage512 = (
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt,
    UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt
)
