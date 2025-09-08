// swift-tools-version:5.3

@preconcurrency import PackageDescription

let package = Package(
    name: "CrashLibB",
    products: [
        .library(
            name: "CrashLibB",
            targets: ["CrashLibB"]
        )
    ],
    targets: [
        .target(
            name: "CrashLibB",
            dependencies: [
                .target(name: "KSCrashLibB")
            ],
            cSettings: [
                .define("KSCRASH_NAMESPACE", to: "CrashLibB")
            ],
            cxxSettings: [
                .define("KSCRASH_NAMESPACE", to: "CrashLibB")
            ],
        ),

        .target(
            name: "KSCrashLibB",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .define("KSCRASH_NAMESPACE", to: "CrashLibB"),
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .headerSearchPath("swift"),
                .headerSearchPath("swift/Basic"),
                .headerSearchPath("llvm"),
                .headerSearchPath("llvm/ADT"),
                .headerSearchPath("llvm/Config"),
                .headerSearchPath("llvm/Support"),
            ],
            cxxSettings: [
                .define("KSCRASH_NAMESPACE", to: "CrashLibB"),
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .headerSearchPath("swift"),
                .headerSearchPath("swift/Basic"),
                .headerSearchPath("llvm"),
                .headerSearchPath("llvm/ADT"),
                .headerSearchPath("llvm/Config"),
                .headerSearchPath("llvm/Support"),
            ]
        ),
    ],
    cxxLanguageStandard: .gnucxx11
)
