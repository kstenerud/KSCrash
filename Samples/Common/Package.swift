// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "KSCrashSamplesCommon",
  platforms: [
    .iOS(.v14),
    .tvOS(.v14),
    .watchOS(.v7),
    .macOS(.v11),
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
        .product(name: "Recording", package: "KSCrash"),
        .product(name: "Reporting", package: "KSCrash"),
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
