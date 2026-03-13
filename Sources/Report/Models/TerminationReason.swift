//
//  TerminationReason.swift
//
//  Created by Alexander Cohen on 2026-03-07.
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

/// The reason a process was terminated.
public enum TerminationReason: RawRepresentable, Codable, Sendable, Equatable {
    // Expected exits
    case clean
    case crash
    case hang
    case firstLaunch
    // Resource reasons
    case lowBattery
    case memoryLimit
    case memoryPressure
    case thermal
    case cpu
    // System change reasons
    case osUpgrade
    case appUpgrade
    case reboot
    // Fallback
    case unexplained
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "clean": self = .clean
        case "crash": self = .crash
        case "hang": self = .hang
        case "first_launch": self = .firstLaunch
        case "low_battery": self = .lowBattery
        case "memory_limit": self = .memoryLimit
        case "memory_pressure": self = .memoryPressure
        case "thermal": self = .thermal
        case "cpu": self = .cpu
        case "os_upgrade": self = .osUpgrade
        case "app_upgrade": self = .appUpgrade
        case "reboot": self = .reboot
        case "unexplained": self = .unexplained
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .clean: return "clean"
        case .crash: return "crash"
        case .hang: return "hang"
        case .firstLaunch: return "first_launch"
        case .lowBattery: return "low_battery"
        case .memoryLimit: return "memory_limit"
        case .memoryPressure: return "memory_pressure"
        case .thermal: return "thermal"
        case .cpu: return "cpu"
        case .osUpgrade: return "os_upgrade"
        case .appUpgrade: return "app_upgrade"
        case .reboot: return "reboot"
        case .unexplained: return "unexplained"
        case .unknown(let value): return value
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}
