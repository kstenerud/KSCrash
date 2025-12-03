// swift-tools-version:5.3

@preconcurrency import PackageDescription

let warningFlags: [String] = []

let package = Package(
    name: "KSCrash",
    platforms: [
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v5),
        .macOS(.v10_14),
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
    ],
    targets: [
        .target(
            name: Targets.recording,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .unsafeFlags(warningFlags),
            ],
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
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
                .target(name: Targets.recordingCore)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.discSpaceMonitor.tests,
            dependencies: [
                .target(name: Targets.discSpaceMonitor),
                .target(name: Targets.recordingCore),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.bootTimeMonitor,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.bootTimeMonitor.tests,
            dependencies: [
                .target(name: Targets.bootTimeMonitor),
                .target(name: Targets.recordingCore),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
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
            name: Targets.testTools,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
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
    static let testTools = "KSCrashTestTools"
}

extension String {
    var tests: String {
        return "\(self)Tests"
    }
}
