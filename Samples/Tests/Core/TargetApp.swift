//
//  TargetApp.swift
//
//  Created by Alexander Cohen on 2026-09-27.
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

import Darwin
import Foundation
import XCTest

// The integration tests run on the Mac and drive the Sample app themselves: a child process
// on macOS, `simctl` on a simulator. XCTest never launches or monitors the app, so it never
// goes looking for a system crash report after an intended crash (a race that failed tests
// at random), and there is no UI test runner to fail to start.

/// Where the Sample app runs, from `KSCRASH_IT_PLATFORM`, which has no default: a lane whose
/// setting never reached the tests would otherwise test macOS and pass.
enum TargetPlatform: String, CaseIterable, Sendable {
    case macOS, iOS, tvOS, watchOS, visionOS

    /// nil when `KSCRASH_IT_PLATFORM` is unset or names no platform; every test then fails in
    /// setUp, before anything reads `current`.
    static let configured: TargetPlatform? = ProcessInfo.processInfo.environment["KSCRASH_IT_PLATFORM"].flatMap {
        name in allCases.first { $0.rawValue.lowercased() == name.lowercased() }
    }

    static var current: TargetPlatform { configured! }

    static let simulators: Set<TargetPlatform> = [.iOS, .tvOS, .watchOS, .visionOS]

    /// The build products directory suffix for this platform's simulator build.
    fileprivate var simulatorSDK: String {
        switch self {
        case .macOS: return ""
        case .iOS: return "iphonesimulator"
        case .tvOS: return "appletvsimulator"
        case .watchOS: return "watchsimulator"
        case .visionOS: return "xrsimulator"
        }
    }

    /// The `platform` and device `productFamily` `simctl list -j runtimes` reports.
    fileprivate var simulatorRuntimePlatform: String { self == .visionOS ? "xrOS" : rawValue }
    fileprivate var deviceFamily: String {
        switch self {
        case .macOS: return ""
        case .iOS: return "iPhone"
        case .tvOS: return "Apple TV"
        case .watchOS: return "Apple Watch"
        case .visionOS: return "Apple Vision"
        }
    }
}

enum TargetAppError: Error, CustomStringConvertible {
    case noPlatform
    case appNotFound(String)
    case commandFailed(String)
    case noSimulator(String)

    var description: String {
        switch self {
        case .noPlatform:
            return "Set KSCRASH_IT_PLATFORM to one of \(TargetPlatform.allCases.map(\.rawValue)) "
                + "(TEST_RUNNER_KSCRASH_IT_PLATFORM when running through xcodebuild)."
        case .appNotFound(let detail), .commandFailed(let detail), .noSimulator(let detail): return detail
        }
    }
}

/// The Sample app on the target platform, with the few operations the tests use.
@MainActor
final class TargetApp {
    enum State {
        case notRunning
        case runningForeground
    }

    static let bundleID = "com.github.kstenerud.KSCrash.Sample"

    /// Passed to every launch, as `XCUIApplication.launchEnvironment` was.
    var launchEnvironment: [String: String] = [:]

    private let appURL: URL
    private var process: Process?
    private var simulatorPID: pid_t?

    init() throws {
        appURL = try Self.locateApp()
        if TargetPlatform.current != .macOS {
            try SimulatorDevice.shared(installing: appURL)
        }
    }

    var state: State {
        switch TargetPlatform.current {
        case .macOS:
            return process?.isRunning == true ? .runningForeground : .notRunning
        default:
            guard let pid = simulatorPID else { return .notRunning }
            // A simulator app is a process on this Mac, just not our child: probe it.
            return kill(pid, 0) == 0 || errno == EPERM ? .runningForeground : .notRunning
        }
    }

    func launch() {
        terminate()
        do {
            switch TargetPlatform.current {
            case .macOS:
                let process = Process()
                process.executableURL = appURL.appendingPathComponent("Contents/MacOS/Sample")
                // Without this, relaunching after an intended crash puts up AppKit's "reopen
                // windows?" alert, which blocks the app before the test script can run.
                process.arguments = ["-ApplePersistenceIgnoreState", "YES"]
                process.environment = Self.macEnvironment.merging(launchEnvironment) { $1 }
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                self.process = process
            default:
                let device = try SimulatorDevice.shared(installing: appURL)
                simulatorPID = try device.launch(Self.bundleID, environment: launchEnvironment)
            }
        } catch {
            XCTFail("Could not launch the Sample app: \(error)")
        }
    }

