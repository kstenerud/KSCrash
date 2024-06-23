import ProjectDescription

let project = Project(
    name: "tvOS",
    packages: [
        .local(path: "../Common"),
    ],
    targets: [
        .target(
            name: "tvOS",
            destinations: .tvOS,
            product: .app,
            bundleId: "com.github.kstenerud.KSCrash.tvOS",
            infoPlist: InfoPlist.extendingDefault(with: [
                "CFBundleDisplayName": "KSCrash tvOS",
            ]),
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "SampleUI", type: .runtime),
            ]
        ),
    ]
)
