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

import CrashTriggers
import Foundation
import KSCrashRecording

public struct UserReportConfig: Codable {
    public struct UserException: Codable {
        public var name: String
        public var reason: String?
        public var language: String?
        public var lineOfCode: String?
        public var stacktrace: [String]?
        public var logAllThreads: Bool
        public var terminateProgram: Bool

        public init(
            name: String,
            reason: String? = nil,
            language: String? = nil,
            lineOfCode: String? = nil,
            stacktrace: [String]? = nil,
            logAllThreads: Bool = false,
            terminateProgram: Bool = false
        ) {
            self.name = name
            self.reason = reason
            self.language = language
            self.lineOfCode = lineOfCode
            self.stacktrace = stacktrace
            self.logAllThreads = logAllThreads
            self.terminateProgram = terminateProgram
        }
    }

    public struct NSExceptionReport: Codable {
        public var name: String
        public var reason: String?
        public var userInfo: [String: String]?
        public var logAllThreads: Bool
        public var addStacktrace: Bool

        public init(
            name: String,
            reason: String? = nil,
            userInfo: [String: String]? = nil,
            logAllThreads: Bool = false,
            addStacktrace: Bool = false
        ) {
            self.name = name
            self.reason = reason
            self.userInfo = userInfo
            self.logAllThreads = logAllThreads
            self.addStacktrace = addStacktrace
        }
    }

    public var userException: UserException?
    public var nsException: NSExceptionReport?

    public init(userException: UserException? = nil, nsException: NSExceptionReport? = nil) {
        self.userException = userException
        self.nsException = nsException
    }
}

extension UserReportConfig {
    func report() {
        userException?.report()
        nsException?.report()
    }
}

extension UserReportConfig.UserException {
    func report() {
        KSCrash.shared.reportUserException(
            name,
            reason: reason,
            language: language,
            lineOfCode: lineOfCode,
            stackTrace: stacktrace,
            logAllThreads: logAllThreads,
            terminateProgram: terminateProgram
        )
    }
}

extension UserReportConfig.NSExceptionReport {
    func report() {
        var exception = NSException(
            name: .init(rawValue: name),
            reason: reason,
            userInfo: userInfo
        )
        if addStacktrace {
            exception = CrashTriggersHelper.exceptionWithStacktrace(for: exception)
        }
        KSCrash.shared.report(exception, logAllThreads: logAllThreads)
    }
}
