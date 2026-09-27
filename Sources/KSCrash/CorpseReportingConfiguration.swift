//
//  CorpseReportingConfiguration.swift
//
//  Created by Alexander Cohen on 2026-09-05.
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

/// A shared report area: a crash extension installs into it, and the app's send pulls
/// reports out of it.
///
/// The extension passes a value to `installForCorpseReporting(with:)`; the app lists
/// the same value in `SendConfiguration.reportSources`. Both sides derive the on-disk
/// layout from it identically, so they cannot disagree about where reports live.
public struct CorpseReportingConfiguration: Sendable, Equatable {

    /// The install namespace shared with the app.
    public var namespace: String

    /// Where the shared area lives. `.appGroup` in production; sharing between an app and
    /// its extensions is always through a common container.
    public var container: Container

    public init(namespace: String, container: Container) {
        self.namespace = namespace
        self.container = container
    }
}

extension CorpseReportingConfiguration {
    /// The directory whose bundle-id subdirectories are per-process install roots.
    package var namespaceRoot: URL {
        get throws { try container.namespaceRoot(for: namespace) }
    }

    /// This process's install root inside the area.
    package var processRoot: URL {
        get throws { try container.processRoot(for: namespace) }
    }

    /// The Reports directory of every store in the area that hands its reports over, other
    /// than this process's own: one per bundle-id subdirectory.
    ///
    /// A store is a source only when it says so, in the manifest its own install wrote. A
    /// corpse-reporting store publishes each report whole and keeps nothing beside it, so
    /// another process may take one. A normal install sharing the container (a widget, say)
    /// writes reports in place and keeps their sidecars and run data in its own store, so
    /// taking its files would tear a write and strand the rest. An area that does not exist
    /// yet has none.
    func drainableReportsDirectories() throws -> [URL] {
        let root = try namespaceRoot
        let own = try processRoot.standardizedFileURL.path
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        } catch  where Store.isNoSuchFile(error) {
            // Nothing has installed into the area yet.
            return []
        }
        return entries.sorted().compactMap { entry in
            let processRoot = root.appendingPathComponent(entry, isDirectory: true)
            guard processRoot.standardizedFileURL.path != own,
                StoreManifest.read(atProcessRoot: processRoot)?.isDrainable == true
            else { return nil }
            let reports = processRoot.appendingPathComponent(KSCRS_DEFAULT_REPORTS_FOLDER, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: reports.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { return nil }
            return reports
        }
    }
}

extension CorpseReportingConfiguration: ReportSource {
    public func makeReader() -> Reader {
        Reader(area: self)
    }

    /// One pass over the reports waiting in the area, one report file at a time.
    public struct Reader: ReportReader {
        private let area: CorpseReportingConfiguration
        private var directories: [URL]?
        /// The report names in the directory being taken, read before any of
        /// them is handed out.
        private var names: [String] = []
        private var directory: URL?

        init(area: CorpseReportingConfiguration) {
            self.area = area
        }

        public mutating func next() async throws -> IncomingReport? {
            if directories == nil {
                // Throws when the area does not resolve (an app group this
                // process is not entitled to), which ends the pass.
                directories = try area.drainableReportsDirectories()
            }
            while true {
                // Order does not matter: the store keeps the newest reports
                // whatever order they arrive in.
                while let directory, let name = names.popLast() {
                    guard let id = Store.ReportFilename.reportID(in: name),
                        let ns = Store.ReportFilename.timestampNs(in: name)
                    else { continue }
                    let url = directory.appendingPathComponent(name)
                    return IncomingReport(
                        content: .file(url), id: id,
                        timestamp: Date(timeIntervalSince1970: Double(ns) / 1_000_000_000))
                }
                guard let next = directories?.first else { return nil }
                directories?.removeFirst()
                // Every name is read before any report leaves the directory:
                // the store moves reports out of it, and removing entries while
                // a directory is being read is unspecified and can skip some.
                // Names only, never the reports, so a backlog costs little.
                do {
                    names = try FileManager.default.contentsOfDirectory(atPath: next.path)
                    directory = next
                } catch {
                    // Its reports stay where they are for a later send.
                    Store.log("Could not list a crash extension's reports", next, error)
                    names = []
                    directory = nil
                }
            }
        }

        public mutating func finish(_ report: IncomingReport, as disposition: IncomingReport.Disposition) async {
            // A moved report is already gone. One the store copied, or already
            // held, is still here and is now redundant.
            guard disposition == .taken, case .file(let url) = report.content else { return }
            Store.remove(url, reason: "a report the store already holds")
        }
    }
}
