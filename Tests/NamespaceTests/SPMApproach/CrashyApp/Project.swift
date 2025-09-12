import ProjectDescription

let project = Project(
    name: "CrashyApp",
    targets: [
        .target(
            name: "CrashyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "org.kscrash.CrashyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ]
                ]
            ),
            buildableFolders: [
                "CrashyApp/Sources",
                "CrashyApp/Resources",
            ],
            dependencies: [
                .external(name: "CrashLibA"),
                .external(name: "CrashLibB"),
            ],
            settings: .settings(base: ["SWIFT_OBJC_INTEROP_MODE": "objcxx"])
        ),
        .target(
            name: "CrashyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.CrashyAppTests",
            infoPlist: .default,
            buildableFolders: [
                "CrashyApp/Tests"
            ],
            dependencies: [.target(name: "CrashyApp")],
            settings: .settings(base: ["SWIFT_OBJC_INTEROP_MODE": "objcxx"])
        ),
    ]
)
