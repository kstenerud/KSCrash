import ProjectDescription

let project = Project(
    name: "KSCrash",
    organizationName: "com.embrace.kscrash",
    settings: .settings(base: [
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++11"
    ]),
    targets: [
        .target(
            name: "KSCrashRecording",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.embrace.KSCrashRecording",
            sources: ["Sources/KSCrashRecording/**"],
            resources: ["Sources/KSCrashRecording/Resources/PrivacyInfo.xcprivacy"], 
            headers: .headers(public: "Sources/KSCrashRecording/include/**/*.h"),
            dependencies: [
                .target(name: "KSCrashRecordingCore")
            ],
            settings: .settings(base: [
                "SKIP_INSTALL": "NO",
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashRecording/Monitors", "$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        ),

        .target(
            name: "KSCrashRecordingTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.embrace.KSCrashRecordingTests",
            sources: ["Tests/KSCrashRecordingTests/**"],
            resources: ["Tests/KSCrashRecordingTests/Resources/**"],
            dependencies: [
                .target(name: "KSCrashTestTools"),
                .target(name: "KSCrashRecording"),
                .target(name: "KSCrashRecordingCore")
            ],
            settings: .settings(base: [
                "HEADER_SEARCH_PATHS": [
                    "$(SRCROOT)/Sources/KSCrashRecording",
                    "$(SRCROOT)/Sources/KSCrashRecording/Monitors",
                    "$(SRCROOT)/Sources/KSCrashCore/include"
                ]
            ])
        ),
        .target(
            name: "KSCrashFilters",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.embrace.KSCrashFilters",
            sources: ["Sources/KSCrashFilters/**"],
            resources: ["Sources/KSCrashFilters/Resources/PrivacyInfo.xcprivacy"],
            headers: .headers(public: "Sources/KSCrashFilters/include/**/*.h"),
            dependencies: [
                .target(name: "KSCrashRecording"),
                .target(name: "KSCrashRecordingCore"),
                .target(name: "KSCrashReportingCore")
            ],
            settings: .settings(base: [
                "SKIP_INSTALL": "NO",
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        ),
        .target(
            name: "KSCrashFiltersTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.embrace.KSCrashFiltersTests",
            sources: ["Tests/KSCrashFiltersTests/**"],
            dependencies: [
                .target(name: "KSCrashFilters"),
                .target(name: "KSCrashRecording"),
                .target(name: "KSCrashRecordingCore"),
                .target(name: "KSCrashReportingCore")
            ],
            settings: .settings(base: [
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        ),
        .target(
            name: "KSCrashSinks",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.embrace.KSCrashSinks",
            sources: ["Sources/KSCrashSinks/**"],
            resources: ["Sources/KSCrashSinks/Resources/PrivacyInfo.xcprivacy"],
            headers: .headers(public: "Sources/KSCrashSinks/include/**/*.h"),
            dependencies: [
                .target(name: "KSCrashRecording"),
                .target(name: "KSCrashFilters")
            ],
            settings: .settings(base: [
                "SKIP_INSTALL": "NO",
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        ),
        .target(
            name: "KSCrashInstallations",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.embrace.KSCrashInstallations",
            sources: ["Sources/KSCrashInstallations/**"],
            resources: ["Sources/KSCrashInstallations/Resources/PrivacyInfo.xcprivacy"],
            headers: .headers(public: "Sources/KSCrashInstallations/include/**/*.h"),
            dependencies: [
                .target(name: "KSCrashFilters"),
                .target(name: "KSCrashSinks"),
                .target(name: "KSCrashRecording")
            ],
            settings: .settings(base: [
                "SKIP_INSTALL": "NO",
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        ),
        .target(
            name: "KSCrashInstallationsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.embrace.KSCrashInstallationsTests",
            sources: ["Tests/KSCrashInstallationsTests/**"],
            dependencies: [
                .target(name: "KSCrashInstallations"),
                .target(name: "KSCrashFilters"),
                .target(name: "KSCrashSinks"),
                .target(name: "KSCrashRecording")
            ],
            settings: .settings(base: [
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        ),
        .target(
            name: "KSCrashRecordingCore",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.embrace.KSCrashRecordingCore",
            sources: ["Sources/KSCrashRecordingCore/**"],
            resources: ["Sources/KSCrashRecordingCore/Resources/PrivacyInfo.xcprivacy"],
            headers: .headers(public: "Sources/KSCrashRecordingCore/include/**/*.h"),
            dependencies: [
                .target(name: "KSCrashCore")
            ],
            settings: .settings(base: [
                "SKIP_INSTALL": "NO",
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
                "HEADER_SEARCH_PATHS": [
                    "$(SRCROOT)/Sources/KSCrashRecordingCore/swift",
                    "$(SRCROOT)/Sources/KSCrashRecordingCore/swift/Basic",
                    "$(SRCROOT)/Sources/KSCrashRecordingCore/llvm",
                    "$(SRCROOT)/Sources/KSCrashRecordingCore/llvm/ADT",
                    "$(SRCROOT)/Sources/KSCrashRecordingCore/llvm/Config",
                    "$(SRCROOT)/Sources/KSCrashRecordingCore/llvm/Support",
                    "$(SRCROOT)/Sources/KSCrashCore/include"
                ]
            ])
        ),
        .target(
            name: "KSCrashRecordingCoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.embrace.KSCrashRecordingCoreTests",
            sources: ["Tests/KSCrashRecordingCoreTests/**"],
            dependencies: [
                .target(name: "KSCrashTestTools"),
                .target(name: "KSCrashRecordingCore"),
                .target(name: "KSCrashCore")
            ],
            settings: .settings(base: [
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        ),
        .target(
            name: "KSCrashReportingCore",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.embrace.KSCrashReportingCore",
            sources: ["Sources/KSCrashReportingCore/**"],
            resources: ["Sources/KSCrashReportingCore/Resources/PrivacyInfo.xcprivacy"],
            headers: .headers(public: "Sources/KSCrashReportingCore/include/**/*.h"),
            dependencies: [
                .target(name: "KSCrashCore")
            ],
            settings: .settings(base: [
                "SKIP_INSTALL": "NO",
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        ),
        .target(
            name: "KSCrashReportingCoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.embrace.KSCrashReportingCoreTests",
            sources: ["Tests/KSCrashReportingCoreTests/**"],
            dependencies: [
                .target(name: "KSCrashReportingCore"),
                .target(name: "KSCrashCore")
            ],
            settings: .settings(base: [
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        ),
        .target(
            name: "KSCrashCore",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.embrace.KSCrashCore",
            sources: ["Sources/KSCrashCore/**"],
            resources: ["Sources/KSCrashCore/Resources/PrivacyInfo.xcprivacy"],
            headers: .headers(public: "Sources/KSCrashCore/include/**/*.h"),
            settings: .settings(base: [
                "SKIP_INSTALL": "NO",
                "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES"
            ])
        ),
        .target(
            name: "KSCrashCoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.embrace.KSCrashCoreTests",
            sources: ["Tests/KSCrashCoreTests/**"],
            dependencies: [
                .target(name: "KSCrashCore")
            ]
        ),
        .target(
            name: "KSCrashTestTools",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.embrace.KSCrashTestTools",
            sources: ["Sources/KSCrashTestTools/**"],
            dependencies: [
                .target(name: "KSCrashRecordingCore")
            ],
            settings: .settings(base: [
                "SKIP_INSTALL": "NO",
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/KSCrashCore/include"]
            ])
        )
    ]
)


