// swift-tools-version:5.9

import Foundation
@preconcurrency import PackageDescription

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

let kscrashNamespace: String? = {
    // Priority 1: Explicit env var override
    if let envValue = ProcessInfo.processInfo.environment["KSCRASH_NAMESPACE"] {
        return envValue.isEmpty ? nil : envValue
    }

    // Priority 2: Auto-detect from checkout path
    // SPM CLI: <ConsumerRoot>/.build/checkouts/KSCrash/Package.swift
    // Xcode:   <DerivedData>/<ProjectName-hash>/SourcePackages/checkouts/KSCrash/Package.swift
    let packageURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    // Walk up to find the innermost "checkouts" ancestor
    var ancestor = packageURL
    var checkoutsURL: URL?
    while ancestor.path != "/" {
        if ancestor.lastPathComponent == "checkouts" {
            checkoutsURL = ancestor
            break
        }
        ancestor = ancestor.deletingLastPathComponent()
    }
    guard let checkoutsURL else {
        return nil  // Not a dependency checkout — development mode
    }

    let rawName: String?
    let parentURL = checkoutsURL.deletingLastPathComponent()
    let parentName = parentURL.lastPathComponent

    if parentName == ".build" {
        // SPM CLI — consumer's Package.swift is in the parent of .build
        let consumerRoot = parentURL.deletingLastPathComponent()
        let manifestURL = consumerRoot.appendingPathComponent("Package.swift")
        guard let contents = try? String(contentsOf: manifestURL, encoding: .utf8),
            let packageInit = contents.range(of: "Package("),
            let nameStart = contents[packageInit.upperBound...].range(of: "name\\s*:", options: .regularExpression),
            let openQuote = contents[nameStart.upperBound...].firstIndex(of: "\"")
        else { return nil }
        let afterOpen = contents.index(after: openQuote)
        guard let closeQuote = contents[afterOpen...].firstIndex(of: "\"") else { return nil }
        rawName = String(contents[afterOpen..<closeQuote])
    } else if parentName == "SourcePackages" {
        // Xcode — extract project name from DerivedData subdirectory
        // e.g. "MyApp-bwrfhsjkqlnvep" → "MyApp"
        let derivedDataSubdir = parentURL.deletingLastPathComponent().lastPathComponent
        guard let lastHyphen = derivedDataSubdir.lastIndex(of: "-") else { return nil }
        rawName = String(derivedDataSubdir[..<lastHyphen])
    } else {
        return nil  // Not a recognized checkout layout
    }

    guard let rawName, !rawName.isEmpty else { return nil }

    // Sanitize to valid C identifier suffix
    let sanitized = String(rawName.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : "_" })
    return sanitized.isEmpty ? nil : "_" + sanitized
}()

let namespaceCSettings: [CSetting] = kscrashNamespace.map { [.define("KSCRASH_NAMESPACE", to: $0)] } ?? []
let namespaceCXXSettings: [CXXSetting] = kscrashNamespace.map { [.define("KSCRASH_NAMESPACE", to: $0)] } ?? []

