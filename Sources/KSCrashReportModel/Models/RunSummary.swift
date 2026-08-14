//
//  RunSummary.swift
//
//  Created by Alexander Cohen on 2026-08-02.
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

/// Per-run stability/telemetry record describing one completed process run.
public struct RunSummary: Codable, Sendable, Equatable {
    /// Kind of host process that produced a run summary.
    public enum HostKind: RawRepresentable, Codable, Sendable, Equatable {
        case app
        case `extension`
        case xctest
        case other
        case unknown(String)

        public init(rawValue: String) {
            switch rawValue {
            case "app": self = .app
            case "extension": self = .extension
            case "xctest": self = .xctest
            case "other": self = .other
            default: self = .unknown(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .app: return "app"
            case .extension: return "extension"
            case .xctest: return "xctest"
            case .other: return "other"
            case .unknown(let value): return value
            }
        }

        public var isUnknown: Bool {
            if case .unknown = self { return true }
            return false
        }
    }

    /// The classified outcome of the run.
    public struct Outcome: Codable, Sendable, Equatable {
        /// Why the run ended.
        public let terminationReason: TerminationReason

        /// Whether the run was user-perceptible (foreground) at termination.
        public let userPerceptible: Bool

        public init(terminationReason: TerminationReason, userPerceptible: Bool) {
            self.terminationReason = terminationReason
            self.userPerceptible = userPerceptible
        }

        enum CodingKeys: String, CodingKey {
            case terminationReason = "termination_reason"
            case userPerceptible = "user_perceptible"
        }
    }

    /// Time the run spent active versus backgrounded.
    public struct Durations: Codable, Sendable, Equatable {
        /// Milliseconds spent active (foreground).
        public let activeMs: Int64

        /// Milliseconds spent backgrounded.
        public let backgroundMs: Int64

        public init(activeMs: Int64, backgroundMs: Int64) {
            self.activeMs = activeMs
            self.backgroundMs = backgroundMs
        }

        enum CodingKeys: String, CodingKey {
            case activeMs = "active"
            case backgroundMs = "background"
        }
    }

    /// One contiguous segment of the run at a single (perceptibility, user) setting.
    public struct Session: Codable, Sendable, Equatable {
        /// This session's id.
        public let sessionID: String

        /// The user id active during the session, or nil when anonymous.
        public let userID: String?

        /// Whether the session was user-perceptible (foreground).
        public let perceptible: Bool

        /// Unix epoch milliseconds (wall clock).
        public let startedAtMs: Int64

        /// Unix epoch milliseconds (wall clock).
        public let endedAtMs: Int64

        public init(
            sessionID: String,
            userID: String? = nil,
            perceptible: Bool,
            startedAtMs: Int64,
            endedAtMs: Int64
        ) {
            self.sessionID = sessionID
            self.userID = userID
            self.perceptible = perceptible
            self.startedAtMs = startedAtMs
            self.endedAtMs = endedAtMs
        }

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case userID = "user_id"
            case perceptible
            case startedAtMs = "started_at_ms"
            case endedAtMs = "ended_at_ms"
        }
    }

    /// The individual sessions recorded this run.
    public struct Sessions: Codable, Sendable, Equatable {
        /// The individual sessions recorded this run, oldest first.
        public let records: [Session]

        public init(records: [Session]) {
            self.records = records
        }

        enum CodingKeys: String, CodingKey {
            case records
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            records = try container.decodeIfPresent([Session].self, forKey: .records) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if !records.isEmpty {
                try container.encode(records, forKey: .records)
            }
        }
    }

    /// Identity of the app that produced the run.
    public struct App: Codable, Sendable, Equatable {
        public let bundleID: String
        public let version: String
        public let shortVersion: String
        public let hostKind: HostKind

        /// How the producing process was built and distributed (app store,
        /// debug, simulator, ...). nil when the run recorded none.
        public let buildType: BuildType?

        public init(
            bundleID: String, version: String, shortVersion: String, hostKind: HostKind,
            buildType: BuildType? = nil
        ) {
            self.bundleID = bundleID
            self.version = version
            self.shortVersion = shortVersion
            self.hostKind = hostKind
            self.buildType = buildType
        }

        enum CodingKeys: String, CodingKey {
            case bundleID = "bundle_id"
            case version
            case shortVersion = "short_version"
            case hostKind = "host_kind"
            case buildType = "build_type"
        }
    }

    /// Operating system that ran the process.
    public struct OS: Codable, Sendable, Equatable {
        public let name: String
        public let version: String
        public let build: String

