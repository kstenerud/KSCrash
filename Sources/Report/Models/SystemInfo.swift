//
//  SystemInfo.swift
//
//  Created by Alexander Cohen on 2024-12-09.
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

/// The build type of the application.
public enum BuildType: RawRepresentable, Codable, Sendable, Equatable {
    case simulator
    case debug
    case release
    case test
    case appStore
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "simulator": self = .simulator
        case "debug": self = .debug
        case "release": self = .release
        case "test": self = .test
        case "app store": self = .appStore
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .simulator: return "simulator"
        case .debug: return "debug"
        case .release: return "release"
        case .test: return "test"
        case .appStore: return "app store"
        case .unknown(let value): return value
        }
    }
}

/// System information at the time of crash.
public struct SystemInfo: Codable, Sendable, Equatable {
    /// Bundle executable name.
    public let cfBundleExecutable: String?

    /// Full path to the bundle executable.
    public let cfBundleExecutablePath: String?

    /// Bundle identifier.
    public let cfBundleIdentifier: String?

    /// Bundle display name.
    public let cfBundleName: String?

    /// Short version string (marketing version).
    public let cfBundleShortVersionString: String?

    /// Bundle version (build number).
    public let cfBundleVersion: String?

    /// Timestamp when the app was started.
    public let appStartTime: Date?

    /// UUID of the app binary.
    public let appUUID: String?

    /// Application usage statistics.
    public let applicationStats: ApplicationStats?

    /// System boot time.
    public let bootTime: Date?

    /// CPU architecture string (e.g., "arm64", "x86_64").
    public let cpuArch: String?

    /// CPU type code.
    public let cpuType: Int?

    /// CPU subtype code.
    public let cpuSubtype: Int?

    /// Binary CPU architecture (may differ from runtime on Rosetta).
    public let binaryArch: String?

    /// Binary CPU type.
    public let binaryCPUType: Int?

    /// Binary CPU subtype.
    public let binaryCPUSubtype: Int?

    /// Hash identifying the device and app combination.
    public let deviceAppHash: String?

    /// Whether the device is jailbroken.
    public let jailbroken: Bool?

    /// Whether the process is running under Rosetta translation.
    public let procTranslated: Bool?

    /// Darwin kernel version string.
    public let kernelVersion: String?

    /// Machine identifier (e.g., "iPhone14,2").
    public let machine: String?

    /// Memory information.
    public let memory: MemoryInfo?

    /// Model identifier.
    public let model: String?

    /// OS build version.
    public let osVersion: String?

    /// Parent process ID.
    public let parentProcessID: Int?

    /// Parent process name.
    public let parentProcessName: String?

    /// Process ID.
    public let processID: Int?

    /// Process name.
    public let processName: String?

    /// System name (e.g., "iOS", "macOS").
    public let systemName: String?

    /// System version (e.g., "17.0").
    public let systemVersion: String?

    /// Timezone identifier.
    public let timeZone: String?

    /// Total storage in bytes.
    public let storage: Int64?

    /// Free storage in bytes.
    public let freeStorage: Int64?

    /// Build type of the application.
    public let buildType: BuildType?

    /// Clang version used to compile the app.
    public let clangVersion: String?

    /// App memory information.
    public let appMemory: AppMemoryInfo?

    /// Whether Low Power Mode was enabled at the time of the event.
    public let lowPowerModeEnabled: Bool?

