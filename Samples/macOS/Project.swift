import ProjectDescription

let project = Project(
    name: "macOS",
    packages: [
        .local(path: "../Common"),
    ],
    targets: [
        .target(
            name: "macOS",
            destinations: .macOS,
            product: .app,
            bundleId: "com.github.kstenerud.KSCrash.macOS",
            infoPlist: InfoPlist.extendingDefault(with: [
                "CFBundleDisplayName": "KSCrash macOS",
            ]),
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "SampleUI", type: .runtime),
            ]
        ),
    ]
)