    /// Polls until the app is in `state`. False on timeout.
    @discardableResult
    func wait(for state: State, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while self.state != state {
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    func terminate() {
        guard state == .runningForeground else { return }
        switch TargetPlatform.current {
        case .macOS:
            process?.terminate()
            if !wait(for: .notRunning, timeout: 5), let pid = process?.processIdentifier {
                kill(pid, SIGKILL)
            }
        default:
            // SIGTERM, as XCUIApplication.terminate() sent: KSCrash records it as a clean exit,
            // and the tests rely on that. `simctl terminate` ends the app without that chance,
            // so the next launch reports the run as an unexplained termination.
            if let pid = simulatorPID {
                kill(pid, SIGTERM)
            }
            if !wait(for: .notRunning, timeout: 5) {
                _ = try? SimulatorDevice.shared(installing: appURL).terminate(Self.bundleID)
            }
        }
        wait(for: .notRunning, timeout: 5)
    }

    /// The test process's own environment is not handed down: it carries XCTest's injection
    /// variables, which would load XCTest into the app.
    private static var macEnvironment: [String: String] {
        let passed = ["HOME", "USER", "LOGNAME", "TMPDIR", "PATH", "LANG"]
        let environment = ProcessInfo.processInfo.environment
        return Dictionary(uniqueKeysWithValues: passed.compactMap { key in environment[key].map { (key, $0) } })
    }

    /// `KSCRASH_IT_APP` when set; otherwise the Sample app built into the same derived data as
    /// this bundle, in this configuration's products directory for the target platform.
    private static func locateApp() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["KSCRASH_IT_APP"] {
            return URL(fileURLWithPath: path)
        }
        let products = Bundle(for: TargetApp.self).bundleURL.deletingLastPathComponent()
        let directory =
            TargetPlatform.current == .macOS
            ? products
            : products.deletingLastPathComponent()
                .appendingPathComponent("\(products.lastPathComponent)-\(TargetPlatform.current.simulatorSDK)")
        let app = directory.appendingPathComponent("Sample.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw TargetAppError.appNotFound(
                "No Sample.app at \(app.path). Build the Sample scheme for \(TargetPlatform.current) first, "
                    + "or set KSCRASH_IT_APP.")
        }
        return app
    }
}

/// The one simulator this test run uses. Created fresh for the run and deleted when the bundle
/// finishes, unless `KSCRASH_IT_DEVICE` names an existing one to use as is.
@MainActor
final class SimulatorDevice {
    let udid: String
    private var installedApp: URL?

    private static var instance: SimulatorDevice?
    private static var observer: Cleanup?

    @discardableResult
    static func shared(installing app: URL) throws -> SimulatorDevice {
        let device = try instance ?? make(for: app)
        instance = device
        if device.installedApp != app {
            try xcrun(["simctl", "install", device.udid, app.path])
            device.installedApp = app
        }
        return device
    }

    private init(udid: String) {
        self.udid = udid
    }

    /// Launches `bundleID` with `environment` (simctl forwards `SIMCTL_CHILD_`-prefixed
    /// variables) and returns its pid.
    func launch(_ bundleID: String, environment: [String: String]) throws -> pid_t {
        let forwarded = Dictionary(uniqueKeysWithValues: environment.map { ("SIMCTL_CHILD_\($0.key)", $0.value) })
        let output = try Self.xcrun(
            ["simctl", "launch", "--terminate-running-process", udid, bundleID], environment: forwarded)
        // "<bundle id>: <pid>"
        guard let pidText = output.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = pid_t(pidText)
        else {
            throw TargetAppError.commandFailed("simctl launch printed no pid: \(output)")
        }
        return pid
    }

    func terminate(_ bundleID: String) throws {
        try Self.xcrun(["simctl", "terminate", udid, bundleID], allowFailure: true)
    }

    private static func make(for app: URL) throws -> SimulatorDevice {
        let environment = ProcessInfo.processInfo.environment
        if let udid = environment["KSCRASH_IT_DEVICE"] {
            try xcrun(["simctl", "boot", udid], allowFailure: true)
            try xcrun(["simctl", "bootstatus", udid, "-b"])
            try keepHomeScreenClosed(on: udid)
            return SimulatorDevice(udid: udid)
        }
        let (runtime, deviceType) = try pickRuntimeAndDeviceType(for: app)
        let udid = try xcrun(["simctl", "create", "KSCrashIntegrationTests", deviceType, runtime])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let device = SimulatorDevice(udid: udid)
        let cleanup = Cleanup(udid: udid)
        XCTestObservationCenter.shared.addTestObserver(cleanup)
        observer = cleanup
        try xcrun(["simctl", "boot", udid])
        try xcrun(["simctl", "bootstatus", udid, "-b"])
        try keepHomeScreenClosed(on: udid)
        return device
    }

