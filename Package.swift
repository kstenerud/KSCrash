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
  ],
  targets: [
    .target(
      name: Targets.recording,
      dependencies: [
        .target(name: Targets.recordingCore)
      ],
      resources: privacyResources,
      cSettings: [.headerSearchPath("Monitors")]
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
      ]
    ),

    .target(
      name: Targets.filters,
      dependencies: [
        .target(name: Targets.recording),
        .target(name: Targets.recordingCore),
        .target(name: Targets.reportingCore),
      ],
      resources: privacyResources
    ),
    .testTarget(
      name: Targets.filters.tests,
      dependencies: [
        .target(name: Targets.filters),
        .target(name: Targets.recording),
        .target(name: Targets.recordingCore),
        .target(name: Targets.reportingCore),
      ]
    ),

    .target(
      name: Targets.sinks,
      dependencies: [
        .target(name: Targets.recording),
        .target(name: Targets.filters),
      ],
      resources: privacyResources
    ),

    .target(
      name: Targets.installations,
      dependencies: [
        .target(name: Targets.filters),
        .target(name: Targets.sinks),
        .target(name: Targets.recording),
      ],
      resources: privacyResources
    ),
    .testTarget(
      name: Targets.installations.tests,
      dependencies: [
        .target(name: Targets.installations),
        .target(name: Targets.filters),
        .target(name: Targets.sinks),
        .target(name: Targets.recording),
      ]
    ),

    .target(
      name: Targets.recordingCore,
      dependencies: [
        .target(name: Targets.core)
      ],
      resources: privacyResources,
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
      name: Targets.recordingCore.tests,
      dependencies: [
        .target(name: Targets.testTools),
        .target(name: Targets.recordingCore),
        .target(name: Targets.core),
      ]
    ),

    .target(
      name: Targets.reportingCore,
      dependencies: [
        .target(name: Targets.core)
      ],
      resources: privacyResources
    ),
    .testTarget(
      name: Targets.reportingCore.tests,
      dependencies: [
        .target(name: Targets.reportingCore),
        .target(name: Targets.core),
      ]
    ),

    .target(
      name: Targets.core,
      resources: privacyResources
    ),
    .testTarget(
      name: Targets.core.tests,
      dependencies: [
        .target(name: Targets.core)
      ]
    ),

    .target(
      name: Targets.testTools,
      dependencies: [
        .target(name: Targets.recordingCore)
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
  static let reportingCore = "KSCrashReportingCore"
  static let core = "KSCrashCore"
  static let testTools = "KSCrashTestTools"
}

extension String {
  var tests: String {
    return "\(self)Tests"
  }
}

let privacyResources: [Resource] = [
  .copy("Resources/PrivacyInfo.xcprivacy")
]
