//
//  ReportConfig.swift
//
//  Created by Nikolay Volosatov on 2024-08-11.
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
import KSCrashFilters
import KSCrashRecording
import KSCrashSinks
import Logging

public struct ReportConfig: Codable {
    public var directoryPath: String

    public init(directoryPath: String) {
        self.directoryPath = directoryPath
    }
}

extension ReportConfig {
    func report() {
        let url = URL(fileURLWithPath: directoryPath)
        guard let store = KSCrash.shared.reportStore else {
            return
        }
        store.sink = CrashReportFilterPipeline(filters: [
            CrashReportFilterAppleFmt(),
            DirectorySink(url),
        ])
        store.sendAllReports()
    }
}

public class DirectorySink: NSObject, CrashReportFilter {
    private static let logger = Logger(label: "DirectorySink")

    private let directoryUrl: URL

    public init(_ directoryUrl: URL) {
        self.directoryUrl = directoryUrl
    }

    public func filterReports(
        _ reports: [any CrashReport], onCompletion: (([any CrashReport]?, (any Error)?) -> Void)? = nil
    ) {
        let prefix = UUID().uuidString
        for (idx, report) in reports.enumerated() {
            let fileName = "\(prefix)-\(idx).ips"
            let fileUrl = directoryUrl.appendingPathComponent(fileName)

            let data: Data
            if let stringReport = report as? CrashReportString {
                data = stringReport.value.data(using: .utf8)!
            } else if let dataReport = report as? CrashReportData {
                data = dataReport.value
            } else {
                continue
            }

            do {
                try data.write(to: fileUrl)
            } catch {
                Self.logger.error("Failed to save report: \(error)")
            }
        }
        onCompletion?(reports, nil)
    }
}
