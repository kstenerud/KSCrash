// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "KSCrashSamplesCommon",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "LibraryBridge",
            targets: ["LibraryBridge"]
        ),
        .library(
            name: "CrashTriggers",
            targets: ["CrashTriggers"]
        ),
        .library(
            name: "IntegrationTestsHelper",
            targets: ["IntegrationTestsHelper"]
        ),
        .library(
            name: "SampleUI",
            targets: ["SampleUI"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "LibraryBridge",
            dependencies: [
                .product(name: "Recording", package: "KSCrash"),
                .product(name: "Reporting", package: "KSCrash"),
                .product(name: "DemangleFilter", package: "KSCrash"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "CrashTriggers"
        ),
        .target(
            name: "IntegrationTestsHelper",
            dependencies: [
                .target(name: "CrashTriggers"),
                .product(name: "Recording", package: "KSCrash"),
                .product(name: "Reporting", package: "KSCrash"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "SampleUI",
            dependencies: [
                .target(name: "LibraryBridge"),
                .target(name: "CrashTriggers"),
                .target(name: "IntegrationTestsHelper"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