        public init(name: String, version: String, build: String) {
            self.name = name
            self.version = version
            self.build = build
        }

        enum CodingKeys: String, CodingKey {
            case name
            case version
            case build
        }
    }

    /// Device that ran the process.
    public struct Device: Codable, Sendable, Equatable {
        public let model: String
        public let modelFamily: String
        public let architecture: String
        public let binaryArchitecture: String
        public let isTranslated: Bool
        public let isJailbroken: Bool

        public init(
            model: String,
            modelFamily: String,
            architecture: String,
            binaryArchitecture: String,
            isTranslated: Bool,
            isJailbroken: Bool
        ) {
            self.model = model
            self.modelFamily = modelFamily
            self.architecture = architecture
            self.binaryArchitecture = binaryArchitecture
            self.isTranslated = isTranslated
            self.isJailbroken = isJailbroken
        }

        enum CodingKeys: String, CodingKey {
            case model
            case modelFamily = "model_family"
            case architecture
            case binaryArchitecture = "binary_architecture"
            case isTranslated = "is_translated"
            case isJailbroken = "is_jailbroken"
        }
    }

    /// Schema version of this summary.
    public let schemaVersion: Int

    /// Version of the SDK that produced the summary.
    public let sdkVersion: String

    /// The per-run UUID.
    public let runID: String

    /// Stable per-install device identifier.
    public let deviceID: String

    /// The user ID active at termination, or nil when no user was active.
    public let userID: String?

    /// Unix epoch milliseconds (wall clock).
    public let startedAtMs: Int64

    /// Unix epoch milliseconds (wall clock).
    public let endedAtMs: Int64

    /// Whether a debugger was attached during the run.
    public let isBeingDebugged: Bool

    public let outcome: Outcome
    public let durations: Durations
    public let sessions: Sessions
    public let app: App
    public let os: OS
    public let device: Device

    /// App-supplied metadata, stitched in at send from the run's userInfo stitch file.
    public let metadata: Metadata?

    public init(
        schemaVersion: Int,
        sdkVersion: String,
        runID: String,
        deviceID: String,
        userID: String? = nil,
        startedAtMs: Int64,
        endedAtMs: Int64,
        isBeingDebugged: Bool,
        outcome: Outcome,
        durations: Durations,
        sessions: Sessions,
        app: App,
        os: OS,
        device: Device,
        metadata: Metadata? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sdkVersion = sdkVersion
        self.runID = runID
        self.deviceID = deviceID
        self.userID = userID
        self.startedAtMs = startedAtMs
        self.endedAtMs = endedAtMs
        self.isBeingDebugged = isBeingDebugged
        self.outcome = outcome
        self.durations = durations
        self.sessions = sessions
        self.app = app
        self.os = os
        self.device = device
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sdkVersion = "sdk_version"
        case runID = "run_id"
        case deviceID = "device_id"
        case userID = "user_id"
        case startedAtMs = "started_at_ms"
        case endedAtMs = "ended_at_ms"
        case isBeingDebugged = "is_being_debugged"
        case outcome
        case durations = "durations_ms"
        case sessions
        case app
        case os
        case device
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        sdkVersion = try container.decode(String.self, forKey: .sdkVersion)
        runID = try container.decode(String.self, forKey: .runID)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        startedAtMs = try container.decode(Int64.self, forKey: .startedAtMs)
        endedAtMs = try container.decode(Int64.self, forKey: .endedAtMs)
        isBeingDebugged = try container.decodeIfPresent(Bool.self, forKey: .isBeingDebugged) ?? false
        outcome = try container.decode(Outcome.self, forKey: .outcome)
        durations = try container.decode(Durations.self, forKey: .durations)
        sessions = try container.decode(Sessions.self, forKey: .sessions)
        app = try container.decode(App.self, forKey: .app)
        os = try container.decode(OS.self, forKey: .os)
        device = try container.decode(Device.self, forKey: .device)
        metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sdkVersion, forKey: .sdkVersion)
        try container.encode(runID, forKey: .runID)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encodeIfPresent(userID, forKey: .userID)
        try container.encode(startedAtMs, forKey: .startedAtMs)
        try container.encode(endedAtMs, forKey: .endedAtMs)
        try container.encode(isBeingDebugged, forKey: .isBeingDebugged)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(durations, forKey: .durations)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(app, forKey: .app)
        try container.encode(os, forKey: .os)
        try container.encode(device, forKey: .device)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}
