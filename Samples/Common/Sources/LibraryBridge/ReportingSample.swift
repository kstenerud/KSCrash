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
        KSCrash.shared.sink = CrashReportSinkConsole.filter().defaultCrashReportFilterSet()
        KSCrash.shared.sendAllReports { reports, isSuccess, error in
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

    public static func sampleLogToConsole() {
        KSCrash.shared.sink = CrashReportFilterPipeline(filtersArray: [
            SampleFilter(),
            SampleSink(),
        ])
        KSCrash.shared.sendAllReports()
    }
}

public class SampleCrashReport: NSObject, CrashReport {
    public struct CrashedThread {
        var index: Int
        var callStack: [String]
    }

    public var untypedValue: Any? { crashedThread }

    public let crashedThread: CrashedThread

    public init?(_ report: CrashReportDictionary) {
        guard let crashDict = report.value[CrashField.crash.rawValue] as? Dictionary<String, Any>,
              let threadsArr = crashDict[CrashField.threads.rawValue] as? Array<Any>,
              let crashedThreadDict = threadsArr
                .compactMap({ $0 as? Dictionary<String, Any> })
                .first(where: { ($0[CrashField.crashed.rawValue] as? Bool) ?? false }),
              let crashedThreadIndex = crashedThreadDict[CrashField.index.rawValue] as? Int,
              let backtrace = crashedThreadDict[CrashField.backtrace.rawValue] as? Dictionary<String, Any>,
              let backtraceArr = backtrace[CrashField.contents.rawValue] as? Array<Any>
        else { return nil }

        crashedThread = .init(
            index: crashedThreadIndex,
            callStack: backtraceArr.enumerated().map { (idx: Int, bt: Any) -> String in
                guard let bt = bt as? Dictionary<String, Any>,
                      let objectName = bt[CrashField.objectName.rawValue] as? String,
                      let instructionAddr = bt[CrashField.instructionAddr.rawValue] as? UInt64
                else { return "\(idx)\t<malformed>" }

                let symbolName = bt[CrashField.symbolName.rawValue] as? String
                let symbolAddr = bt[CrashField.symbolAddr.rawValue] as? UInt64
                let offset = symbolAddr.flatMap { instructionAddr - $0 } ?? 0
                
                let instructionAddrStr = "0x\(String(instructionAddr, radix: 16))"
                let symbolAddrStr = "0x\(String(symbolAddr ?? instructionAddr, radix: 16))"

                return "\(idx)\t\(objectName)\t\(instructionAddrStr) \(symbolName ?? symbolAddrStr) + \(offset)"
            }
        )
    }
}

public class SampleFilter: NSObject, CrashReportFilter {
    public func filterReports(_ reports: [any CrashReport], onCompletion: (([any CrashReport]?, Bool, (any Error)?) -> Void)? = nil) {
        let filtered = reports.compactMap { report -> SampleCrashReport? in
            guard let dictReport = report as? CrashReportDictionary else {
                return nil
            }
            return SampleCrashReport(dictReport)
        }
        onCompletion?(filtered, true, nil)
    }
}

public class SampleSink: NSObject, CrashReportFilter {
    public func filterReports(_ reports: [any CrashReport], onCompletion: (([any CrashReport]?, Bool, (any Error)?) -> Void)? = nil) {
        for (idx, report) in reports.enumerated() {
            guard let sampleReport = report as? SampleCrashReport else {
                continue
            }
            let lines = [
                "Crash report #\(idx):",
                "\tCrashed thread #\(sampleReport.crashedThread.index):",
            ] + sampleReport.crashedThread.callStack.map { "\t\t\($0)" }
            print(lines.joined(separator: "\n"))
        }
        onCompletion?(reports, true, nil)
    }
}
