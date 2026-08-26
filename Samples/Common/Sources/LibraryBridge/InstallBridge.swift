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
import KSCrash
import Logging
import SwiftUI

public enum ContainerChoice: String, CaseIterable {
    case `default`
    case cache
    case applicationSupport

    var container: Container {
        switch self {
        case .default: return .default
        case .cache: return .caches
        case .applicationSupport: return .applicationSupport
        }
    }
}

public class InstallBridge: ObservableObject {
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

    private var config: InstallConfiguration
    private var disposables = Set<AnyCancellable>()

    @Published public var container: ContainerChoice = .default
    @Published public var installed: Bool = false
    @Published public var error: InstallationError?

    /// Where the install put its reports; nil until installed.
    @Published public var reportsDirectory: URL?
    @Published public var useSamplePipeline: Bool = false

    public init() {
        config = InstallConfiguration(namespace: "Sample")

        // Example of adding custom fields at crash time from Swift. The tests
        // use integrationTestIsWritingReportCallback instead (set below).
        var callbacks = UnsafeCrashTimeCallbacks()
        callbacks.isWritingReport = { plan, writer in
            writer.pointee.beginObject(writer, "plan")
            writer.pointee.addBooleanElement(writer, "isFatal", plan.pointee.isFatal)
            writer.pointee.addBooleanElement(writer, "requiresAsyncSafety", plan.pointee.requiresAsyncSafety)
            writer.pointee.addBooleanElement(
                writer, "crashedDuringExceptionHandling", plan.pointee.crashedDuringExceptionHandling)
            writer.pointee.addBooleanElement(writer, "shouldRecordAllThreads", plan.pointee.shouldRecordAllThreads)
            writer.pointee.endContainer(writer)
        }
        callbacks.isWritingReport = integrationTestIsWritingReportCallback
        config.unsafeCrashTimeCallbacks = callbacks

        $container
            .removeDuplicates()
            .sink { [weak self] choice in
                Self.logger.info("Setting KSCrash container to: \(choice.rawValue)")
                self?.config.container = choice.container
            }
            .store(in: &disposables)
    }

    private func handleInstallation(_ block: () throws -> Void) {
        do {
            try block()
        } catch let error as InstallError {
            let message = String(describing: error)
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
            try KSCrash.shared.install(config)
            reportsDirectory = try KSCrash.shared.installConfiguration?.locations.reports
            installed = true
        }
    }

    // Installs normally and flags that report sending should use the sample
    // pipeline (SampleLogStage -> KeepOnDiskStage), passed at send time.
    public func useSampleSendPipeline() {
        install()
        if installed {
            useSamplePipeline = true
        }
    }

    public func sendViaSamplePipeline(completion: @escaping (Error?) -> Void) {
        guard installed else {
            completion(InstallationError.unexpectedError("KSCrash is not installed"))
            return
        }
        Task { @MainActor in
            do {
                let configuration = SendConfiguration(reportPipeline: [
                    AnyPipelineStage(SampleLogStage()),
                    AnyPipelineStage(KeepOnDiskStage()),
                ])
                _ = try await KSCrash.shared.sendReports(with: configuration)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }
}

// An utility method to simplify binding of config fields
extension InstallBridge {
    public func configBinding<T>(for keyPath: WritableKeyPath<InstallConfiguration, T>) -> Binding<T> {
        // InstallConfiguration is a struct: a plain [config] capture would
        // freeze the getter on install-time values while the setter mutates
        // self.config, so every SwiftUI refresh would appear to revert.
        .init { [weak self, config] in
            self?.config[keyPath: keyPath] ?? config[keyPath: keyPath]
        } set: { [weak self] val in
            self?.objectWillChange.send()
            self?.config[keyPath: keyPath] = val
        }
    }
}
