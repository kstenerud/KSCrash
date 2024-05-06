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
    .library(
      name: "Filters",
      targets: ["KSCrashFilters"]
    ),
    .library(
      name: "Sinks",
      targets: ["KSCrashSinks"]
    ),
    .library(
      name: "Installations",
      targets: ["KSCrashInstallations"]
    ),
    .library(
      name: "Recording",
      targets: ["KSCrashRecording"]
    ),
  ],
  targets: [
    .target(
      name: "KSCrashRecording",
      dependencies: [
        "KSCrashRecordingCore"
      ],
      cSettings: [.headerSearchPath("Monitors")]
    ),
    .testTarget(
      name: "KSCrashRecordingTests",
      dependencies: [
        "KSCrashTestTools",
        "KSCrashRecording",
        "KSCrashRecordingCore",
      ],
      resources: [
        .process("Resources"),
      ],
      cSettings: [
        .headerSearchPath("../../Sources/KSCrashRecording"),
        .headerSearchPath("../../Sources/KSCrashRecording/Monitors"),
      ]
    ),

    .target(
      name: "KSCrashFilters",
      dependencies: [
        "KSCrashRecording",
        "KSCrashRecordingCore",
        "KSCrashReportingCore",
      ]
    ),
    .testTarget(
      name: "KSCrashFiltersTests",
      dependencies: [
        "KSCrashFilters",
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
    ),

    .target(
      name: "KSCrashInstallations",
      dependencies: [
        "KSCrashFilters",
        "KSCrashSinks",
        "KSCrashRecording",
      ]
    ),
    .testTarget(
      name: "KSCrashInstallationsTests",
      dependencies: [
        "KSCrashInstallations",
        "KSCrashFilters",
        "KSCrashSinks",
        "KSCrashRecording",
      ]
    ),

    .target(
      name: "KSCrashRecordingCore",
      dependencies: ["KSCrashCore"],
      cSettings: [
        .headerSearchPath("swift"),
        .headerSearchPath("swift/Basic"),
        .headerSearchPath("llvm"),
        .headerSearchPath("llvm/ADT"),
        .headerSearchPath("llvm/Config"),
        .headerSearchPath("llvm/Support"),
      ]
    ),
    .testTarget(
      name: "KSCrashRecordingCoreTests",
      dependencies: [
        "KSCrashTestTools",
        "KSCrashRecordingCore",
        "KSCrashCore",
      ]
    ),

    .target(
      name: "KSCrashReportingCore",
      dependencies: ["KSCrashCore"]
    ),
    .testTarget(
      name: "KSCrashReportingCoreTests",
      dependencies: [
        "KSCrashReportingCore",
        "KSCrashCore",
      ]
    ),

    .target(
      name: "KSCrashCore"
    ),
    .testTarget(
      name: "KSCrashCoreTests",
      dependencies: ["KSCrashCore"]
    ),

    .target(
      name: "KSCrashTestTools",
      dependencies: ["KSCrashRecordingCore"]
    ),
  ],
  cxxLanguageStandard: .gnucxx11
)
