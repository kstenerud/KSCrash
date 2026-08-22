//
//  Monitors.swift
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

import KSCrashRecording

/// The crash detectors an install enables. The infrastructure monitors and
/// user-reported exceptions are always on and are not part of the set.
public struct Monitors: OptionSet, Sendable, Hashable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Mach kernel exceptions.
    public static let machExceptions = Monitors(rawValue: MonitorType.machException.rawValue)
    /// Fatal signals.
    public static let signals = Monitors(rawValue: MonitorType.signal.rawValue)
    /// Uncaught C++ exceptions.
    public static let cppExceptions = Monitors(rawValue: MonitorType.cppException.rawValue)
    /// Uncaught NSExceptions.
    public static let nsExceptions = Monitors(rawValue: MonitorType.nsException.rawValue)
    /// Terminations by the system (memory, thermal, watchdog kills), detected at the next launch.
    public static let terminations = Monitors(rawValue: MonitorType.termination.rawValue)
    /// Main-thread hangs, and the hangs that end in a watchdog termination.
    public static let hangs = Monitors(rawValue: MonitorType.hang.rawValue)
    /// Deallocated-object tracking; costs CPU and memory.
    public static let zombies = Monitors(rawValue: MonitorType.zombie.rawValue)

    /// Every detector except `zombies`.
    public static let `default`: Monitors = [
        .machExceptions, .signals, .cppExceptions, .nsExceptions, .terminations, .hangs,
    ]
    /// Every detector.
    public static let all: Monitors = [.default, .zombies]

    var cValue: MonitorType { MonitorType(rawValue: rawValue) }
}
