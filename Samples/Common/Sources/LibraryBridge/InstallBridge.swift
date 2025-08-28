//
//  InstallBridge.swift
//
//  Created by Nikolay Volosatov on 2024-07-07.
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

import Combine
import CrashCallback
import Foundation
import KSCrashInstallations
import KSCrashRecording
import Logging
import SwiftUI

public enum BasePath: String, CaseIterable {
    case `default`
    case cache
    case applicationSupport
}

public class InstallBridge: ObservableObject {
    public typealias MonitorType = KSCrashRecording.MonitorType

    public enum InstallationError: Error, LocalizedError {
        case kscrashError(String)
        case unexpectedError(String)
        case alreadyInstalled

        public var errorDescription: String? {
            switch self {
            case .kscrashError(let message), .unexpectedError(let message):
                return message
            case .alreadyInstalled:
                return "KSCrash is already installed"
            }
        }
    }

    private static let logger = Logger(label: "InstallBridge")

    private func setBasePath(_ value: BasePath) {
        let basePath = value.basePaths.first.flatMap { $0 + "/KSCrash" }
        Self.logger.info("Setting KSCrash base path to: \(basePath ?? "<default>")")
        config.installPath = basePath
    }

    private var config: KSCrashConfiguration
    private var disposables = Set<AnyCancellable>()

    @Published public var basePath: BasePath = .default
    @Published public var installed: Bool = false
    @Published public var reportsOnlySetup: Bool = false
    @Published public var error: InstallationError?

    @Published public var reportStore: CrashReportStore?
    @Published public var installation: CrashInstallation?

    public init() {
        config = .init()

        // Example of setting a crash notify callback from Swift.
        // To see this in action, comment out the following line below this block:
        //     "config.isWritingReportCallback = integrationTestIsWritingReportCallback"
        // Then tap "Install", "Report", "Log Raw to Console" in the sample app to see these custom fields in the raw report.
        let cb: @convention(c) (UnsafePointer<ExceptionHandlingPlan>, UnsafePointer<ReportWriter>) -> Void = {
            plan, writer in
            writer.pointee.beginObject(writer, "plan")
            writer.pointee.addBooleanElement(writer, "isFatal", plan.pointee.isFatal)
            writer.pointee.addBooleanElement(writer, "requiresAsyncSafety", plan.pointee.requiresAsyncSafety)
            writer.pointee.addBooleanElement(
                writer, "crashedDuringExceptionHandling", plan.pointee.crashedDuringExceptionHandling)
            writer.pointee.addBooleanElement(writer, "shouldRecordAllThreads", plan.pointee.shouldRecordAllThreads)
            writer.pointee.endContainer(writer)
        }
        config.isWritingReportCallback = cb
        // The above block is an example only. We use integrationTestIsWritingReportCallback in the tests.
        config.isWritingReportCallback = integrationTestIsWritingReportCallback

        $basePath
            .removeDuplicates()
            .sink(receiveValue: setBasePath(_:))
            .store(in: &disposables)
    }

    private func handleInstallation(_ block: () throws -> Void) {
        do {
            try block()
        } catch let error as KSCrashInstallError {
            let message = error.localizedDescription
            Self.logger.error("Failed to install KSCrash: \(message)")
            self.error = .kscrashError(message)
        } catch {
            let message = error.localizedDescription
            Self.logger.error("Unexpected error during KSCrash installation: \(message)")
            self.error = .unexpectedError(message)
        }
    }

    public func install() {
        guard !installed else {
            error = .alreadyInstalled
            return
        }

        handleInstallation {
            try KSCrash.shared.install(with: config)
            reportStore = KSCrash.shared.reportStore
            installed = true
        }
    }

    public func useInstallation(_ installation: CrashInstallation) {
        guard !installed else {
            error = .alreadyInstalled
            return
        }

        handleInstallation {
            try installation.install(with: config)
            reportStore = KSCrash.shared.reportStore
            self.installation = installation
            installed = true
        }
    }

    public func setupReportsOnly() {
        do {
            let config = CrashReportStoreConfiguration()
            config.reportsPath = self.config.installPath.map { $0 + "/" + CrashReportStore.defaultInstallSubfolder }
            reportStore = try CrashReportStore(configuration: config)
            reportsOnlySetup = true
        } catch let error as KSCrashInstallError {
            let message = error.localizedDescription
            Self.logger.error("Failed to install KSCrash: \(message)")
            self.error = .kscrashError(message)
        } catch {
            let message = error.localizedDescription
            Self.logger.error("Unexpected error during KSCrash installation: \(message)")
            self.error = .unexpectedError(message)
        }
    }
}

// An utility method to simplify binding of config fields
extension InstallBridge {
    public func configBinding<T>(for keyPath: WritableKeyPath<KSCrashConfiguration, T>) -> Binding<T> {
        .init { [config] in
            config[keyPath: keyPath]
        } set: { [weak self] val in
            self?.objectWillChange.send()
            self?.config[keyPath: keyPath] = val
        }
    }
}

// Monitor types are specified here
extension InstallBridge {
    public static let allRawMonitorTypes: [(monitor: MonitorType, name: String, description: String)] = [
        (.machException, "Mach Exception", "Low-level system exceptions"),
        (.signal, "Signal", "UNIX-style signals indicating abnormal program termination"),
        (.cppException, "C++ Exception", "Unhandled exceptions in C++ code"),
        (.nsException, "NSException", "Unhandled Objective-C exceptions"),
        (.mainThreadDeadlock, "Main Thread Deadlock", "Situations where the main thread becomes unresponsive"),
        (.memoryTermination, "Memory Termination", "Termination due to excessive memory usage"),
        (.zombie, "Zombie", "Attempts to access deallocated objects"),
        (.userReported, "User Reported", "Custom crash reports"),
        (.system, "System", "Additional system information added to reports"),
        (.applicationState, "Application State", "Application lifecycle added to report"),
    ]

    public static let allCompositeMonitorTypes: [(monitor: MonitorType, name: String)] = [
        (.all, "All"),
        (.fatal, "Fatal"),

        (.productionSafe, "Production-safe"),
        (.productionSafeMinimal, "Production-safe Minimal"),
        (.experimental, "Experimental"),

        (.required, "Required"),
        (.optional, "Optional"),

        (.debuggerSafe, "Debugger-safe"),
        (.debuggerUnsafe, "Debugger-unsafe"),

        (.asyncSafe, "Async-safe"),
        (.asyncUnsafe, "Async-unsafe"),

        (.manual, "Manual"),
    ]
}

extension BasePath {
    var basePaths: [String] {
        switch self {
        case .default:
            return []
        case .cache:
            return NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        case .applicationSupport:
            return NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        }
    }
}