    public init(
        cfBundleExecutable: String? = nil,
        cfBundleExecutablePath: String? = nil,
        cfBundleIdentifier: String? = nil,
        cfBundleName: String? = nil,
        cfBundleShortVersionString: String? = nil,
        cfBundleVersion: String? = nil,
        appStartTime: Date? = nil,
        appUUID: String? = nil,
        applicationStats: ApplicationStats? = nil,
        bootTime: Date? = nil,
        cpuArch: String? = nil,
        cpuType: Int? = nil,
        cpuSubtype: Int? = nil,
        binaryArch: String? = nil,
        binaryCPUType: Int? = nil,
        binaryCPUSubtype: Int? = nil,
        deviceAppHash: String? = nil,
        jailbroken: Bool? = nil,
        procTranslated: Bool? = nil,
        kernelVersion: String? = nil,
        machine: String? = nil,
        memory: MemoryInfo? = nil,
        model: String? = nil,
        osVersion: String? = nil,
        parentProcessID: Int? = nil,
        parentProcessName: String? = nil,
        processID: Int? = nil,
        processName: String? = nil,
        systemName: String? = nil,
        systemVersion: String? = nil,
        timeZone: String? = nil,
        storage: Int64? = nil,
        freeStorage: Int64? = nil,
        buildType: BuildType? = nil,
        clangVersion: String? = nil,
        appMemory: AppMemoryInfo? = nil,
        lowPowerModeEnabled: Bool? = nil
    ) {
        self.cfBundleExecutable = cfBundleExecutable
        self.cfBundleExecutablePath = cfBundleExecutablePath
        self.cfBundleIdentifier = cfBundleIdentifier
        self.cfBundleName = cfBundleName
        self.cfBundleShortVersionString = cfBundleShortVersionString
        self.cfBundleVersion = cfBundleVersion
        self.appStartTime = appStartTime
        self.appUUID = appUUID
        self.applicationStats = applicationStats
        self.bootTime = bootTime
        self.cpuArch = cpuArch
        self.cpuType = cpuType
        self.cpuSubtype = cpuSubtype
        self.binaryArch = binaryArch
        self.binaryCPUType = binaryCPUType
        self.binaryCPUSubtype = binaryCPUSubtype
        self.deviceAppHash = deviceAppHash
        self.jailbroken = jailbroken
        self.procTranslated = procTranslated
        self.kernelVersion = kernelVersion
        self.machine = machine
        self.memory = memory
        self.model = model
        self.osVersion = osVersion
        self.parentProcessID = parentProcessID
        self.parentProcessName = parentProcessName
        self.processID = processID
        self.processName = processName
        self.systemName = systemName
        self.systemVersion = systemVersion
        self.timeZone = timeZone
        self.storage = storage
        self.freeStorage = freeStorage
        self.buildType = buildType
        self.clangVersion = clangVersion
        self.appMemory = appMemory
        self.lowPowerModeEnabled = lowPowerModeEnabled
    }

