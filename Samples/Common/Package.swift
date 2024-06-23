// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "KSCrashSamplesCommon",
  platforms: [
    .iOS(.v13),
    .tvOS(.v13),
    .watchOS(.v6),
    .macOS(.v10_15),
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
      name: "SampleUI",
      targets: ["SampleUI"]
    ),
  ],
  dependencies: [
    .package(path: "../.."),
  ],
  targets: [
    .target(
      name: "LibraryBridge",
      dependencies: [
        .productItem(name: "Recording", package: "KSCrash"),
        .productItem(name: "Reporting", package: "KSCrash"),
      ]
    ),
    .target(
      name: "CrashTriggers"
    ),
    .target(
      name: "SampleUI",
      dependencies: [
        .target(name: "LibraryBridge"),
        .target(name: "CrashTriggers"),
      ]
    )
  ]
)
