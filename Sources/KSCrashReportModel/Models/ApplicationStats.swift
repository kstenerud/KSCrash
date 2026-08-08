//
//  ApplicationStats.swift
//
//  Created by Alexander Cohen on 2024-12-09.
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

/// Application usage statistics.
public struct ApplicationStats: Codable, Sendable, Equatable {
    /// Time the app was active since the last crash.
    public let activeTimeSinceLastCrash: Double?

    /// Time the app was active since launch.
    public let activeTimeSinceLaunch: Double?

    /// Whether the app is currently active.
    public let applicationActive: Bool?

    /// Whether the app is in the foreground.
    public let applicationInForeground: Bool?

    /// Time the app was in the background since the last crash.
    public let backgroundTimeSinceLastCrash: Double?

    /// Time the app was in the background since launch.
    public let backgroundTimeSinceLaunch: Double?

    /// Number of times the app was launched since the last crash.
    public let launchesSinceLastCrash: Int?

    /// Number of sessions since the last crash.
    public let sessionsSinceLastCrash: Int?

    /// Number of sessions since launch.
    public let sessionsSinceLaunch: Int?

    /// App transition state at the time of the event.
    public let appTransitionState: AppTransitionState?

    /// Whether the user could perceive the app as part of their experience.
    public let userPerceptible: Bool?

    /// The task role at the time of the event.
    public let taskRole: TaskRole?

    enum CodingKeys: String, CodingKey {
        case activeTimeSinceLastCrash = "active_time_since_last_crash"
        case activeTimeSinceLaunch = "active_time_since_launch"
        case applicationActive = "application_active"
        case applicationInForeground = "application_in_foreground"
        case backgroundTimeSinceLastCrash = "background_time_since_last_crash"
        case backgroundTimeSinceLaunch = "background_time_since_launch"
        case launchesSinceLastCrash = "launches_since_last_crash"
        case sessionsSinceLastCrash = "sessions_since_last_crash"
        case sessionsSinceLaunch = "sessions_since_launch"
        case appTransitionState = "app_transition_state"
        case userPerceptible = "user_perceptible"
        case taskRole = "task_role"
    }
}

/// Mach task role assigned by the kernel.
public enum TaskRole: RawRepresentable, Codable, Sendable, Equatable {
    case reniced
    case unspecified
    case foregroundApplication
    case backgroundApplication
    case controlApplication
    case graphicsServer
    case throttleApplication
    case nonUIApplication
    case defaultApplication
    case darwinBGApplication
    case userInitApplication
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "RENICED": self = .reniced
        case "UNSPECIFIED": self = .unspecified
        case "FOREGROUND_APPLICATION": self = .foregroundApplication
        case "BACKGROUND_APPLICATION": self = .backgroundApplication
        case "CONTROL_APPLICATION": self = .controlApplication
        case "GRAPHICS_SERVER": self = .graphicsServer
        case "THROTTLE_APPLICATION": self = .throttleApplication
        case "NONUI_APPLICATION": self = .nonUIApplication
        case "DEFAULT_APPLICATION": self = .defaultApplication
        case "DARWINBG_APPLICATION": self = .darwinBGApplication
        case "USER_INIT_APPLICATION": self = .userInitApplication
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .reniced: return "RENICED"
        case .unspecified: return "UNSPECIFIED"
        case .foregroundApplication: return "FOREGROUND_APPLICATION"
        case .backgroundApplication: return "BACKGROUND_APPLICATION"
        case .controlApplication: return "CONTROL_APPLICATION"
        case .graphicsServer: return "GRAPHICS_SERVER"
        case .throttleApplication: return "THROTTLE_APPLICATION"
        case .nonUIApplication: return "NONUI_APPLICATION"
        case .defaultApplication: return "DEFAULT_APPLICATION"
        case .darwinBGApplication: return "DARWINBG_APPLICATION"
        case .userInitApplication: return "USER_INIT_APPLICATION"
        case .unknown(let value): return value
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

/// App lifecycle transition state.
public enum AppTransitionState: RawRepresentable, Codable, Sendable, Equatable {
    case startup
    case prewarm
    case launching
    case foregrounding
    case active
    case deactivating
    case background
    case terminating
    case exiting
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "startup": self = .startup
        case "prewarm": self = .prewarm
        case "launching": self = .launching
        case "foregrounding": self = .foregrounding
        case "active": self = .active
        case "deactivating": self = .deactivating
        case "background": self = .background
        case "terminating": self = .terminating
        case "exiting": self = .exiting
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .startup: return "startup"
        case .prewarm: return "prewarm"
        case .launching: return "launching"
        case .foregrounding: return "foregrounding"
        case .active: return "active"
        case .deactivating: return "deactivating"
        case .background: return "background"
        case .terminating: return "terminating"
        case .exiting: return "exiting"
        case .unknown(let value): return value
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}
