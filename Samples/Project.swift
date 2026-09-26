import Foundation
import ProjectDescription

/// The development team for the corpse pair, read from `Corpse/signing.env`,
/// which is not committed.
///
/// Read from the file rather than the environment because a Tuist manifest runs
/// in its own process and does not inherit exported variables. With no file
/// there are no settings, so CI keeps building these unsigned.
let corpseSigningValues: [String: String] = {
    // Relative to the working directory, not #filePath: Tuist compiles the
    // manifest from a copy elsewhere, so #filePath does not point at the
    // checkout. Generate runs from Samples/.
    let candidates = [
        FileManager.default.currentDirectoryPath + "/Corpse/signing.env",
        FileManager.default.currentDirectoryPath + "/Samples/Corpse/signing.env",
    ]
    guard let text = candidates.lazy.compactMap({ try? String(contentsOfFile: $0, encoding: .utf8) }).first
    else { return [:] }
    var values: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
        let key = String(trimmed[trimmed.startIndex..<eq])
        var value = String(trimmed[trimmed.index(after: eq)...])
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        values[key] = value
    }
    return values
}()

/// Automatic signing, with no profile named.
///
/// The profiles Xcode creates for these targets are Xcode-managed, and a
/// managed profile cannot be named by a manually-managed configuration, so
/// letting Xcode choose is the only way to use them. `xcodebuild
/// -allowProvisioningUpdates`, which the run script passes, refreshes them
/// without Xcode itself being open.
var corpseSigning: SettingsDictionary {
    guard let team = corpseSigningValues["TUIST_CORPSE_TEAM"], !team.isEmpty else { return [:] }
    return [
        "DEVELOPMENT_TEAM": .string(team),
        "CODE_SIGN_STYLE": .string("Automatic"),
    ]
}

/// The one thing the corpse host and its extension share. Both rebuild their
/// `CorpseReportingConfiguration` from it independently, on purpose: that is how
/// a real two-target integration is written, and a mismatch between the sides is
/// one of the failures these tests exist to catch.
let corpseAppGroup = "group.com.github.kstenerud.KSCrash.Corpse"
let corpseHostBundleID = "com.github.kstenerud.KSCrash.CorpseHost"

