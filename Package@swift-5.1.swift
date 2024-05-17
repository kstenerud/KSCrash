// swift-tools-version:5.1

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
      dependencies: [
        "KSCrashCore",
        "KSCrashSwift",
        "KSCrashLLVM",
      ]
    ),
    .testTarget(
      name: "KSCrashRecordingCoreTests",
      dependencies: [
        "KSCrashTestTools",
        "KSCrashRecordingCore",
        "KSCrashCore",
        "KSCrashSwift",
        "KSCrashLLVM",
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
    //MARK: - Forks
    .target(
      name: "KSCrashSwift",
      dependencies: ["KSCrashLLVM"]
    ),
    .target(
      name: "KSCrashLLVM"
    ),
  ],
  cxxLanguageStandard: .gnucxx11
)
