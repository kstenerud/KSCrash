//
//  RunSummary+Codable.swift
//
//  Created by Alexander Cohen on 2026-04-19.
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
import KSCrashRecording

// Codable-backed decode for RunSummary.
//
// Encoding is owned by the ObjC `-[KSCrashRunSummary jsonData]` method —
// single source of truth for the wire schema, callable from both ObjC
// and Swift. This file only provides the decode half, via a private
// `Payload` struct mirroring the wire schema. The ObjC classes are not
// themselves Codable — Swift disallows `init(from:)` on non-final
// ObjC-imported classes without a `required` initializer, and that
// keyword can't be added from an extension. The payload pattern sidesteps
// that restriction without exposing any Swift-only parallel type.

extension RunSummary {
    /// Decode a summary from JSON matching the wire schema.
    public static func decode(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> RunSummary {
        try decoder.decode(Payload.self, from: data).makeRunSummary()
    }
}

// MARK: - Payload (internal wire mirror)

private struct Payload: Codable {
    let schemaVersion: Int
    let sdkVersion: String
    let runID: String
    let deviceID: String
    let userID: String?
    let users: Users
    let startedAtMs: Int64
    let endedAtMs: Int64
    let outcome: Outcome
    let durationsMs: Durations
    let sessions: Sessions
    let app: App
    let os: OSInfo
    let device: Device

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sdkVersion = "sdk_version"
        case runID = "run_id"
        case deviceID = "device_id"
        case userID = "user_id"
        case users = "users"
        case startedAtMs = "started_at_ms"
        case endedAtMs = "ended_at_ms"
        case outcome
        case durationsMs = "durations_ms"
        case sessions
        case app
        case os
        case device
    }

    func makeRunSummary() -> RunSummary {
        RunSummary(
            schemaVersion: schemaVersion,
            sdkVersion: sdkVersion,
            runID: runID,
            deviceID: deviceID,
            userID: userID,
            users: users.makeObjC(),
            startedAtMs: startedAtMs,
            endedAtMs: endedAtMs,
            outcome: outcome.makeObjC(),
            durations: durationsMs.makeObjC(),
            sessions: sessions.makeObjC(),
            app: app.makeObjC(),
            os: os.makeObjC(),
            device: device.makeObjC())
    }
}

// MARK: - Outcome

extension Payload {
    fileprivate struct Outcome: Codable {
        let terminationReason: String
        let cleanShutdown: Bool
        let fatalReported: Bool
        let userPerceptible: Bool

        enum CodingKeys: String, CodingKey {
            case terminationReason = "termination_reason"
            case cleanShutdown = "clean_shutdown"
            case fatalReported = "fatal_reported"
            case userPerceptible = "user_perceptible"
        }

        func makeObjC() -> RunSummary.Outcome {
            RunSummary.Outcome(
                terminationReason: KSCrashRecording.TerminationReason(wireString: terminationReason),
                cleanShutdown: cleanShutdown,
                fatalReported: fatalReported,
                userPerceptible: userPerceptible)
        }
    }
}

// MARK: - Durations

extension Payload {
    fileprivate struct Durations: Codable {
        let active: Int64
        let background: Int64

        func makeObjC() -> RunSummary.Durations {
            RunSummary.Durations(activeMs: active, backgroundMs: background)
        }
    }
}

// MARK: - Sessions

extension Payload {
    fileprivate struct Sessions: Codable {
        let perceptibleCount: Int
        let imperceptibleCount: Int

        enum CodingKeys: String, CodingKey {
            case perceptibleCount = "perceptible_count"
            case imperceptibleCount = "imperceptible_count"
        }

        func makeObjC() -> RunSummary.Sessions {
            RunSummary.Sessions(perceptibleCount: perceptibleCount, imperceptibleCount: imperceptibleCount)
        }
    }
}

// MARK: - Users

extension Payload {
    fileprivate struct Users: Codable {
        let perceptibleCount: Int
        let imperceptibleCount: Int

        enum CodingKeys: String, CodingKey {
            case perceptibleCount = "perceptible_count"
            case imperceptibleCount = "imperceptible_count"
        }

        func makeObjC() -> RunSummary.Users {
            RunSummary.Users(
                perceptibleCount: perceptibleCount,
                imperceptibleCount: imperceptibleCount)
        }
    }
}

// MARK: - App

extension Payload {
    fileprivate struct App: Codable {
        let bundleID: String
        let version: String
        let shortVersion: String
        let hostKind: String

        enum CodingKeys: String, CodingKey {
            case bundleID = "bundle_id"
            case version
            case shortVersion = "short_version"
            case hostKind = "host_kind"
        }

        func makeObjC() -> RunSummary.App {
            RunSummary.App(
                bundleID: bundleID,
                version: version,
                shortVersion: shortVersion,
                hostKind: RunSummary.HostKind(wireString: hostKind))
        }
    }
}

// MARK: - OS

extension Payload {
    fileprivate struct OSInfo: Codable {
        let name: String
        let version: String
        let build: String

        func makeObjC() -> RunSummary.OS {
            RunSummary.OS(name: name, version: version, build: build)
        }
    }
}

// MARK: - Device

extension Payload {
    fileprivate struct Device: Codable {
        let model: String
        let modelFamily: String
        let architecture: String
        let binaryArchitecture: String
        let isTranslated: Bool
        let isJailbroken: Bool

        enum CodingKeys: String, CodingKey {
            case model
            case modelFamily = "model_family"
            case architecture
            case binaryArchitecture = "binary_architecture"
            case isTranslated = "is_translated"
            case isJailbroken = "is_jailbroken"
        }

        func makeObjC() -> RunSummary.Device {
            RunSummary.Device(
                model: model,
                modelFamily: modelFamily,
                architecture: architecture,
                binaryArchitecture: binaryArchitecture,
                isTranslated: isTranslated,
                isJailbroken: isJailbroken)
        }
    }
}

// MARK: - TerminationReason bridging

extension KSCrashRecording.TerminationReason {
    fileprivate init(wireString: String) {
        switch wireString {
        case "clean": self = .clean
        case "crash": self = .crash
        case "hang": self = .hang
        case "first_launch": self = .firstLaunch
        case "os_upgrade": self = .osUpgrade
        case "app_upgrade": self = .appUpgrade
        case "reboot": self = .reboot
        case "low_battery": self = .lowBattery
        case "memory_limit": self = .memoryLimit
        case "memory_pressure": self = .memoryPressure
        case "thermal": self = .thermal
        case "cpu": self = .CPU
        case "unexplained": self = .unexplained
        default: self = .none
        }
    }

}

// MARK: - HostKind bridging

extension RunSummary.HostKind {
    fileprivate init(wireString: String) {
        switch wireString {
        case "app": self = .app
        case "extension": self = .`extension`
        case "xctest": self = .xcTest
        default: self = .other
        }
    }
}
