// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "KSCrash",
    products: [
        .library(
            name: "KSCrash",
            targets: [
                "KSCrash/Installations",
                "KSCrash/Recording",
                "KSCrash/Recording/Monitors",
                "KSCrash/Recording/Tools",
                "KSCrash/Reporting/Filters",
                "KSCrash/Reporting/Filters/Tools",
                "KSCrash/Reporting/Tools",
                "KSCrash/Reporting/Sinks",
                "KSCrash/swift/Basic"
            ]
        )
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "KSCrash/Installations",
            path: "Source/KSCrash/Installations",
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../Recording"),
                .headerSearchPath("../Recording/Monitors"),
                .headerSearchPath("../Recording/Tools"),
                .headerSearchPath("../Reporting/Filters"),
                .headerSearchPath("../Reporting/Sinks"),
                .headerSearchPath("../Reporting/Tools"),
            ]
        ),
        .target(
            name: "KSCrash/Recording",
            path: "Source/KSCrash/Recording",
            exclude: [
                "Monitors",
                "Tools"
            ],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("Tools"),
                .headerSearchPath("Monitors"),
                .headerSearchPath("../Reporting/Filters")
            ]
        ),
        .target(
            name: "KSCrash/Recording/Monitors",
            path: "Source/KSCrash/Recording/Monitors",
            publicHeadersPath: ".",
            cxxSettings: [
                .define("GCC_ENABLE_CPP_EXCEPTIONS", to: "YES"),
                .headerSearchPath(".."),
                .headerSearchPath("../Tools"),
                .headerSearchPath("../../Reporting/Filters")
            ]
        ),
        .target(
            name: "KSCrash/Recording/Tools",
            path: "Source/KSCrash/Recording/Tools",
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath(".."),
                .headerSearchPath("../../swift"),
                .headerSearchPath("../../swift/Basic"),
                .headerSearchPath("../../llvm/ADT"),
                .headerSearchPath("../../llvm/Support"),
                .headerSearchPath("../../llvm/Config")
            ]
        ),
        .target(
            name: "KSCrash/Reporting/Filters",
            path: "Source/KSCrash/Reporting/Filters",
            exclude: [
                "Tools"
            ],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("Tools"),
                .headerSearchPath("../../Recording"),
                .headerSearchPath("../../Recording/Monitors"),
                .headerSearchPath("../../Recording/Tools")
            ]
        ),
        .target(
            name: "KSCrash/Reporting/Filters/Tools",
            path: "Source/KSCrash/Reporting/Filters/Tools",
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../../../Recording/Tools")
            ]
        ),
        .target(
            name: "KSCrash/Reporting/Tools",
            path: "Source/KSCrash/Reporting/Tools",
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../../Recording"),
                .headerSearchPath("../../Recording/Tools")
            ]
        ),
        .target(
            name: "KSCrash/Reporting/Sinks",
            path: "Source/KSCrash/Reporting/Sinks",
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../Filters"),
                .headerSearchPath("../Filters/Tools"),
                .headerSearchPath("../Tools"),
                .headerSearchPath("../../Recording"),
                .headerSearchPath("../../Recording/Tools"),
                .headerSearchPath("../../Recording/Monitors")
            ]
        ),
        .target(
            name: "KSCrash/swift/Basic",
            path: "Source/KSCrash/swift/Basic",
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath(".."),
                .headerSearchPath("../../llvm/ADT"),
                .headerSearchPath("../../llvm/Config"),
                .headerSearchPath("../../llvm/Support")
            ]
        )
    ],
    cxxLanguageStandard: .gnucxx11
)
