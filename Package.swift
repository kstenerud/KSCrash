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
            name: "Filters",
            targets: [
                "FiltersBase",
//                "FiltersBasic",
            ]
        ),
        .library(
            name: "Recording",
            targets: ["Recording"]
        ),
    ],
    targets: [
        .target(
            name: "Recording",
            dependencies: [
                "RecordingTools",
                "FiltersBase",
            ],
            cSettings: [.headerSearchPath("Monitors")]
        ),
        .target(
            name: "RecordingTools",
            dependencies: [
                "RecordingToolsCxx",
                "KSCrashLLVM",
            ]
        ),
        .target(
            name: "RecordingToolsCxx",
            dependencies: ["KSCrashSwift"]
        ),
        .target(
            name: "KSCrashSwift",
            dependencies: [
                "KSCrashLLVM"
            ]
        ),
        .target(name: "KSCrashLLVM"),

        .target(name: "FiltersBase"),
        .target(
            name: "FiltersTools",
            publicHeadersPath: "."
        ),
//        .target(name: "FiltersBasic"),
    ],
    cxxLanguageStandard: .gnucxx11
)
