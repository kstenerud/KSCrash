import ProjectDescription

let project = Project(
    name: "KSCrashSamples",
    packages: [
        .local(path: "Common"),
    ],
    targets: [
        .target(
            name: "iOS",
            destinations: .iOS,
            product: .app,
            bundleId: .bundleId(for: "iOS"),
            infoPlist: InfoPlist.extendingDefault(with: [
                "UILaunchScreen": [
                    "UIImageName": "LaunchImage",
                    "UIBackgroundColor": "LaunchScreenColor",
                ],
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "CFBundleDisplayName": "KSCrash iOS",
            ]),
            sources: ["Sources/**"],
            dependencies: .sample
        ),
        .target(
            name: "macOS",
            destinations: .macOS,
            product: .app,
            bundleId: .bundleId(for: "macOS"),
            infoPlist: InfoPlist.extendingDefault(with: [
                "CFBundleDisplayName": "KSCrash macOS",
            ]),
            sources: ["Sources/**"],
            dependencies: .sample
        ),
        .target(
            name: "tvOS",
            destinations: .tvOS,
            product: .app,
            bundleId: .bundleId(for: "tvOS"),
            infoPlist: InfoPlist.extendingDefault(with: [
                "CFBundleDisplayName": "KSCrash tvOS",
            ]),
            sources: ["Sources/**"],
            dependencies: .sample
        ),
        .target(
            name: "visionOS",
            destinations: .visionOS,
            product: .app,
            bundleId: .bundleId(for: "visionOS"),
            infoPlist: InfoPlist.extendingDefault(with: [
                "CFBundleDisplayName": "KSCrash visionOS",
            ]),
            sources: ["Sources/**"],
            dependencies: .sample
        ),
        .target(
            name: "watchOS",
            destinations: .watchOS,
            product: .app,
            bundleId: .bundleId(for: "watchOS"),
            infoPlist: InfoPlist.extendingDefault(with: [
                "CFBundleDisplayName": "KSCrash watchOS",
                "WKApplication": true,
                "WKWatchOnly": true,
            ]),
            sources: ["Sources/**"],
            dependencies: .sample
        ),
    ]
)

extension String {
    static func bundleId(for target: StringLiteralType) -> Self {
        "com.github.kstenerud.KSCrash.\(target)"
    }
}

extension Array where Element == TargetDependency {
    static var sample: Self {
        [
            .package(product: "SampleUI", type: .runtime),
        ]
    }
}
