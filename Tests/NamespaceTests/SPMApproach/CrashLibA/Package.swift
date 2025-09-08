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
                .define("KSCRASH_NAMESPACE", to: "CrashLibA"),
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