    /// tvOS opens its home screen when an app dies. On a loaded machine PineBoard learns of a
    /// crashed app's exit late, as late as the next launch's own request to end it, and the
    /// home screen then races that launch. Opening second, it covers the new app, which is
    /// suspended before the test's script acts. With the home screen kept closed, a launch has
    /// nothing to race.
    private static func keepHomeScreenClosed(on udid: String) throws {
        guard TargetPlatform.current == .tvOS else { return }
        try xcrun(["simctl", "spawn", udid, "defaults", "write", "com.apple.PineBoard", "NoAutoLaunch", "-bool", "YES"])
    }

    /// `KSCRASH_IT_RUNTIME` and `KSCRASH_IT_DEVICE_TYPE` when set. Otherwise the runtime whose
    /// version matches the SDK the app was built with (the newest one below it when there is
    /// no exact match), so the app runs on the OS it was built for, and that runtime's first
    /// device type of the platform's family.
    private static func pickRuntimeAndDeviceType(for app: URL) throws -> (runtime: String, deviceType: String) {
        struct List: Decodable {
            struct Runtime: Decodable {
                struct DeviceType: Decodable {
                    let identifier: String
                    let productFamily: String?
                }
                let identifier: String
                let platform: String?
                let version: String
                let isAvailable: Bool
                let supportedDeviceTypes: [DeviceType]?
            }
            let runtimes: [Runtime]
        }
        let platform = TargetPlatform.current
        let environment = ProcessInfo.processInfo.environment
        let list = try JSONDecoder().decode(
            List.self, from: Data(try xcrun(["simctl", "list", "-j", "runtimes"]).utf8))
        let candidates = list.runtimes.filter { $0.isAvailable && $0.platform == platform.simulatorRuntimePlatform }

        let runtime: List.Runtime
        if let wanted = environment["KSCRASH_IT_RUNTIME"] {
            guard let match = candidates.first(where: { $0.identifier == wanted }) else {
                throw TargetAppError.noSimulator("No available runtime \(wanted)")
            }
            runtime = match
        } else {
            let sorted = candidates.sorted { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
            let notNewerThanSDK = sdkVersion(of: app).flatMap { sdk in
                sorted.last { $0.version.compare(sdk, options: .numeric) != .orderedDescending }
            }
            guard let match = notNewerThanSDK ?? sorted.last else {
                throw TargetAppError.noSimulator("No available \(platform) simulator runtime")
            }
            runtime = match
        }

        if let wanted = environment["KSCRASH_IT_DEVICE_TYPE"] {
            return (runtime.identifier, wanted)
        }
        guard
            let deviceType = runtime.supportedDeviceTypes?.first(where: { $0.productFamily == platform.deviceFamily })
        else {
            throw TargetAppError.noSimulator("Runtime \(runtime.identifier) supports no \(platform.deviceFamily)")
        }
        return (runtime.identifier, deviceType.identifier)
    }

    /// The SDK version the app was built against, from its Info.plist.
    private static func sdkVersion(of app: URL) -> String? {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist"))
        return info?["DTPlatformVersion"] as? String
    }

    /// Runs `xcrun` and returns its standard output. Standard error is kept apart so a
    /// warning never lands in output that gets parsed (a device id, a pid).
    @discardableResult
    nonisolated fileprivate static func xcrun(
        _ arguments: [String], environment extra: [String: String] = [:], allowFailure: Bool = false
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 && !allowFailure {
            throw TargetAppError.commandFailed(
                "xcrun \(arguments.joined(separator: " ")): \(String(decoding: errorData, as: UTF8.self))")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Deletes the device this run created once the bundle finishes.
    private final class Cleanup: NSObject, XCTestObservation {
        let udid: String

        init(udid: String) {
            self.udid = udid
        }

        func testBundleDidFinish(_ testBundle: Bundle) {
            _ = try? SimulatorDevice.xcrun(["simctl", "shutdown", udid], allowFailure: true)
            _ = try? SimulatorDevice.xcrun(["simctl", "delete", udid], allowFailure: true)
        }
    }
}
