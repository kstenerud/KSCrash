import ProjectDescription

let project = Project(
    name: "KSCrashSamples",
    packages: [
        .local(path: "Common")
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0"
    ]),
    targets: [
        .target(
            name: "Sample",
            destinations: .allForSample,
            product: .app,
            bundleId: "com.github.kstenerud.KSCrash.Sample",
            deploymentTargets: .allForSample,
            infoPlist: InfoPlist.extendingDefault(with: [
                "UILaunchScreen": [
                    "UIImageName": "LaunchImage",
                    "UIBackgroundColor": "LaunchScreenColor",
                ],
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "CFBundleDisplayName": "KSCrashSample",
                "WKApplication": true,
                "WKWatchOnly": true,
            ]),
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "SampleUI", type: .runtime),
                .package(product: "KSCrash", type: .runtime),
            ],
            // Empty unless a build names one. The Enhanced Security integration lane passes
            // KSCRASH_SAMPLE_ENTITLEMENTS=EnhancedSecurity.entitlements (with
            // ENABLE_POINTER_AUTHENTICATION=YES) to build the app the way an app adopting that
            // capability is built. Scoped to this target: set on the command line instead, it
            // would reach every package target too.
            settings: .settings(base: [
                "CODE_SIGN_ENTITLEMENTS": "$(KSCRASH_SAMPLE_ENTITLEMENTS)"
            ])
        ),
        // The integration tests run on the Mac whatever platform they drive, and launch the
        // Sample app themselves (see Tests/Core/TargetApp.swift). They must not depend on the
        // Sample target: that would make the app their test host.
        .target(
            name: "SampleTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.github.kstenerud.KSCrash.Sample.Tests",
            deploymentTargets: .macOS("13.0"),
            sources: ["Tests/**"],
            dependencies: [
                .package(product: "SampleUI", type: .runtime),
                .package(product: "CrashTriggers", type: .runtime),
                .package(product: "CrashCallback", type: .runtime),
                .package(product: "IntegrationTestsHelper", type: .runtime),
                .package(product: "Report", type: .runtime),
            ],
            additionalFiles: ["Tests/Integration.xctestplan"]
        ),
    ],
    schemes: [
        .scheme(
            name: "Sample",
            shared: true,
            buildAction: .buildAction(targets: ["Sample"]),
            testAction: .testPlans(["Tests/Integration.xctestplan"], configuration: .release, attachDebugger: false),
            runAction: .runAction(executable: "Sample")
        )
    ]
)

extension Set where Element == ProjectDescription.Destination {
    static var allForSample: Self {
        let sets: [Set<Destination>] = [
            .iOS,
            .macOS,
            .tvOS,
            .watchOS,
            .visionOS,
        ]
        return sets.reduce(.init()) { $0.union($1) }
    }
}

extension DeploymentTargets {
    static var allForSample: Self {
        .multiplatform(
            iOS: "15.0",
            macOS: "13.0",
            watchOS: "8.0",
            tvOS: "15.0",
            visionOS: "1.0"
        )
    }
}
