import ProjectDescription

let project = Project(
    name: "KSCrashSamples",
    packages: [
        .local(path: "Common"),
    ],
    targets: [
        .target(
            name: "Sample",
            destinations: .allForSample,
            product: .app,
            bundleId: "com.github.kstenerud.KSCrash.Sample",
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
            ]
        ),
        .target(
            name: "SampleTests",
            destinations: .allForSample.subtracting(.visionOS),
            product: .uiTests,
            bundleId: "com.github.kstenerud.KSCrash.Sample.Tests",
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "Sample"),
                .package(product: "SampleUI", type: .runtime),
                .package(product: "CrashTriggers", type: .runtime),
                .package(product: "IntegrationTestsHelper", type: .runtime),
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
        ),
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
