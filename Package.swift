// swift-tools-version:5.3

import PackageDescription

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
      resources: [
        .copy("Resources/PrivacyInfo.xcprivacy")
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
        .process("Resources")
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
      ],
      resources: [
        .copy("Resources/PrivacyInfo.xcprivacy")
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
      ],
      resources: [
        .copy("Resources/PrivacyInfo.xcprivacy")
      ]
    ),

    .target(
      name: "KSCrashInstallations",
      dependencies: [
        "KSCrashFilters",
        "KSCrashSinks",
        "KSCrashRecording",
      ],
      resources: [
        .copy("Resources/PrivacyInfo.xcprivacy")
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
      resources: [
        .copy("Resources/PrivacyInfo.xcprivacy")
      ],
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
      dependencies: ["KSCrashCore"],
      resources: [
        .copy("Resources/PrivacyInfo.xcprivacy")
      ]
    ),
    .testTarget(
      name: "KSCrashReportingCoreTests",
      dependencies: [
        "KSCrashReportingCore",
        "KSCrashCore",
      ]
    ),

    .target(
      name: "KSCrashCore",
      resources: [
        .copy("Resources/PrivacyInfo.xcprivacy")
      ]
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