let package = Package(
    name: "KSCrash",
    platforms: [
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v5),
        .macOS(.v10_14),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "Reporting",
            targets: [
                Targets.filters,
                Targets.sinks,
                Targets.installations,
            ]
        ),
        .library(
            name: "Filters",
            targets: [Targets.filters]
        ),
        .library(
            name: "Sinks",
            targets: [Targets.sinks]
        ),
        .library(
            name: "Installations",
            targets: [Targets.installations]
        ),
        .library(
            name: "Recording",
            targets: [Targets.recording]
        ),
        .library(
            name: "RecordingCore",
            targets: [Targets.recordingCore]
        ),
        .library(
            name: "DiscSpaceMonitor",
            targets: [Targets.discSpaceMonitor]
        ),
        .library(
            name: "BootTimeMonitor",
            targets: [Targets.bootTimeMonitor]
        ),
        .library(
            name: "DemangleFilter",
            targets: [Targets.demangleFilter]
        ),
        .library(
            name: "Profiler",
            targets: [Targets.profiler]
        ),
        .library(
            name: "Report",
            targets: [Targets.report]
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
            ] + namespaceCSettings,
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .headerSearchPath("../KSCrashRecordingCore/include"),  // For internal Unwind/ headers
                .unsafeFlags(warningFlags),
            ] + namespaceCXXSettings
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
            ] + namespaceCSettings
        ),

        .target(
            name: Targets.filters,
            dependencies: [
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.reportingCore),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),
        .testTarget(
            name: Targets.filters.tests,
            dependencies: [
                .target(name: Targets.filters),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.reportingCore),
            ],
            resources: [
                .process("Resources")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),

        .target(
            name: Targets.sinks,
            dependencies: [
                .target(name: Targets.recording),
                .target(name: Targets.filters),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),

        .target(
            name: Targets.installations,
            dependencies: [
                .target(name: Targets.filters),
                .target(name: Targets.sinks),
                .target(name: Targets.recording),
                .target(name: Targets.demangleFilter),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),
        .testTarget(
            name: Targets.installations.tests,
            dependencies: [
                .target(name: Targets.installations),
                .target(name: Targets.filters),
                .target(name: Targets.sinks),
                .target(name: Targets.recording),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
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
            ] + namespaceCSettings
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
            ] + namespaceCSettings
        ),
        .testTarget(
            name: Targets.recordingCoreSwift.tests,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),

        .target(
            name: Targets.reportingCore,
            dependencies: [
                .target(name: Targets.core)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings,
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: Targets.reportingCore.tests,
            dependencies: [
                .target(name: Targets.reportingCore),
                .target(name: Targets.core),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),

        .target(
            name: Targets.core,
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),
        .testTarget(
            name: Targets.core.tests,
            dependencies: [
                .target(name: Targets.core)
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),

        .target(
            name: Targets.discSpaceMonitor,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),
        .testTarget(
            name: Targets.discSpaceMonitor.tests,
            dependencies: [
                .target(name: Targets.discSpaceMonitor),
                .target(name: Targets.recordingCore),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),

        .target(
            name: Targets.bootTimeMonitor,
            dependencies: [
                .target(name: Targets.recordingCore)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),
        .testTarget(
            name: Targets.bootTimeMonitor.tests,
            dependencies: [
                .target(name: Targets.bootTimeMonitor),
                .target(name: Targets.recordingCore),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
        ),

        .target(
            name: Targets.demangleFilter,
            dependencies: [
                .target(name: Targets.recording)
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings,
            cxxSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCXXSettings
        ),
        .testTarget(
            name: Targets.demangleFilter.tests,
            dependencies: [
                .target(name: Targets.demangleFilter),
                .target(name: Targets.recording),
            ],
            cSettings: [
                .unsafeFlags(warningFlags)
            ] + namespaceCSettings
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
                .target(name: Targets.report)
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
            ] + namespaceCSettings
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
                .headerSearchPath("../../Sources/\(Targets.recording)")
            ] + namespaceCSettings
        ),

        .testTarget(
            name: Targets.coldBenchmarks,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
            ]
        ),

        .target(
            name: Targets.profiler,
            dependencies: [
                .target(name: Targets.recordingCore),
                .target(name: Targets.recording),
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

        .testTarget(
            name: Targets.namespaceDetection.tests
        ),
    ],
    cxxLanguageStandard: .gnucxx11
)

enum Targets {
    static let recording = "KSCrashRecording"
    static let filters = "KSCrashFilters"
    static let sinks = "KSCrashSinks"
    static let installations = "KSCrashInstallations"
    static let recordingCore = "KSCrashRecordingCore"
    static let recordingCoreSwift = "KSCrashRecordingCoreSwift"
    static let reportingCore = "KSCrashReportingCore"
    static let core = "KSCrashCore"
    static let discSpaceMonitor = "KSCrashDiscSpaceMonitor"
    static let bootTimeMonitor = "KSCrashBootTimeMonitor"
    static let demangleFilter = "KSCrashDemangleFilter"
    static let report = "Report"
    static let testTools = "KSCrashTestTools"
    static let benchmarks = "KSCrashBenchmarks"
    static let objcBenchmarks = "KSCrashBenchmarksObjC"
    static let coldBenchmarks = "KSCrashBenchmarksCold"
    static let profiler = "KSCrashProfiler"
    static let namespaceDetection = "KSCrashNamespaceDetection"
}

extension String {
    var tests: String {
        return "\(self)Tests"
    }
}
