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
    /// Where KSCrash handles Mach exceptions (`KSCRASH_HAS_MACH`).
    static let machExceptionHosts: Set<TargetPlatform> = [.iOS, .macOS, .visionOS]

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
    private let createdAt = Date()

    init() throws {
        appURL = try Self.locateApp()
        if TargetPlatform.current != .macOS {
            if let error = Self.deviceSetupError { throw error }
            try SimulatorDevice.shared(installing: appURL)
        }
    }

    /// Why `prepareDevice` failed, when it did. Every test throws it rather than try the
    /// setup again inside its own time allowance.
    private static var deviceSetupError: Error?

    /// Creates the run's simulator and installs the app before the first test, so the minutes
    /// that takes are charged to no test. Called by `IntegrationTestsSetup`.
    static func prepareDevice() {
        guard let platform = TargetPlatform.configured, platform != .macOS else { return }
        do {
            try SimulatorDevice.shared(installing: locateApp())
        } catch {
            deviceSetupError = error
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

    /// What the app was doing when a test gave up waiting on it: its threads, while it is still
    /// running, and its system log since this test began. Taken before teardown ends the app,
    /// because a stuck app killed by teardown leaves no trace of where it was stuck.
    func diagnostics() -> [(name: String, text: String)] {
        var result: [(name: String, text: String)] = []

        let pid = TargetPlatform.current == .macOS ? process?.processIdentifier : simulatorPID
        if state == .runningForeground, let pid {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("Sample-\(pid).sample.txt")
            _ = try? SimulatorDevice.xcrun(["sample", String(pid), "2", "-file", file.path], allowFailure: true)
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? "sample \(pid) wrote nothing"
            try? FileManager.default.removeItem(at: file)
            result.append(("App threads", text))
        } else {
            result.append(("App threads", "The app was not running."))
        }

        let start = DateFormatter()
        start.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let logShow = [
            "log", "show", "--info", "--style", "compact", "--start", start.string(from: createdAt),
            "--predicate", "process == \"Sample\"",
        ]
        let arguments =
            TargetPlatform.current == .macOS
            ? logShow
            : ["simctl", "spawn", (try? SimulatorDevice.shared(installing: appURL).udid) ?? "booted"] + logShow
        let log = (try? SimulatorDevice.xcrun(arguments, allowFailure: true)) ?? "log show failed"
        result.append(("App system log", log))

        return result
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

/// The test bundle's principal class (`NSPrincipalClass` in Samples/Project.swift). XCTest makes
/// one when the bundle loads, so it sets up the simulator before any test starts. Charged to the
/// first test instead, that setup used most of the test's five minute allowance on CI.
@objc(KSCrashIntegrationTestsSetup)
final class IntegrationTestsSetup: NSObject, XCTestObservation {
    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        // XCTest calls its observers on the main thread.
        MainActor.assumeIsolated { TargetApp.prepareDevice() }
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
            try xcrun(["simctl", "boot", udid], allowFailure: true, timeout: bootTimeout)
            try xcrun(["simctl", "bootstatus", udid, "-b"], timeout: bootTimeout)
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
        try xcrun(["simctl", "boot", udid], timeout: bootTimeout)
        try xcrun(["simctl", "bootstatus", udid, "-b"], timeout: bootTimeout)
        try quiet(udid)
        try keepHomeScreenClosed(on: udid)
        return device
    }

    private static let bootTimeout: TimeInterval = 600

    /// Jobs a fresh simulator runs that keep the Mac's cores busy for minutes after a boot.
    /// On iOS 26.5 they held a new device at 300 to 400% CPU (mediaanalysisd alone at over
    /// 350%), and on a CI runner that load stretched the first app launch past a test's
    /// time allowance. A label the runtime does not have is harmless to disable.
    private static let busyJobs = [
        "PosterBoard", "chronod", "remindd", "siriinferenced", "dataaccess.dataaccessd", "healthd",
        "healthappd", "siriactionsd", "sirittsd", "email.maild", "homed", "calaccessd",
        "icloudmailagent", "amsengagementd", "intelligenceplatformd", "intelligenceflowd", "triald",
        "assistantd", "telephonyutilities.callservicesd", "mediaanalysisd", "mediaanalysisd.service",
        "photoanalysisd",
    ]

    /// Disables `busyJobs` and stops the ones already running. A disabled job is not started
    /// again, so the device stays quiet without a reboot. Some of these run per user rather
    /// than system-wide, so each is disabled in both domains. Every system disable must succeed;
    /// the user domain is best effort, since tvOS and watchOS have none and some runtimes
    /// (tvOS 26.2) refuse every disable there. A job that is not running fails to stop, which
    /// is harmless once it is disabled. The calls run a few at a time because each one is a
    /// separate spawn into the simulator.
    private static func quiet(_ udid: String) throws {
        let domains = ["system", "user/\(getuid())"]
        let failures = Failures()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        for domain in domains {
            for job in busyJobs {
                let label = "\(domain)/com.apple.\(job)"
                queue.addOperation {
                    guard (try? xcrun(["simctl", "spawn", udid, "launchctl", "disable", label])) != nil else {
                        if domain == "system" {
                            failures.append(label)
                        }
                        return
                    }
                    _ = try? xcrun(["simctl", "spawn", udid, "launchctl", "bootout", label], allowFailure: true)
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        guard failures.all.isEmpty else {
            throw TargetAppError.commandFailed("launchctl disable failed for \(failures.all)")
        }
    }

    private final class Failures: @unchecked Sendable {
        private let lock = NSLock()
        private var labels: [String] = []

        func append(_ label: String) {
            lock.withLock { labels.append(label) }
        }

        var all: [String] {
            lock.withLock { labels }
        }
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
    /// warning never lands in output that gets parsed (a device id, a pid). A command still
    /// running after `timeout` seconds is terminated and throws, naming the command, rather
    /// than holding the run until the CI job's own limit ends it without a word.
    @discardableResult
    nonisolated fileprivate static func xcrun(
        _ arguments: [String], environment extra: [String: String] = [:], allowFailure: Bool = false,
        timeout: TimeInterval = 120
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let drained = DispatchGroup()
        let data = PipeContents(output, in: drained)
        let errorData = PipeContents(errors, in: drained)
        let deadline = DispatchTime.now() + timeout
        guard exited.wait(timeout: deadline) == .success, drained.wait(timeout: deadline) == .success else {
            process.terminate()
            throw TargetAppError.commandFailed(
                "xcrun \(arguments.joined(separator: " ")) did not finish within \(Int(timeout)) s")
        }
        if process.terminationStatus != 0 && !allowFailure {
            throw TargetAppError.commandFailed(
                "xcrun \(arguments.joined(separator: " ")): \(String(decoding: errorData.data, as: UTF8.self))")
        }
        return String(decoding: data.data, as: UTF8.self)
    }

    /// `data` is read only after `group` has been waited on.
    private final class PipeContents: @unchecked Sendable {
        private(set) var data = Data()

        init(_ pipe: Pipe, in group: DispatchGroup) {
            group.enter()
            DispatchQueue.global().async {
                self.data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }
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