    enum CodingKeys: String, CodingKey {
        case cfBundleExecutable = "CFBundleExecutable"
        case cfBundleExecutablePath = "CFBundleExecutablePath"
        case cfBundleIdentifier = "CFBundleIdentifier"
        case cfBundleName = "CFBundleName"
        case cfBundleShortVersionString = "CFBundleShortVersionString"
        case cfBundleVersion = "CFBundleVersion"
        case appStartTime = "app_start_time"
        case appUUID = "app_uuid"
        case applicationStats = "application_stats"
        case bootTime = "boot_time"
        case cpuArch = "cpu_arch"
        case cpuType = "cpu_type"
        case cpuSubtype = "cpu_subtype"
        case binaryArch = "binary_arch"
        case binaryCPUType = "binary_cpu_type"
        case binaryCPUSubtype = "binary_cpu_subtype"
        case deviceAppHash = "device_app_hash"
        case jailbroken
        case procTranslated = "proc_translated"
        case kernelVersion = "kernel_version"
        case machine
        case memory
        case model
        case osVersion = "os_version"
        case parentProcessID = "parent_process_id"
        case parentProcessName = "parent_process_name"
        case processID = "process_id"
        case processName = "process_name"
        case systemName = "system_name"
        case systemVersion = "system_version"
        case timeZone = "time_zone"
        case storage
        case freeStorage
        case buildType = "build_type"
        case clangVersion = "clang_version"
        case appMemory = "app_memory"
        case lowPowerModeEnabled = "low_power_mode_enabled"
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cfBundleExecutable = try c.decodeIfPresent(String.self, forKey: .cfBundleExecutable)
        cfBundleExecutablePath = try c.decodeIfPresent(String.self, forKey: .cfBundleExecutablePath)
        cfBundleIdentifier = try c.decodeIfPresent(String.self, forKey: .cfBundleIdentifier)
        cfBundleName = try c.decodeIfPresent(String.self, forKey: .cfBundleName)
        cfBundleShortVersionString = try c.decodeIfPresent(String.self, forKey: .cfBundleShortVersionString)
        cfBundleVersion = try c.decodeIfPresent(String.self, forKey: .cfBundleVersion)
        appUUID = try c.decodeIfPresent(String.self, forKey: .appUUID)
        applicationStats = try c.decodeIfPresent(ApplicationStats.self, forKey: .applicationStats)
        cpuArch = try c.decodeIfPresent(String.self, forKey: .cpuArch)
        cpuType = try c.decodeIfPresent(Int.self, forKey: .cpuType)
        cpuSubtype = try c.decodeIfPresent(Int.self, forKey: .cpuSubtype)
        binaryArch = try c.decodeIfPresent(String.self, forKey: .binaryArch)
        binaryCPUType = try c.decodeIfPresent(Int.self, forKey: .binaryCPUType)
        binaryCPUSubtype = try c.decodeIfPresent(Int.self, forKey: .binaryCPUSubtype)
        deviceAppHash = try c.decodeIfPresent(String.self, forKey: .deviceAppHash)
        jailbroken = try c.decodeIfPresent(Bool.self, forKey: .jailbroken)
        procTranslated = try c.decodeIfPresent(Bool.self, forKey: .procTranslated)
        kernelVersion = try c.decodeIfPresent(String.self, forKey: .kernelVersion)
        machine = try c.decodeIfPresent(String.self, forKey: .machine)
        memory = try c.decodeIfPresent(MemoryInfo.self, forKey: .memory)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        osVersion = try c.decodeIfPresent(String.self, forKey: .osVersion)
        parentProcessID = try c.decodeIfPresent(Int.self, forKey: .parentProcessID)
        parentProcessName = try c.decodeIfPresent(String.self, forKey: .parentProcessName)
        processID = try c.decodeIfPresent(Int.self, forKey: .processID)
        processName = try c.decodeIfPresent(String.self, forKey: .processName)
        systemName = try c.decodeIfPresent(String.self, forKey: .systemName)
        systemVersion = try c.decodeIfPresent(String.self, forKey: .systemVersion)
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone)
        storage = try c.decodeIfPresent(Int64.self, forKey: .storage)
        freeStorage = try c.decodeIfPresent(Int64.self, forKey: .freeStorage)
        buildType = try c.decodeIfPresent(BuildType.self, forKey: .buildType)
        clangVersion = try c.decodeIfPresent(String.self, forKey: .clangVersion)
        appMemory = try c.decodeIfPresent(AppMemoryInfo.self, forKey: .appMemory)
        lowPowerModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .lowPowerModeEnabled)

        // Dates arrive as ISO 8601 strings from the system stitch
        if let str = try c.decodeIfPresent(String.self, forKey: .appStartTime) {
            appStartTime = Self.parseISO8601(str)
        } else {
            appStartTime = nil
        }
        if let str = try c.decodeIfPresent(String.self, forKey: .bootTime) {
            bootTime = Self.parseISO8601(str)
        } else {
            bootTime = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(cfBundleExecutable, forKey: .cfBundleExecutable)
        try c.encodeIfPresent(cfBundleExecutablePath, forKey: .cfBundleExecutablePath)
        try c.encodeIfPresent(cfBundleIdentifier, forKey: .cfBundleIdentifier)
        try c.encodeIfPresent(cfBundleName, forKey: .cfBundleName)
        try c.encodeIfPresent(cfBundleShortVersionString, forKey: .cfBundleShortVersionString)
        try c.encodeIfPresent(cfBundleVersion, forKey: .cfBundleVersion)
        try c.encodeIfPresent(appUUID, forKey: .appUUID)
        try c.encodeIfPresent(applicationStats, forKey: .applicationStats)
        try c.encodeIfPresent(cpuArch, forKey: .cpuArch)
        try c.encodeIfPresent(cpuType, forKey: .cpuType)
        try c.encodeIfPresent(cpuSubtype, forKey: .cpuSubtype)
        try c.encodeIfPresent(binaryArch, forKey: .binaryArch)
        try c.encodeIfPresent(binaryCPUType, forKey: .binaryCPUType)
        try c.encodeIfPresent(binaryCPUSubtype, forKey: .binaryCPUSubtype)
        try c.encodeIfPresent(deviceAppHash, forKey: .deviceAppHash)
        try c.encodeIfPresent(jailbroken, forKey: .jailbroken)
        try c.encodeIfPresent(procTranslated, forKey: .procTranslated)
        try c.encodeIfPresent(kernelVersion, forKey: .kernelVersion)
        try c.encodeIfPresent(machine, forKey: .machine)
        try c.encodeIfPresent(memory, forKey: .memory)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(osVersion, forKey: .osVersion)
        try c.encodeIfPresent(parentProcessID, forKey: .parentProcessID)
        try c.encodeIfPresent(parentProcessName, forKey: .parentProcessName)
        try c.encodeIfPresent(processID, forKey: .processID)
        try c.encodeIfPresent(processName, forKey: .processName)
        try c.encodeIfPresent(systemName, forKey: .systemName)
        try c.encodeIfPresent(systemVersion, forKey: .systemVersion)
        try c.encodeIfPresent(timeZone, forKey: .timeZone)
        try c.encodeIfPresent(storage, forKey: .storage)
        try c.encodeIfPresent(freeStorage, forKey: .freeStorage)
        try c.encodeIfPresent(buildType, forKey: .buildType)
        try c.encodeIfPresent(clangVersion, forKey: .clangVersion)
        try c.encodeIfPresent(appMemory, forKey: .appMemory)
        try c.encodeIfPresent(lowPowerModeEnabled, forKey: .lowPowerModeEnabled)

        if let appStartTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try c.encode(formatter.string(from: appStartTime), forKey: .appStartTime)
        }
        if let bootTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try c.encode(formatter.string(from: bootTime), forKey: .bootTime)
        }
    }
}
