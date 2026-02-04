//
//  MetricKitJSONDumper.swift
//
//  Created by Alexander Cohen on 2026-02-03.
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
import os.log

#if os(iOS) || os(macOS)
    import MetricKit
#endif

#if SWIFT_PACKAGE
    import KSCrashRecording
#endif

// MARK: - MetricKit JSON Dumper

#if os(iOS) || os(macOS)

    @available(iOS 14.0, macOS 12.0, *)
    enum MetricKitJSONDumper {

        private static var runId: String {
            String(cString: kscrash_getRunID())
        }

        /// Writes JSON data to Documents/MetricKit/<type>/<type>_<runId>_<uuid>.json
        static func dump(_ data: Data, type: String) {
            guard
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                    .first
            else {
                os_log(.error, log: metricKitLog, "[MONITORS] Could not resolve documents directory")
                return
            }

            let dirURL = documentsURL.appendingPathComponent("MetricKit/\(type)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            } catch {
                os_log(
                    .error, log: metricKitLog,
                    "[MONITORS] Failed to create MetricKit/%{public}@ directory: %{public}@",
                    type, error.localizedDescription)
                return
            }

            let filenameType = type.replacingOccurrences(of: "/", with: "_")
            let filename = "\(filenameType)_\(runId)_\(UUID().uuidString).json"
            let fileURL = dirURL.appendingPathComponent(filename)

            do {
                try data.write(to: fileURL, options: .atomic)
                os_log(
                    .default, log: metricKitLog,
                    "[MONITORS] Dumped JSON (%d bytes) to MetricKit/%{public}@/%{public}@",
                    data.count, type, filename)
            } catch {
                os_log(
                    .error, log: metricKitLog,
                    "[MONITORS] Failed to write to MetricKit/%{public}@: %{public}@",
                    type, error.localizedDescription)
            }
        }

        /// Writes a JSON-serializable object to Documents/MetricKit/<type>/<type>_<runId>_<uuid>.json
        static func dump(_ json: Any, type: String) {
            guard JSONSerialization.isValidJSONObject(json) else {
                os_log(.error, log: metricKitLog, "[MONITORS] Invalid JSON object for %{public}@", type)
                return
            }

            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: json,
                    options: [.prettyPrinted, .sortedKeys]
                )
            else {
                os_log(.error, log: metricKitLog, "[MONITORS] Failed to serialize JSON for %{public}@", type)
                return
            }

            dump(data, type: type)
        }

        @available(iOS 17.0, macOS 14.0, *)
        static func dumpSignposts(_ records: [MXSignpostRecord]?, type: String) {
            guard let records = records, !records.isEmpty else { return }
            let signposts = records.map { $0.dictionaryRepresentation() }
            dump(signposts, type: "Signposts/\(type)")
        }
    }

    // MARK: - MXDiagnosticPayload Extension

    @available(iOS 14.0, macOS 12.0, *)
    extension MXDiagnosticPayload {
        /// Dumps the full payload JSON, each diagnostic, and all signposts.
        func dump() {
            MetricKitJSONDumper.dump(jsonRepresentation(), type: "DiagnosticPayload")

            if let diagnostics = crashDiagnostics { for d in diagnostics { d.dump() } }
            if let diagnostics = cpuExceptionDiagnostics { for d in diagnostics { d.dump() } }
            if let diagnostics = diskWriteExceptionDiagnostics { for d in diagnostics { d.dump() } }
            if let diagnostics = hangDiagnostics { for d in diagnostics { d.dump() } }

            if #available(iOS 17.0, macOS 14.0, *) {
                if let diagnostics = crashDiagnostics { for d in diagnostics { d.dumpSignposts() } }
                if let diagnostics = cpuExceptionDiagnostics { for d in diagnostics { d.dumpSignposts() } }
                if let diagnostics = diskWriteExceptionDiagnostics { for d in diagnostics { d.dumpSignposts() } }
                if let diagnostics = hangDiagnostics { for d in diagnostics { d.dumpSignposts() } }
            }

            #if os(iOS)
                if #available(iOS 17.0, *) {
                    if let diagnostics = appLaunchDiagnostics {
                        for d in diagnostics { d.dump() }
                        for d in diagnostics { d.dumpSignposts() }
                    }
                }
            #endif
        }
    }

    // MARK: - MXMetricPayload Extension

    @available(iOS 14.0, macOS 12.0, *)
    extension MXMetricPayload {
        func dump() {
            MetricKitJSONDumper.dump(jsonRepresentation(), type: "Metric")
        }
    }

    // MARK: - MXCrashDiagnostic Extension

    @available(iOS 14.0, macOS 12.0, *)
    extension MXCrashDiagnostic {
        func dump() {
            MetricKitJSONDumper.dump(jsonRepresentation(), type: "Crash")
        }

        @available(iOS 17.0, macOS 14.0, *)
        func dumpSignposts() {
            MetricKitJSONDumper.dumpSignposts(signpostData, type: "Crash")
        }
    }

    // MARK: - MXCPUExceptionDiagnostic Extension

    @available(iOS 14.0, macOS 12.0, *)
    extension MXCPUExceptionDiagnostic {
        func dump() {
            MetricKitJSONDumper.dump(jsonRepresentation(), type: "CPUException")
        }

        @available(iOS 17.0, macOS 14.0, *)
        func dumpSignposts() {
            MetricKitJSONDumper.dumpSignposts(signpostData, type: "CPUException")
        }
    }

    // MARK: - MXDiskWriteExceptionDiagnostic Extension

    @available(iOS 14.0, macOS 12.0, *)
    extension MXDiskWriteExceptionDiagnostic {
        func dump() {
            MetricKitJSONDumper.dump(jsonRepresentation(), type: "DiskWriteException")
        }

        @available(iOS 17.0, macOS 14.0, *)
        func dumpSignposts() {
            MetricKitJSONDumper.dumpSignposts(signpostData, type: "DiskWriteException")
        }
    }

    // MARK: - MXHangDiagnostic Extension

    @available(iOS 14.0, macOS 12.0, *)
    extension MXHangDiagnostic {
        func dump() {
            MetricKitJSONDumper.dump(jsonRepresentation(), type: "Hang")
        }

        @available(iOS 17.0, macOS 14.0, *)
        func dumpSignposts() {
            MetricKitJSONDumper.dumpSignposts(signpostData, type: "Hang")
        }
    }

    // MARK: - MXAppLaunchDiagnostic Extension

    #if os(iOS)
        @available(iOS 17.0, *)
        extension MXAppLaunchDiagnostic {
            func dump() {
                MetricKitJSONDumper.dump(jsonRepresentation(), type: "AppLaunch")
            }

            func dumpSignposts() {
                MetricKitJSONDumper.dumpSignposts(signpostData, type: "AppLaunch")
            }
        }
    #endif

#endif
