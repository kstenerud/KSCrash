import ProjectDescription

let project = Project(
    name: "KSCrashBenchmarks",
    packages: [
        .local(path: "..")
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "5.9"
    ]),
    targets: [
        .target(
            name: "BenchmarkApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.github.kstenerud.KSCrash.BenchmarkApp",
            deploymentTargets: .iOS("18.0"),
            infoPlist: InfoPlist.extendingDefault(with: [
                "UILaunchScreen": [:]
            ]),
            sources: ["Sources/**"],
            dependencies: []
        ),
        .target(
            name: "BenchmarkTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.github.kstenerud.KSCrash.BenchmarkTests",
            deploymentTargets: .iOS("18.0"),
            sources: [
                "../Tests/KSCrashBenchmarks/**",
                "../Tests/KSCrashBenchmarksObjC/**",
                "../Tests/KSCrashBenchmarksCold/**",
            ],
            dependencies: [
                .target(name: "BenchmarkApp"),
                .package(product: "Recording", type: .runtime),
                .package(product: "RecordingCore", type: .runtime),
                .package(product: "Profiler", type: .runtime),
            ],
            settings: .settings(base: [
                "HEADER_SEARCH_PATHS": "$(SRCROOT)/../Sources/KSCrashRecording"
            ])
        ),
        .target(
            name: "BenchmarkUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "com.github.kstenerud.KSCrash.BenchmarkUITests",
            deploymentTargets: .iOS("18.0"),
            sources: [
                "../Tests/KSCrashBenchmarks/**",
                "../Tests/KSCrashBenchmarksObjC/**",
                "../Tests/KSCrashBenchmarksCold/**",
            ],
            dependencies: [
                .target(name: "BenchmarkApp"),
                .package(product: "Recording", type: .runtime),
                .package(product: "RecordingCore", type: .runtime),
                .package(product: "Profiler", type: .runtime),
            ],
            settings: .settings(base: [
                "HEADER_SEARCH_PATHS": "$(SRCROOT)/../Sources/KSCrashRecording",
                // Export Swift test class symbols for BrowserStack test discovery
                "GCC_SYMBOLS_PRIVATE_EXTERN": "NO",
                "STRIP_INSTALLED_PRODUCT": "NO",
            ])
        ),
    ],
    schemes: [
        .scheme(
            name: "Benchmarks",
            shared: true,
            buildAction: .buildAction(targets: ["BenchmarkApp", "BenchmarkTests"]),
            testAction: .targets(
                ["BenchmarkTests"],
                configuration: .release,
                attachDebugger: false
            ),
            runAction: .runAction(executable: "BenchmarkApp")
        ),
        .scheme(
            name: "BenchmarksBrowserStack",
            shared: true,
            buildAction: .buildAction(targets: ["BenchmarkApp", "BenchmarkUITests"]),
            testAction: .targets(
                ["BenchmarkUITests"],
                configuration: .release,
                attachDebugger: false
            ),
            runAction: .runAction(executable: "BenchmarkApp")
        ),
    ]
)
