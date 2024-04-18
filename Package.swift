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
                "ReportingTools",
                "ReportingSinks",
                "FilterBase",
                "FilterAlert",
                "FilterAppleFmt",
                "FilterBasic",
                "FilterStringify",
                "FilterGZip",
                "FilterJSON",
                "FilterSets",
            ]
        ),
        .library(
            name: "Recording",
            targets: ["Recording"]
        ),
        .library(
            name: "Installations",
            targets: ["Installations"]
        ),
        .library(
            name: "Core",
            targets: ["Core"]
        ),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                "FilterBasic",
                "Recording", // KSCrashReportWriter
                "ReportingTools", // KSCString
            ]
        ),
        .target(
            name: "Installations",
            dependencies: [
                "Core",
                "Recording",
                "FilterBase",
                "ReportingSinks",
            ]
        ),
        //MARK: - Recording
        .target(
            name: "Recording",
            dependencies: [
                "RecordingTools",
                "FilterBase",
            ],
            cSettings: [.headerSearchPath("Monitors")]
        ),
        .target(
            name: "RecordingTools",
            dependencies: [
                "CommonTools",
                "KSCrashSwift",
                "KSCrashLLVM",
            ]
        ),
        .target(name: "CommonTools"),
        //MARK: - Peporting
        .target(
            name: "ReportingTools",
            dependencies: ["CommonTools"],
            linkerSettings: [
                .linkedFramework("SystemConfiguration", .when(platforms: [.iOS, .tvOS, .macOS]))
            ]
        ),
        .target(
            name: "ReportingSinks",
            dependencies: [
                "CommonTools",
                "ReportingTools",
                "FilterBase",
                "FilterAlert",
                "FilterAppleFmt",
                "FilterBasic",
                "FilterStringify",
                "FilterGZip",
                "FilterJSON",
            ],
            linkerSettings: [
                .linkedFramework("MessageUI", .when(platforms: [.iOS]))
            ]
        ),
        // MARK: - Filters
        .target(name: "FilterBase"),
        .target(
            name: "FilterTools",
            dependencies: ["CommonTools"]
        ),
        .target(
            name: "FilterAlert",
            dependencies: [
                "FilterBase",
                "CommonTools",
                "RecordingTools", // KSLogger
            ]
        ),
        .target(
            name: "FilterAppleFmt",
            dependencies: [
                "FilterBase",
                "Recording", // KSCrashReportFields
            ]
        ),
        .target(
            name: "FilterBasic",
            dependencies: [
                "CommonTools",
                "FilterBase",
                "FilterTools",
                "RecordingTools", // KSLogger
            ]
        ),
        .target(
            name: "FilterStringify",
            dependencies: ["FilterBase"]
        ),
        .target(
            name: "FilterGZip",
            dependencies: [
                "FilterBase",
                "FilterTools",
            ]
        ),
        .target(
            name: "FilterJSON",
            dependencies: [
                "FilterBase",
                "RecordingTools", // KSJSONCodecObjC
            ]
        ),
        .target(
            name: "FilterSets",
            dependencies: [
                "Recording", // KSCrashReportFields
                "FilterBase",
                "FilterAlert",
                "FilterAppleFmt",
                "FilterBasic",
                "FilterStringify",
                "FilterGZip",
                "FilterJSON",
            ]
        ),
        //MARK: - Forks
        .target(
            name: "KSCrashSwift",
            dependencies: ["KSCrashLLVM"]
        ),
        .target(name: "KSCrashLLVM"),
    ],
    cxxLanguageStandard: .gnucxx11
)
