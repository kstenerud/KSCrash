// swift-tools-version:5.3

@preconcurrency import PackageDescription

let package = Package(
    name: "CrashLibA",
    products: [
        .library(
            name: "CrashLibA",
            targets: ["CrashLibA"]
        )
    ],
    targets: [
        .target(
            name: "CrashLibA",
            dependencies: [
                .target(name: "KSCrashLibA")
            ],
            cSettings: [
                .define("KSCRASH_NAMESPACE", to: "CrashLibA")
            ],
            cxxSettings: [
                .define("KSCRASH_NAMESPACE", to: "CrashLibA")
            ],
        ),

        .target(
            name: "KSCrashLibA",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .define("KSCRASH_NAMESPACE", to: "CrashLibA"),
                .headerSearchPath("Monitors"),
            ],
            cxxSettings: [
                .define("KSCRASH_NAMESPACE", to: "CrashLibA"),
                .headerSearchPath("Monitors"),
            ]
        ),
    ],
    cxxLanguageStandard: .gnucxx11
)
