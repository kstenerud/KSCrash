//
//  CrashReportStore+Bridge.swift
//
//  Created by Nikolay Volosatov on 2024-08-04.
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

extension CrashReportStore {
    private static let logger = Logger(label: "ReportingSample")

    /// Log a short model-level summary of every pending report. Reads only;
    /// reports stay on disk.
    public func logToConsole() {
        for id in (try? listReportIDs()) ?? [] {
            guard let data = (try? reportData(for: id.int64Value))?.value else { continue }
            let summary =
                (try? JSONDecoder().decode(Report.self, from: data))
                .map { String(describing: $0.crash.error.type) } ?? "undecodable"
            Self.logger.info("Report \(id): \(summary) (\(data.count) bytes)")
        }
    }

    /// Dump each pending report's raw JSON. Reads only; reports stay on disk.
    public func logRawToConsole() {
        for id in (try? listReportIDs()) ?? [] {
            guard let data = (try? reportData(for: id.int64Value))?.value,
                let json = String(data: data, encoding: .utf8)
            else { continue }
            Self.logger.info("Report \(id):\n\(json)")
        }
    }
}

extension KSCrash {
    /// Run every pending report through the sample pipeline, keeping them all
    /// on disk for the next send.
    public func sampleLogToConsole() {
        Task {
            let configuration = SendConfiguration(reportPipeline: [
                AnyPipelineStage(SampleLogStage()),
                AnyPipelineStage(KeepOnDiskStage()),
            ])
            _ = try? await sendReports(with: configuration)
        }
    }
}

/// A custom pipeline stage: formats the crashed thread's call stack from the
/// typed model and logs it, then passes the report on.
public struct SampleLogStage: PipelineStage {
    private static let logger = Logger(label: "SampleLogStage")

    public init() {}

    public func process(_ payload: Report) async throws -> Report? {
        let thread = payload.crash.crashedThread ?? payload.crash.threads?.first(where: { $0.crashed })
        let callStack = (thread?.backtrace?.contents ?? []).enumerated().map { idx, frame -> String in
            let symbol =
                frame.symbolName
                ?? frame.instructionAddr.map { "0x" + String($0, radix: 16) }
                ?? "?"
            return "\t\t\(idx)\t\(frame.objectName ?? "?")\t\(symbol)"
        }
        let lines =
            [
                "Crash report \(payload.report.id):",
                "\tCrashed thread #\((thread?.index).map(String.init) ?? "?"):",
            ] + callStack
        Self.logger.info("\(lines.joined(separator: "\n"))")
        return payload
    }
}

/// Terminal stage that keeps every item on disk: throwing is how a stage
/// leaves a report for a later send instead of consuming it.
public struct KeepOnDiskStage: PipelineStage {
    public struct Kept: Error {}

    public init() {}

    public func process(_ payload: Report) async throws -> Report? {
        throw Kept()
    }
}
