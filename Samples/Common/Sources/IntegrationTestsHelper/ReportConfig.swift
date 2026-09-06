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
import KSCrash
import Logging

public struct ReportConfig: Codable {
    public var directoryPath: String

    public init(directoryPath: String) {
        self.directoryPath = directoryPath
    }
}

extension ReportConfig {
    /// Returns once every delivered report is on disk, so the runner's
    /// completion marker means "the reports are there".
    func report() async {
        let url = URL(fileURLWithPath: directoryPath)
        let configuration = SendConfiguration(
            reportPipeline: [AnyPipelineStage(DirectoryStage(directoryUrl: url))]
        )
        _ = try? await KSCrash.shared.sendReports(with: configuration)
    }
}

/// Terminal stage: writes each delivered report's JSON into the directory,
/// where the integration tests pick it up.
struct DirectoryStage: PipelineStage {
    private static let logger = Logger(label: "DirectoryStage")

    let directoryUrl: URL

    func process(_ payload: Report) async throws -> Report? {
        let fileName = "\(payload.report.id)-\(UUID().uuidString).ips"
        let fileUrl = directoryUrl.appendingPathComponent(fileName)
        do {
            try JSONEncoder().encode(payload).write(to: fileUrl)
        } catch {
            Self.logger.error("Failed to save report: \(error)")
            throw error
        }
        return payload
    }
}
