// swift-tools-version:5.9

@preconcurrency import PackageDescription

let metricKitSwiftSettings: [SwiftSetting] = [
    .define("KSCRASH_HAS_METRICKIT", .when(platforms: [.iOS, .macOS, .visionOS]))
]

let warningFlags = [
    // The main ones
    "-Werror",
    "-Wmost",
    "-Wall",
    "-Wextra",

    // Specifics that aren't covered by above
    "-Wanon-enum-enum-conversion",
    "-Warc-repeated-use-of-weak",
    "-Wbitfield-enum-conversion",
    "-Wbitwise-instead-of-logical",
    "-Wbitwise-op-parentheses",
    "-Wblock-capture-autoreleasing",
    "-Wbool-conversion",
    "-Wbool-operation",
    "-Wcalled-once-parameter",
    "-Wcast-align",
    "-Wclass-varargs",
    "-Wcomma",
    "-Wcomment",
    "-Wcompletion-handler",
    "-Wconditional-uninitialized",
    "-Wconstant-conversion",
    "-Wconsumed",
    "-Wconversion",
    "-Wcustom-atomic-properties",
    "-Wdelete-non-virtual-dtor",
    "-Wdeprecated",
    "-Wdeprecated-declarations",
    "-Wdocumentation",
    "-Wdocumentation-pedantic",
    "-Wdtor-name",
    "-Wduplicate-decl-specifier",
    "-Wduplicate-enum",
    "-Wduplicate-method-arg",
    "-Wduplicate-method-match",
    "-Wembedded-directive",
    "-Wempty-body",
    "-Wempty-init-stmt",
    "-Wenum-compare-conditional",
    "-Wenum-conversion",
    "-Wexit-time-destructors",
    "-Wexpansion-to-defined",
    "-Wflexible-array-extensions",
    "-Wfloat-conversion",
    "-Wfloat-equal",
    "-Wfor-loop-analysis",
    "-Wformat-non-iso",
    "-Wformat-pedantic",
    "-Wformat-type-confusion",
    "-Wfour-char-constants",
    "-Wframe-address",
    "-Widiomatic-parentheses",
    "-Wignored-qualifiers",
    "-Wimplicit",
    "-Wimplicit-atomic-properties",
    "-Wimplicit-fallthrough",
    "-Wimplicit-float-conversion",
    "-Wimplicit-function-declaration",
    "-Wimplicit-int",
    "-Wimplicit-int-conversion",
    "-Wimplicit-int-float-conversion",
    "-Wimplicit-retain-self",
    "-Winconsistent-missing-destructor-override",
    "-Winfinite-recursion",
    "-Wint-conversion",
    "-Wint-in-bool-context",
    "-Wkeyword-macro",
    "-Wlogical-op-parentheses",
    "-Wloop-analysis",
    "-Wmain",
    "-Wmethod-signatures",
    "-Wmisleading-indentation",
    "-Wmismatched-tags",
    "-Wmissing-braces",
    "-Wmissing-field-initializers",
    "-Wmissing-method-return-type",
    "-Wmissing-noreturn",
    "-Wmissing-variable-declarations",
    "-Wmove",
    "-Wnested-anon-types",
    "-Wno-four-char-constants",
    "-Wno-missing-field-initializers",
    "-Wno-missing-prototypes",
    "-Wno-semicolon-before-method-body",
    "-Wno-trigraphs",
    "-Wno-unknown-pragmas",
    "-Wnon-literal-null-conversion",
    "-Wnon-modular-include-in-module",
    "-Wnon-pod-varargs",
    "-Wnon-virtual-dtor",
    "-Wnull-pointer-arithmetic",
    "-Wnull-pointer-subtraction",
    "-Wobjc-literal-conversion",
    "-Wobjc-property-assign-on-object-type",
    "-Wobjc-redundant-api-use",
    "-Wobjc-signed-char-bool-implicit-int-conversion",
    "-Wover-aligned",
    "-Woverloaded-virtual",
    "-Woverriding-method-mismatch",
    "-Wparentheses",
    "-Wpessimizing-move",
    "-Wpointer-sign",
    "-Wquoted-include-in-framework-header",
    "-Wrange-loop-analysis",
    "-Wredundant-move",
    "-Wredundant-parens",
    "-Wreorder-ctor",
    "-Wreserved-macro-identifier",
    "-Wselector-type-mismatch",
    "-Wself-assign-overloaded",
    "-Wself-move",
    "-Wsemicolon-before-method-body",
    "-Wsequence-point",
    "-Wshadow",
    "-Wshadow-uncaptured-local",
    "-Wshift-sign-overflow",
    "-Wshorten-64-to-32",
    "-Wsign-compare",
    "-Wsign-conversion",
    "-Wsometimes-uninitialized",
    "-Wspir-compat",
    "-Wstatic-in-inline",
    "-Wstrict-potentially-direct-selector",
    "-Wstrict-prototypes",
    "-Wstring-conversion",
    "-Wsuggest-destructor-override",
    "-Wsuggest-override",
    "-Wsuper-class-method-mismatch",
    "-Wswitch",
    "-Wswitch-default",
    "-Wtautological-compare",
    "-Wtautological-unsigned-char-zero-compare",
    "-Wtautological-unsigned-enum-zero-compare",
    "-Wtautological-value-range-compare",
    "-Wtentative-definition-incomplete-type",
    "-Wthread-safety",
    "-Wunaligned-access",
    "-Wundeclared-selector",
    "-Wundef-prefix",
    "-Wundefined-func-template",
    "-Wundefined-internal-type",
    "-Wundefined-reinterpret-cast",
    "-Wunguarded-availability",
    "-Wuninitialized",
    "-Wuninitialized-const-reference",
    "-Wunneeded-internal-declaration",
    "-Wunneeded-member-function",
    "-Wunreachable-code",
    "-Wunreachable-code-loop-increment",
    "-Wunreachable-code-return",
    "-Wunused",
    "-Wunused-but-set-parameter",
    "-Wunused-const-variable",
    "-Wunused-exception-parameter",
    "-Wunused-function",
    "-Wunused-label",
    "-Wunused-parameter",
    "-Wunused-value",
    "-Wunused-variable",
    "-Wused-but-marked-unused",
    "-Wvector-conversion",
    "-Wweak-vtables",

    // To be added later (big job to fix this)
    // "-Wdirect-ivar-access",
    // "-Wobjc-interface-ivars",

    // Flags that we can't use for various reasons:
    // "-Wassign-enum",
    // "-Watomic-implicit-seq-cst",
    // "-Wcast-qual",
    // "-Wcast-function-type",

    // Must disable these because the auto-generated resource_bundle_accessor.m is naughty
    "-Wno-strict-prototypes",
    //"-Wnullable-to-nonnull-conversion",
]

