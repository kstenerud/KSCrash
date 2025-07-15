// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
@preconcurrency import PackageDescription

// MARK: - Package Definition

let package = Package(
    name: "KSCrash",
    platforms: [
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v5),
        .macOS(.v10_14),
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
        .library(name: "Filters", targets: [Targets.filters]),
        .library(name: "Sinks", targets: [Targets.sinks]),
        .library(name: "Installations", targets: [Targets.installations]),
        .library(name: "Recording", targets: [Targets.recording]),
        .library(name: "DiscSpaceMonitor", targets: [Targets.discSpaceMonitor]),
        .library(name: "BootTimeMonitor", targets: [Targets.bootTimeMonitor]),
        .library(name: "DemangleFilter", targets: [Targets.demangleFilter]),
    ],
    targets: [
        // MARK: Recording Targets
        .target(
            name: Targets.recording,
            dependencies: [.target(name: Targets.recordingCore)],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .unsafeFlags(developmentUnsafeFlags),
            ],
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Monitors"),
                .unsafeFlags(developmentUnsafeFlags),
            ]
        ),
        .testTarget(
            name: Targets.recording.tests,
            dependencies: [
                .target(name: Targets.testTools),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
            ],
            resources: [.process("Resources")],
            cSettings: [
                .headerSearchPath("../../Sources/\(Targets.recording)"),
                .headerSearchPath("../../Sources/\(Targets.recording)/Monitors"),
                .unsafeFlags(developmentUnsafeFlags),
            ]
        ),

        // MARK: Core Targets
        .target(
            name: Targets.recordingCore,
            dependencies: [.target(name: Targets.core)],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),
        .testTarget(
            name: Targets.recordingCore.tests,
            dependencies: [
                .target(name: Targets.testTools),
                .target(name: Targets.recordingCore),
                .target(name: Targets.core),
            ],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),
        .testTarget(
            name: Targets.recordingCoreSwift.tests,
            dependencies: [.target(name: Targets.recordingCore)],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),

        .target(
            name: Targets.reportingCore,
            dependencies: [.target(name: Targets.core)],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)],
            linkerSettings: [.linkedLibrary("z")]
        ),
        .testTarget(
            name: Targets.reportingCore.tests,
            dependencies: [
                .target(name: Targets.reportingCore),
                .target(name: Targets.core),
            ],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),

        .target(
            name: Targets.core,
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),
        .testTarget(
            name: Targets.core.tests,
            dependencies: [.target(name: Targets.core)],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),

        // MARK: Filter Targets
        .target(
            name: Targets.filters,
            dependencies: [
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.reportingCore),
            ],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),
        .testTarget(
            name: Targets.filters.tests,
            dependencies: [
                .target(name: Targets.filters),
                .target(name: Targets.recording),
                .target(name: Targets.recordingCore),
                .target(name: Targets.reportingCore),
            ],
            resources: [.process("Resources")],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),

        .target(
            name: Targets.demangleFilter,
            dependencies: [.target(name: Targets.recording)],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [
                .headerSearchPath("swift"),
                .headerSearchPath("swift/Basic"),
                .headerSearchPath("llvm"),
                .headerSearchPath("llvm/ADT"),
                .headerSearchPath("llvm/Config"),
                .headerSearchPath("llvm/Support"),
                .unsafeFlags(developmentUnsafeFlags),
            ],
            cxxSettings: [
                .headerSearchPath("swift"),
                .headerSearchPath("swift/Basic"),
                .headerSearchPath("llvm"),
                .headerSearchPath("llvm/ADT"),
                .headerSearchPath("llvm/Config"),
                .headerSearchPath("llvm/Support"),
                .unsafeFlags(developmentUnsafeFlags),
            ]
        ),
        .testTarget(
            name: Targets.demangleFilter.tests,
            dependencies: [
                .target(name: Targets.demangleFilter),
                .target(name: Targets.recording),
            ],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),

        // MARK: Sink Targets
        .target(
            name: Targets.sinks,
            dependencies: [
                .target(name: Targets.recording),
                .target(name: Targets.filters),
            ],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),

        // MARK: Installation Targets
        .target(
            name: Targets.installations,
            dependencies: [
                .target(name: Targets.filters),
                .target(name: Targets.sinks),
                .target(name: Targets.recording),
                .target(name: Targets.demangleFilter),
            ],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),
        .testTarget(
            name: Targets.installations.tests,
            dependencies: [
                .target(name: Targets.installations),
                .target(name: Targets.filters),
                .target(name: Targets.sinks),
                .target(name: Targets.recording),
            ],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),

        // MARK: Monitor Targets
        .target(
            name: Targets.discSpaceMonitor,
            dependencies: [.target(name: Targets.recordingCore)],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),
        .testTarget(
            name: Targets.discSpaceMonitor.tests,
            dependencies: [
                .target(name: Targets.discSpaceMonitor),
                .target(name: Targets.recordingCore),
            ],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),

        .target(
            name: Targets.bootTimeMonitor,
            dependencies: [.target(name: Targets.recordingCore)],
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),
        .testTarget(
            name: Targets.bootTimeMonitor.tests,
            dependencies: [
                .target(name: Targets.bootTimeMonitor),
                .target(name: Targets.recordingCore),
            ],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),

        // MARK: Utility Targets
        .target(
            name: Targets.testTools,
            dependencies: [.target(name: Targets.recordingCore)],
            cSettings: [.unsafeFlags(developmentUnsafeFlags)]
        ),
    ],
    cxxLanguageStandard: .gnucxx11
)

// MARK: - Target Names

/// Centralized target name management using enum for type safety
private enum Targets {
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
    static let testTools = "KSCrashTestTools"
}

// MARK: - Development Configuration

private var isDevelopmentBuild: Bool {
    let developmentFlagPath = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .appendingPathComponent(".kscrash_development")
        .path

    return FileManager.default.fileExists(atPath: developmentFlagPath)
}

private var developmentUnsafeFlags: [String] {
    guard isDevelopmentBuild else { return [] }

    return [
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
}

// MARK: - String Extensions

extension String {
    /// Generates consistent test target names
    fileprivate var tests: String {
        return self + "Tests"
    }
}
