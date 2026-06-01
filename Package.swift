// swift-tools-version:5.9

@preconcurrency import PackageDescription

let metricKitSwiftSettings: [SwiftSetting] = [
    .define("KSCRASH_HAS_METRICKIT", .when(platforms: [.iOS, .macOS, .visionOS]))
]

let warningFlags: [String] = []

let package = Package(
    name: "KSCrash",
    platforms: [
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v5),
        .macOS(.v10_14),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "Reporting",
            targets: [
                Targets.filters,
                Targets.sinks,
                Targets.installations,
            ]
        ),
        .library(
            name: "Filters",
            targets: [Targets.filters]
        ),
        .library(
            name: "Sinks",
            targets: [Targets.sinks]
        ),
        .library(
            name: "Installations",
            targets: [Targets.installations]
        ),
        .library(
            name: "Recording",
            targets: [Targets.recording]
        ),
        .library(
            name: "RecordingCore",
            targets: [Targets.recordingCore]
        ),
        .library(
            name: "DiscSpaceMonitor",
            targets: [Targets.discSpaceMonitor]
        ),
        .library(
            name: "BootTimeMonitor",
            targets: [Targets.bootTimeMonitor]
        ),
        .library(
            name: "DemangleFilter",
            targets: [Targets.demangleFilter]
        ),
        .library(
            name: "Profiler",
            targets: [Targets.profiler]
        ),
        .library(
            name: "Monitors",
            targets: [Targets.monitors]
        ),
        .library(
            name: "Report",
            targets: [Targets.report]
        ),
    ],
    targets: [
        .target(
            name: Targets.recording,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.core),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .headerSearchPath("../KSCrashRecordingCore/include"),  // For internal Unwind/ headers
                .unsafeFlags(warningFlags),
            ],
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .headerSearchPath("../KSCrashRecordingCore/include"),  // For internal Unwind/ headers
                .unsafeFlags(warningFlags),
            ]
        ),
        .testTarget(
            name: Targets.recording.tests,
            dependencies: [
                .target(name: Targets.testTools),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
            ],
            resources: [
                .process("Resources")
            ],
            cSettings: [
                .headerSearchPath("../../Sources/\(Targets.recording)"),
                .headerSearchPath("../../Sources/\(Targets.recording)/Monitors"),
                .headerSearchPath("../../Sources/\(Targets.recordingCore)/include"),  // For internal Unwind/ headers
                .unsafeFlags(warningFlags),
            ]
        ),

        .target(
            name: Targets.filters,
            dependencies: [
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.reportingCore),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.filters.tests,
            dependencies: [
                .target(name: Targets.filters),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.reportingCore),
            ],
            resources: [
                .process("Resources")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.sinks,
            dependencies: [
                .target(name: Targets.recording),
                .target(name: Targets.filters),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.installations,
            dependencies: [
                .target(name: Targets.filters),
                .target(name: Targets.sinks),
                .target(name: Targets.recording),
                .target(name: Targets.demangleFilter),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.installations.tests,
            dependencies: [
                .target(name: Targets.installations),
                .target(name: Targets.filters),
                .target(name: Targets.sinks),
                .target(name: Targets.recording),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.recordingCore,
            dependencies: [
                .target(name: Targets.core)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.recordingCore.tests,
            dependencies: [
                .target(name: Targets.testTools),
                .target(name: Targets.recordingCore),
                .target(name: Targets.core),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.recordingCoreSwift.tests,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.reportingCore,
            dependencies: [
                .target(name: Targets.core)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: Targets.reportingCore.tests,
            dependencies: [
                .target(name: Targets.reportingCore),
                .target(name: Targets.core),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.core,
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.core.tests,
            dependencies: [
                .target(name: Targets.core)
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.discSpaceMonitor,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .headerSearchPath("../\(Targets.recording)/Monitors"),
                .unsafeFlags(warningFlags),
            ]
        ),
        .testTarget(
            name: Targets.discSpaceMonitor.tests,
            dependencies: [
                .target(name: Targets.discSpaceMonitor),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
            ],
            cSettings: [
                .headerSearchPath("../../Sources/\(Targets.recording)/Monitors"),
                .unsafeFlags(warningFlags),
            ]
        ),

        .target(
            name: Targets.bootTimeMonitor,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .headerSearchPath("../\(Targets.recording)/Monitors"),
                .unsafeFlags(warningFlags),
            ]
        ),
        .testTarget(
            name: Targets.bootTimeMonitor.tests,
            dependencies: [
                .target(name: Targets.bootTimeMonitor),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
            ],
            cSettings: [
                .headerSearchPath("../../Sources/\(Targets.recording)/Monitors"),
                .unsafeFlags(warningFlags),
            ]
        ),

        .target(
            name: Targets.demangleFilter,
            dependencies: [
                .target(name: Targets.recording)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ],
            cxxSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.demangleFilter.tests,
            dependencies: [
                .target(name: Targets.demangleFilter),
                .target(name: Targets.recording),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.report,
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: Targets.report.tests,
            dependencies: [
                .target(name: Targets.report)
            ],
            resources: [
                .process("Resources")
            ]
        ),

        .target(
            name: Targets.testTools,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .testTarget(
            name: Targets.benchmarks,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
                .target(name: Targets.profiler),
            ]
        ),

        .testTarget(
            name: Targets.objcBenchmarks,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
            ],
            cSettings: [
                .headerSearchPath("../../Sources/\(Targets.recording)")
            ]
        ),

        .testTarget(
            name: Targets.coldBenchmarks,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
            ]
        ),

        .target(
            name: Targets.swiftCore
        ),
        .testTarget(
            name: Targets.swiftCore.tests,
            dependencies: [
                .target(name: Targets.swiftCore)
            ]
        ),

        .target(
            name: Targets.profiler,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
                .target(name: Targets.swiftCore),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: Targets.profiler.tests,
            dependencies: [
                .target(name: Targets.profiler)
            ]
        ),

        .target(
            name: Targets.monitors,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
                .target(name: Targets.report),
                .target(name: Targets.swiftCore),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            swiftSettings: metricKitSwiftSettings
        ),
        .testTarget(
            name: Targets.monitors.tests,
            dependencies: [
                .target(name: Targets.monitors),
                .target(name: Targets.report),
            ],
            swiftSettings: metricKitSwiftSettings
        ),
    ],
    cxxLanguageStandard: .gnucxx11
)

enum Targets {
    static let recording = "KSCrashRecording"
    static let filters = "KSCrashFilters"
    static let sinks = "KSCrashSinks"
    static let installations = "KSCrashInstallations"
    static let recordingCore = "KSCrashRecordingCore"
    static let recordingCoreSwift = "KSCrashRecordingCoreSwift"
    static let reportingCore = "KSCrashReportingCore"
    static let core = "KSCrashCore"
    static let discSpaceMonitor = "KSCrashDiscSpaceMonitor"
    static let bootTimeMonitor = "KSCrashBootTimeMonitor"
    static let demangleFilter = "KSCrashDemangleFilter"
    static let report = "KSCrashReportModel"
    static let testTools = "KSCrashTestTools"
    static let benchmarks = "KSCrashBenchmarks"
    static let objcBenchmarks = "KSCrashBenchmarksObjC"
    static let coldBenchmarks = "KSCrashBenchmarksCold"
    static let swiftCore = "KSCrashSwiftCore"
    static let profiler = "KSCrashProfiler"
    static let monitors = "KSCrashMonitors"
}

extension String {
    var tests: String {
        return "\(self)Tests"
    }
}
