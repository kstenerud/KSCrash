//
//  CorpseArea.swift
//
//  Created by Alexander Cohen on 2026-09-19.
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
import KSCrash

/// The app's half of the two-target integration.
///
/// This is deliberately a separate declaration from the extension's, built from
/// the same app group rather than from a shared constant. The two processes are
/// built and signed independently in a real integration, and the only thing that
/// makes them agree is that both derive the same area from the same group. A
/// shared constant would paper over a mismatch that a real app would hit.
enum CorpseArea {
    static let appGroup = "group.com.github.kstenerud.KSCrash.Corpse"
    static let namespace = "KSCrashCorpseTests"

    static var configuration: CorpseReportingConfiguration {
        CorpseReportingConfiguration(namespace: namespace, container: .appGroup(appGroup))
    }
}

/// How the UI test drives the app. Everything the app does is decided by launch
/// arguments, because the test has to control a process that is about to die and
/// then inspect what a *later* launch makes of it.
enum LaunchPlan {
    /// Install, then die in the requested way.
    case crash(trigger: String)
    /// Install, drain the extension's area, send, and publish a verdict.
    case verify
    /// Neither: the app just sits there.
    case idle

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchPlan {
        if let index = arguments.firstIndex(of: "--corpse-crash"), index + 1 < arguments.count {
            return .crash(trigger: arguments[index + 1])
        }
        if arguments.contains("--corpse-verify") {
            return .verify
        }
        return .idle
    }
}
