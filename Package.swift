// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "KSCrash",
    platforms: [
        .iOS(.v11),
        .tvOS(.v11),
        .watchOS(.v4),
        .macOS(.v10_13),
    ],
    products: [
        .library(
            name: "Reporting",
            targets: [
                "KSCrashFilters",
                "KSCrashSinks",
                "KSCrashInstallations",
            ]
        ),
        .library(name: "Filters", targets: ["KSCrashFilters"]),
        .library(name: "Sinks", targets: ["KSCrashSinks"]),
        .library(name: "Installations", targets: ["KSCrashInstallations"]),
        .library(name: "Recording", targets: ["KSCrashRecording"]
        ),
    ],
    targets: [
        .target(
            name: "KSCrashRecording",
            dependencies: [
                "KSCrashRecordingCore",
            ],
            cSettings: [.headerSearchPath("Monitors")]
        ),
        .target(
            name: "KSCrashFilters",
            dependencies: [
                "KSCrashRecording",
                "KSCrashRecordingCore",
                "KSCrashReportingCore",
            ]
        ),
        .target(
            name: "KSCrashSinks",
            dependencies: [
                "KSCrashRecording",
                "KSCrashFilters",
            ]
        ),.target(
            name: "KSCrashInstallations",
            dependencies: [
                "KSCrashFilters",
                "KSCrashSinks",
                "KSCrashRecording",
            ]
        ),
        .target(
            name: "KSCrashRecordingCore",
            dependencies: [
                "KSCrashCore",
                "KSCrashSwift",
                "KSCrashLLVM",
            ]
        ),
        .target(
            name: "KSCrashReportingCore",
            dependencies: ["KSCrashCore"]
        ),
        .target(name: "KSCrashCore"),
        //MARK: - Forks
        .target(
            name: "KSCrashSwift",
            dependencies: ["KSCrashLLVM"]
        ),
        .target(name: "KSCrashLLVM"),
    ],
    cxxLanguageStandard: .gnucxx11
)