let project = Project(
    name: "KSCrashSamples",
    packages: [
        .local(path: "Common")
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "5.0"
    ]),
    targets: [
        .target(
            name: "Sample",
            destinations: .allForSample,
            product: .app,
            bundleId: "com.github.kstenerud.KSCrash.Sample",
            deploymentTargets: .allForSample,
            infoPlist: InfoPlist.extendingDefault(with: [
                "UILaunchScreen": [
                    "UIImageName": "LaunchImage",
                    "UIBackgroundColor": "LaunchScreenColor",
                ],
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "CFBundleDisplayName": "KSCrashSample",
                "WKApplication": true,
                "WKWatchOnly": true,
            ]),
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "SampleUI", type: .runtime),
                .package(product: "KSCrash", type: .runtime),
            ]
        ),
        .target(
            name: "SampleTests",
            destinations: .allForSample.subtracting(.visionOS),
            product: .uiTests,
            bundleId: "com.github.kstenerud.KSCrash.Sample.Tests",
            deploymentTargets: .allForSample.excludingVisionOS,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "Sample"),
                .package(product: "SampleUI", type: .runtime),
                .package(product: "CrashTriggers", type: .runtime),
                .package(product: "CrashCallback", type: .runtime),
                .package(product: "IntegrationTestsHelper", type: .runtime),
                .package(product: "Report", type: .runtime),
            ],
            additionalFiles: ["Tests/Integration.xctestplan"]
        ),

        // The iOS 27 crash extension, and a host for it.
        //
        // These are separate from Sample rather than folded into it because the
        // pair needs an App Groups entitlement, and Sample builds for five
        // platforms, four of which can never run an iOS crash extension. Putting
        // the entitlement on Sample would make every one of those builds sign
        // for a capability it does not use.
        //
        // The extension links CrashReportExtension, which ships in the device
        // SDK and is absent from the simulator SDK, so it is pinned to iphoneos
        // and the host depends on it only on iOS. Nothing here can run in a
        // simulator: an extension is invoked by the system against a real
        // corpse, which only happens on a device.
        .target(
            name: "CorpseHost",
            destinations: .iOS,
            product: .app,
            bundleId: corpseHostBundleID,
            deploymentTargets: .iOS("27.0"),
            infoPlist: InfoPlist.extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "KSCrashCorpse",
            ]),
            sources: ["Corpse/App/**"],
            entitlements: .dictionary([
                "com.apple.security.application-groups": .array([.string(corpseAppGroup)])
            ]),
            dependencies: [
                .target(name: "CorpseReporter", condition: .when([.ios])),
                .package(product: "KSCrash", type: .runtime),
                // The app side needs this too, not just the extension: it
                // registers CrashReportExtensionMonitor as a plugin so the
                // reports the extension wrote can be drained at send.
                .package(product: "CrashReportExtension", type: .runtime),
                .package(product: "Report", type: .runtime),
                .package(product: "CrashTriggers", type: .runtime),
            ],
            settings: .settings(base: corpseSigning)
        ),

        // The bundle identifier must be a child of the host's; the system will
        // not match the extension to the app otherwise.
        .target(
            name: "CorpseReporter",
            destinations: .iOS,
            product: .extensionKitExtension,
            bundleId: "\(corpseHostBundleID).Reporter",
            deploymentTargets: .iOS("27.0"),
            // extendingDefault, not dictionary: a bare dictionary replaces the
            // whole plist, which drops CFBundleIdentifier, and an embedded
            // binary with no identifier cannot be prefixed by its host's, so
            // the build fails validation before anything ever runs.
            infoPlist: InfoPlist.extendingDefault(with: [
                "CFBundleDisplayName": "KSCrashCorpseReporter",
                "EXAppExtensionAttributes": [
                    "EXExtensionPointIdentifier": "com.apple.crash-reporter.extension"
                ],
            ]),
            sources: ["Corpse/Reporter/**"],
            entitlements: .dictionary([
                "com.apple.security.application-groups": .array([.string(corpseAppGroup)])
            ]),
            dependencies: [
                .package(product: "KSCrash", type: .runtime),
                .package(product: "CrashReportExtension", type: .runtime),
            ],
            settings: .settings(
                base:
                    corpseSigning
                    .merging(["SUPPORTED_PLATFORMS": "iphoneos"]) { _, new in new })
        ),

        .target(
            name: "CorpseTests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "\(corpseHostBundleID).Tests",
            deploymentTargets: .iOS("27.0"),
            sources: ["Corpse/Tests/**"],
            dependencies: [
                .target(name: "CorpseHost")
            ],
            settings: .settings(
                base: corpseSigning.merging([
                    // BrowserStack discovers tests via `nm -U -g | grep '.test'`.
                    // -enable-testing exports Swift symbols globally (T not t).
                    "OTHER_SWIFT_FLAGS": ["-Xfrontend", "-enable-testing"]
                ]) { _, new in new })
        ),
    ],
    schemes: [
        .scheme(
            name: "Sample",
            shared: true,
            buildAction: .buildAction(targets: ["Sample"]),
            testAction: .testPlans(["Tests/Integration.xctestplan"], configuration: .release, attachDebugger: false),
            runAction: .runAction(executable: "Sample")
        ),
        // Its own scheme, not part of Sample's: Sample's test plan runs on
        // simulators, and nothing here can run anywhere but a device.
        .scheme(
            name: "CorpseBrowserStack",
            shared: true,
            buildAction: .buildAction(targets: ["CorpseHost", "CorpseTests"]),
            // attachDebugger defaults to true, and the launch watchdog does not
            // fire under a debugger: a hung launch simply sits there instead of
            // being killed with 0x8badf00d, so the termination under test never
            // happens. Sample's own test action turns it off for the same reason.
            testAction: .targets(["CorpseTests"], configuration: .release, attachDebugger: false),
            runAction: .runAction(executable: "CorpseHost")
        ),
    ]
)

extension Set where Element == ProjectDescription.Destination {
    static var allForSample: Self {
        let sets: [Set<Destination>] = [
            .iOS,
            .macOS,
            .tvOS,
            .watchOS,
            .visionOS,
        ]
        return sets.reduce(.init()) { $0.union($1) }
    }
}

extension DeploymentTargets {
    static var allForSample: Self {
        .multiplatform(
            iOS: "15.0",
            macOS: "13.0",
            watchOS: "8.0",
            tvOS: "15.0",
            visionOS: "1.0"
        )
    }

    var excludingVisionOS: Self {
        var excluded = self
        excluded.visionOS = nil
        return excluded
    }
}