// Test targets that pull in the C++ standard library (via .mm/.cpp using std:: and
// throw) must link the C++ runtime explicitly. Xcode 27's SwiftPM stopped auto-linking
// it into test bundles, so std:: and __cxa_* symbols would otherwise be undefined at
// link time. Harmless on toolchains that already link it (duplicate libraries are
// allowed via -no_warn_duplicate_libraries).
let cxxTestLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("c++"),
    .linkedLibrary("c++abi"),
]

let package = Package(
    name: "KSCrash",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .macOS(.v12),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "Recording",
            targets: [Targets.recording]
        ),
        .library(
            name: "RecordingCore",
            targets: [Targets.recordingCore]
        ),
        .library(
            name: "DiskMonitor",
            targets: [Targets.diskMonitor]
        ),
        .library(
            name: "BootMonitor",
            targets: [Targets.bootMonitor]
        ),
        .library(
            name: "Profiler",
            targets: [Targets.profiler]
        ),
        .library(
            name: "MonitorPlugins",
            targets: [Targets.monitorPlugins]
        ),
        .library(
            name: "Monitors",
            targets: [Targets.monitors]
        ),
        .library(
            name: "Report",
            targets: [Targets.report]
        ),
        .library(
            name: "KSCrash",
            targets: [Targets.kscrash]
        ),
    ],
    targets: [
        .target(
            name: Targets.recording,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.core),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .headerSearchPath("../KSCrashRecordingCore/include"),  // For internal Unwind/ headers
                .unsafeFlags(warningFlags),
            ],
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .headerSearchPath("../KSCrashRecordingCore/include"),  // For internal Unwind/ headers
                .unsafeFlags(warningFlags),
            ]
        ),
        .testTarget(
            name: Targets.recording.tests,
            dependencies: [
                .target(name: Targets.testTools),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
            ],
            resources: [
                .process("Resources")
            ],
            cSettings: [
                .headerSearchPath("../../Sources/\(Targets.recording)"),
                .headerSearchPath("../../Sources/\(Targets.recording)/Monitors"),
                .headerSearchPath("../../Sources/\(Targets.recordingCore)/include"),  // For internal Unwind/ headers
                .unsafeFlags(warningFlags),
            ],
            linkerSettings: cxxTestLinkerSettings
        ),

        .target(
            name: Targets.recordingCore,
            dependencies: [
                .target(name: Targets.core)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.recordingCore.tests,
            dependencies: [
                .target(name: Targets.testTools),
                .target(name: Targets.recordingCore),
                .target(name: Targets.core),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ],
            linkerSettings: cxxTestLinkerSettings
        ),
        .testTarget(
            name: Targets.recordingCoreSwift.tests,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.core,
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),
        .testTarget(
            name: Targets.core.tests,
            dependencies: [
                .target(name: Targets.core)
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .target(
            name: Targets.diskMonitor,
            dependencies: [
                .target(name: Targets.monitorPlugins),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.swiftCore),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: Targets.bootMonitor,
            dependencies: [
                .target(name: Targets.monitorPlugins),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.swiftCore),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),

        .target(
            name: Targets.report,
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: Targets.report.tests,
            dependencies: [
                .target(name: Targets.report),
                .target(name: Targets.recording),
            ],
            resources: [
                .process("Resources")
            ]
        ),

        .target(
            name: Targets.testTools,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ]
        ),

        .testTarget(
            name: Targets.benchmarks,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
                .target(name: Targets.profiler),
            ]
        ),

        .testTarget(
            name: Targets.objcBenchmarks,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
            ],
            cSettings: [
                .headerSearchPath("../../Sources/\(Targets.recording)"),
                .headerSearchPath("../../Sources/\(Targets.recording)/Monitors"),
            ],
            linkerSettings: cxxTestLinkerSettings
        ),

        .testTarget(
            name: Targets.coldBenchmarks,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
            ]
        ),

        .target(
            name: Targets.swiftCore,
            dependencies: [
                .target(name: Targets.core)
            ]
        ),
        .testTarget(
            name: Targets.swiftCore.tests,
            dependencies: [
                .target(name: Targets.swiftCore)
            ]
        ),

        .target(
            name: Targets.profiler,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
                .target(name: Targets.swiftCore),
                .target(name: Targets.monitorPlugins),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: Targets.profiler.tests,
            dependencies: [
                .target(name: Targets.profiler)
            ]
        ),

        .target(
            name: Targets.monitorPlugins,
            dependencies: [
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.report),
                .target(name: Targets.swiftCore),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: Targets.monitorPlugins.tests,
            dependencies: [
                .target(name: Targets.monitorPlugins)
            ]
        ),

        .target(
            name: Targets.monitors,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
                .target(name: Targets.report),
                .target(name: Targets.swiftCore),
                .target(name: Targets.monitorPlugins),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            swiftSettings: metricKitSwiftSettings
        ),
        .testTarget(
            name: Targets.monitors.tests,
            dependencies: [
                .target(name: Targets.monitors),
                .target(name: Targets.report),
            ],
            swiftSettings: metricKitSwiftSettings
        ),
        .target(
            name: Targets.kscrash,
            dependencies: [
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.report),
                .target(name: Targets.swiftCore),
                .target(name: Targets.monitorPlugins),
            ]
        ),
        .testTarget(
            name: Targets.kscrash.tests,
            dependencies: [
                .target(name: Targets.kscrash),
                .target(name: Targets.recordingCore),
                .target(name: Targets.swiftCore),
                .target(name: Targets.monitorPlugins),
                .target(name: Targets.diskMonitor),
                .target(name: Targets.bootMonitor),
            ]
        ),
    ],
    cxxLanguageStandard: .gnucxx11
)

enum Targets {
    static let recording = "KSCrashRecording"
    static let recordingCore = "KSCrashRecordingCore"
    static let recordingCoreSwift = "KSCrashRecordingCoreSwift"
    static let core = "KSCrashCore"
    static let diskMonitor = "KSCrashDiskMonitor"
    static let bootMonitor = "KSCrashBootMonitor"
    static let report = "KSCrashReportModel"
    static let kscrash = "KSCrash"
    static let testTools = "KSCrashTestTools"
    static let benchmarks = "KSCrashBenchmarks"
    static let objcBenchmarks = "KSCrashBenchmarksObjC"
    static let coldBenchmarks = "KSCrashBenchmarksCold"
    static let swiftCore = "KSCrashSwiftCore"
    static let profiler = "KSCrashProfiler"
    static let monitors = "KSCrashMonitors"
    static let monitorPlugins = "KSCrashMonitorPlugins"
}

extension String {
    var tests: String {
        return "\(self)Tests"
    }
}
