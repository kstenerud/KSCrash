//
//  ReportSource.swift
//
//  Created by Alexander Cohen on 2026-09-26.
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
import KSCrashReportModel

/// Somewhere outside this install that holds finished reports for the send to take in.
///
/// Before it lists the store, `sendReports` makes one reader from each source in
/// `SendConfiguration.reportSources` and takes their reports into the store one at a time.
/// From then on they are the store's reports and are sent like any other.
public protocol ReportSource: Sendable {
    associatedtype Reader: ReportReader

    /// A fresh pass over the reports waiting now. Called once for each send that takes
    /// reports in.
    func makeReader() -> Reader
}

/// One pass over a source's waiting reports, used by one send from one task.
public protocol ReportReader {
    /// The next report, or nil when this pass has none left. Called again only after the
    /// previous report was finished. A throw ends the pass for this send; the store's own
    /// reports and other sources are unaffected. Sends take turns taking reports in, so
    /// return promptly: a slow reader holds up every send waiting behind it.
    mutating func next() async throws -> IncomingReport?

    /// Called once for each report `next()` returned, before `next()` is called again.
    mutating func finish(_ report: IncomingReport, as disposition: IncomingReport.Disposition) async
}

/// A report offered to the store by a `ReportReader`.
public struct IncomingReport: Sendable {
    public enum Content: Sendable {
        /// A report file, which the store moves in. One on another volume is copied instead,
        /// and stays where it is for the reader to remove on `.taken`. A report the reader
        /// cannot give up as a file goes as `.data`.
        case file(URL)
        /// A report held in memory.
        case data(Data)
    }

    public enum Disposition: Sendable, Equatable {
        /// The store holds the report. The reader may delete its copy.
        case taken
        /// The store did not take the report this time. The reader keeps it and offers it
        /// on a later send, not again during this one.
        case retryLater
    }

    public var content: Content

    /// The report's id, the `report.id` inside it. The store files the report under this
    /// id and does not check it against the content.
    public var id: Report.ID

    /// When the report was written. Orders it among the store's reports.
    public var timestamp: Date

    public init(content: Content, id: Report.ID, timestamp: Date) {
        self.content = content
        self.id = id
        self.timestamp = timestamp
    }
}
