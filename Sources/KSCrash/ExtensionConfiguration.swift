//
//  ExtensionConfiguration.swift
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
/// The extension passes a value to `installForExtensionReporting(with:)`; the app lists
/// the same value in `SendConfiguration.extensionAreas`. Both sides derive the on-disk
/// layout from it identically, so they cannot disagree about where reports live.
public struct ExtensionConfiguration: Sendable, Equatable {

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

extension ExtensionConfiguration {
    /// The directory whose bundle-id subdirectories are per-process install roots.
    package var namespaceRoot: URL {
        get throws { try container.namespaceRoot(for: namespace) }
    }

    /// This process's install root inside the area.
    package var processRoot: URL {
        get throws {
            let bundleID = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            return try namespaceRoot.appendingPathComponent(bundleID, isDirectory: true)
        }
    }

    /// Every Reports directory in the area other than `excluded` (the caller's own): one per
    /// bundle-id subdirectory. An area that does not exist yet contributes nothing.
    package func reportsDirectories(excluding excluded: URL?) throws -> [URL] {
        let root = try namespaceRoot
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        return entries.sorted().compactMap { entry in
            let reports = root.appendingPathComponent(entry, isDirectory: true)
                .appendingPathComponent("Reports", isDirectory: true)
            if let excluded, reports.standardizedFileURL.path == excluded.standardizedFileURL.path {
                return nil
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: reports.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { return nil }
            return reports
        }
    }
}
