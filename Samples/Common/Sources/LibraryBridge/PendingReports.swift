//
//  PendingReports.swift
//
//  Created by Alexander Cohen on 2026-08-25.
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
import Logging

/// The pending reports on disk, read straight from the install's reports
/// directory. Reads only; reports stay on disk.
public struct PendingReports {
    private static let logger = Logger(label: "ReportingSample")

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var count: Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).count
    }

    private func reportFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// Log a short model-level summary of every pending report.
    public func logToConsole() {
        for url in reportFiles() {
            guard let data = try? Data(contentsOf: url) else { continue }
            let summary =
                (try? JSONDecoder().decode(Report.self, from: data))
                .map { String(describing: $0.crash.error.type) } ?? "undecodable"
            Self.logger.info("Report \(url.lastPathComponent): \(summary) (\(data.count) bytes)")
        }
    }

    /// Dump each pending report's raw JSON.
    public func logRawToConsole() {
        for url in reportFiles() {
            guard let data = try? Data(contentsOf: url),
                let json = String(data: data, encoding: .utf8)
            else { continue }
            Self.logger.info("Report \(url.lastPathComponent):\n\(json)")
        }
    }
}

extension KSCrash {
    /// Sample: run every pending report through a logging pipeline stage.
    public func sampleLogToConsole() {
        Task { @MainActor in
            let configuration = SendConfiguration(reportPipeline: [
                AnyPipelineStage(SampleLogStage()),
                AnyPipelineStage(KeepOnDiskStage()),
            ])
            _ = try? await KSCrash.shared.sendReports(with: configuration)
        }
    }
}
