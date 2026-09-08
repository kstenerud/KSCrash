//
//  StoreManifest.swift
//
//  Created by Alexander Cohen on 2026-09-07.
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
import os

/// What a store at a process root is for, written by the process that owns it.
///
/// Processes sharing a container see each other only as directories, so the question that
/// crosses the boundary, whether another process may take these reports, is answered here
/// by the side that knows. A store's own layout never answers it.
package struct StoreManifest: Codable, Equatable {

    package init(schema: Int, kind: String) {
        self.schema = schema
        self.kind = kind
    }

    /// Reports about other processes' corpses. They are complete when they appear, they
    /// carry their own data rather than leaning on this store's sidecars, and they are
    /// meant to be taken: the app that owns the run drains and delivers them.
    package static let corpseKind = "corpse"

    /// Reports about the process that owns this store, which delivers them itself. Nobody
    /// else may take one: it is stitched from sidecars and run data that live here, and a
    /// report moved without them arrives explaining nothing.
    package static let selfKind = "self"

    /// The manifest's own format. A reader that does not know the version leaves the
    /// store alone, the same as one that does not know the kind.
    package static let currentSchema = 1

    package static let filename = "store.json"

    package var schema: Int
    package var kind: String

    /// Whether a process that did not write this store may drain its reports.
    package var isDrainable: Bool { schema == Self.currentSchema && kind == Self.corpseKind }
}

extension StoreManifest {

    /// Declares what the store at `processRoot` is for. Called before the store itself is
    /// created, so an install that cannot declare itself does not leave behind an area
    /// whose reports no one will ever come for.
    package static func write(kind: String, atProcessRoot processRoot: URL) throws {
        try FileManager.default.createDirectory(at: processRoot, withIntermediateDirectories: true)
        let manifest = StoreManifest(schema: currentSchema, kind: kind)
        try JSONEncoder().encode(manifest).write(to: processRoot.appendingPathComponent(filename), options: .atomic)
    }

    /// The declaration at `processRoot`, or nil when there is none, it cannot be read, or
    /// it does not decode. Every one of those means the same thing to a caller: this is
    /// not a store it was invited into.
    package static func read(atProcessRoot processRoot: URL) -> StoreManifest? {
        let url = processRoot.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let manifest = try? JSONDecoder().decode(StoreManifest.self, from: data) else {
            os_log(.error, "Ignoring an unreadable store manifest at %{public}@", processRoot.lastPathComponent)
            return nil
        }
        return manifest
    }
}
