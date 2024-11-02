//
//  UserReportConfig.swift
//
//  Created by Nikolay Volosatov on 2024-11-02.
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
import CrashTriggers
import KSCrashRecording

public struct UserReportConfig: Codable {
    public enum ReportType: String, Codable {
        case userException
        case nsException
    }

    public var reportType: ReportType

    public init(reportType: ReportType) {
        self.reportType = reportType
    }
}

extension UserReportConfig {
    public static let crashName = "Crash Name"
    public static let crashReason = "Crash Reason"
    public static let crashLanguage = "Crash Language"
    public static let crashLineOfCode = "108"
    public static let crashCustomStacktrace = ["func01", "func02", "func03"]

    func report() {
        switch reportType {
        case .userException:
            KSCrash.shared.reportUserException(
                Self.crashName,
                reason: Self.crashReason,
                language: Self.crashLanguage,
                lineOfCode: Self.crashLineOfCode,
                stackTrace: Self.crashCustomStacktrace,
                logAllThreads: true,
                terminateProgram: false
            )
        case .nsException:
            KSCrash.shared.report(
                CrashTriggersHelper.exceptionWithStacktrace(for: NSException(
                    name: .init(rawValue:Self.crashName),
                    reason: Self.crashReason,
                    userInfo: ["a":"b"]
                )),
                logAllThreads: true
            )
        }
    }
}
