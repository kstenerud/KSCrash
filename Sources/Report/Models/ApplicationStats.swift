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
public struct ApplicationStats: Decodable, Sendable {
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
    }
}
