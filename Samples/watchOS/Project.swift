import ProjectDescription

let project = Project(
    name: "watchOS",
    packages: [
        .local(path: "../Common"),
    ],
    targets: [
        .target(
            name: "watchOS",
            destinations: .watchOS,
            product: .app,
            bundleId: "com.github.kstenerud.KSCrash.watchOS",
            infoPlist: InfoPlist.extendingDefault(with: [
                "CFBundleDisplayName": "KSCrash watchOS",
                "WKApplication": true,
                "WKWatchOnly": true,
            ]),
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "SampleUI", type: .runtime),
            ]
        ),
    ]
)
