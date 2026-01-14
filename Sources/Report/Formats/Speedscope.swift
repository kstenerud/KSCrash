//
//  Speedscope.swift
//
//  Created by Alexander Cohen on 2025-01-06.
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

/// Root structure for the Speedscope file format.
///
/// Speedscope is a web-based flame graph viewer that accepts JSON files
/// conforming to this schema. Files can be opened at https://speedscope.app
///
/// See: https://www.speedscope.app/file-format-schema.json
public struct Speedscope: Encodable, Sendable {
    /// JSON schema URL for validation.
    public let schema: String

    /// Name of this profile file.
    public let name: String

    /// Tool that generated this file.
    public let exporter: String

    /// Shared data referenced by profiles.
    public let shared: Shared

    /// Array of profile data.
    public let profiles: [Profile]

    /// Index of the initially active profile.
    public let activeProfileIndex: Int

    public init(
        schema: String = "https://www.speedscope.app/file-format-schema.json",
        name: String,
        exporter: String,
        shared: Shared,
        profiles: [Profile],
        activeProfileIndex: Int = 0
    ) {
        self.schema = schema
        self.name = name
        self.exporter = exporter
        self.shared = shared
        self.profiles = profiles
        self.activeProfileIndex = activeProfileIndex
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case name
        case exporter
        case shared
        case profiles
        case activeProfileIndex
    }

    // MARK: - Value Unit

    /// Unit of measurement for profile values.
    public enum ValueUnit: String, Encodable, Sendable {
        case bytes
        case microseconds
        case milliseconds
        case nanoseconds
        case none
        case seconds
    }

    // MARK: - Profile Type

    /// Type of profile data collection.
    public enum ProfileType: String, Encodable, Sendable {
        /// Event-based profiling with explicit open/close events.
        case evented
        /// Sampling-based profiling with periodic snapshots.
        case sampled
    }

    // MARK: - Shared

    /// Shared data in a Speedscope file.
    public struct Shared: Encodable, Sendable {
        /// Array of unique frames referenced by all profiles.
        public let frames: [Frame]

        public init(frames: [Frame]) {
            self.frames = frames
        }
    }

    // MARK: - Frame

    /// A single frame in a Speedscope profile.
    public struct Frame: Encodable, Sendable {
        /// Symbol name or address.
        public let name: String

        /// Source file or binary image name.
        public let file: String?

        /// Line number in source code.
        public let line: Int?

        /// Column number in source code.
        public let col: Int?

        public init(name: String, file: String? = nil, line: Int? = nil, col: Int? = nil) {
            self.name = name
            self.file = file
            self.line = line
            self.col = col
        }
    }

    // MARK: - Profile

    /// A sampled profile in Speedscope format.
    public struct Profile: Encodable, Sendable {
        /// Type of profile data collection.
        public let type: ProfileType

        /// Name of this profile.
        public let name: String

        /// Unit of measurement for all values.
        public let unit: ValueUnit

        /// Start value in the specified `unit`.
        public let startValue: UInt64

        /// End value in the specified `unit`.
        public let endValue: UInt64

        /// Array of samples, each containing frame indices.
        public let samples: [[Int]]

        /// Size of each sample in the specified `unit`.
        public let weights: [UInt64]

        public init(
            type: ProfileType = .sampled,
            name: String,
            unit: ValueUnit,
            startValue: UInt64,
            endValue: UInt64,
            samples: [[Int]],
            weights: [UInt64]
        ) {
            self.type = type
            self.name = name
            self.unit = unit
            self.startValue = startValue
            self.endValue = endValue
            self.samples = samples
            self.weights = weights
        }
    }
}
