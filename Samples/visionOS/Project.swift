import ProjectDescription

let project = Project(
    name: "visionOS",
    packages: [
        .local(path: "../Common"),
    ],
    targets: [
        .target(
            name: "visionOS",
            destinations: .visionOS,
            product: .app,
            bundleId: "com.github.kstenerud.KSCrash.visionOS",
            infoPlist: InfoPlist.extendingDefault(with: [
                "CFBundleDisplayName": "KSCrash visionOS",
            ]),
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "SampleUI", type: .runtime),
            ]
        ),
    ]
)
