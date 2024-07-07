//
//  ReportingSample.swift
//
//  Created by Nikolay Volosatov on 2024-06-23.
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
import KSCrashRecording
import KSCrashFilters
import KSCrashSinks

public class ReportingSample {
    public static func logToConsole() {
        KSCrash.shared().sink = CrashReportSinkConsole.filter().defaultCrashReportFilterSet()
        KSCrash.shared().sendAllReports { reports, isSuccess, error in
            if isSuccess, let reports {
                print("Logged \(reports.count) reports")
                for (idx, report) in reports.enumerated() {
                    switch report {
                    case let stringReport as CrashReportString:
                        print("Report #\(idx) is a string (length is \(stringReport.value.count))")
                    case let dictionaryReport as CrashReportDictionary:
                        print("Report #\(idx) is a dictionary (number of keys is \(dictionaryReport.value.count))")
                    case let dataReport as CrashReportData:
                        print("Report #\(idx) is a binary data (size is \(dataReport.value.count) bytes)")
                    default:
                        print("Unknown report #\(idx): \(report.debugDescription ?? "?")")
                    }
                }
            } else {
                print("Failed to log reports: \(error?.localizedDescription ?? "")")
            }
        }
    }
}
