//
//  NamespaceDetectionTests.swift
//
//  Created by Claude on 2026-02-12.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#if os(macOS)

    import Foundation
    import XCTest

    // MARK: - Logic extracted from Package.swift for testability

    /// Sanitizes a raw package name to a valid C identifier suffix.
    /// Returns nil if the result would be empty.
    private func sanitizePackageName(_ rawName: String) -> String? {
        let sanitized = String(rawName.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : "_" })
        return sanitized.isEmpty ? nil : "_" + sanitized
    }

    /// Parses a consumer root path from a KSCrash SPM CLI checkout path.
    /// Returns nil if the path doesn't match the `.build/checkouts/` pattern.
    private func consumerRootFromCheckoutPath(_ packageDir: String) -> String? {
        let components = packageDir.split(separator: "/", omittingEmptySubsequences: false)
        guard let checkoutsIdx = components.lastIndex(of: "checkouts"),
            checkoutsIdx >= 1,
            components[checkoutsIdx - 1] == ".build"
        else {
            return nil
        }
        return "/" + components[..<(checkoutsIdx - 1)].joined(separator: "/")
    }

    /// Extracts the Xcode project name from a SourcePackages checkout path.
    /// Path: .../<ProjectName-hash>/SourcePackages/checkouts/KSCrash
    /// Returns nil if the path doesn't match the Xcode layout.
    private func projectNameFromXcodePath(_ packageDir: String) -> String? {
        let components = packageDir.split(separator: "/", omittingEmptySubsequences: false)
        guard let checkoutsIdx = components.lastIndex(of: "checkouts"),
            checkoutsIdx >= 2,
            components[checkoutsIdx - 1] == "SourcePackages"
        else {
            return nil
        }
        let derivedDataSubdir = String(components[checkoutsIdx - 2])
        guard let lastHyphen = derivedDataSubdir.lastIndex(of: "-") else { return nil }
        let name = String(derivedDataSubdir[..<lastHyphen])
        return name.isEmpty ? nil : name
    }

    /// Extracts the package name from Package.swift contents.
    /// Returns nil if parsing fails.
    private func extractPackageName(from contents: String) -> String? {
        guard let nameStart = contents.range(of: "name:"),
            let openQuote = contents[nameStart.upperBound...].firstIndex(of: "\"")
        else { return nil }
        let afterOpen = contents.index(after: openQuote)
        guard let closeQuote = contents[afterOpen...].firstIndex(of: "\"") else { return nil }
        return String(contents[afterOpen..<closeQuote])
    }

    /// Full detection logic (minus env var and file reading) for a given path and Package.swift contents.
    private func detectNamespace(packageDir: String, consumerPackageContents: String?) -> String? {
        // SPM CLI path
        if consumerRootFromCheckoutPath(packageDir) != nil,
            let contents = consumerPackageContents,
            let rawName = extractPackageName(from: contents)
        {
            return sanitizePackageName(rawName)
        }
        // Xcode path
        if let projectName = projectNameFromXcodePath(packageDir) {
            return sanitizePackageName(projectName)
        }
        return nil
    }

    // MARK: - Tests

    final class NamespaceSanitizationTests: XCTestCase {

        func testSimpleName() {
            XCTAssertEqual(sanitizePackageName("MyApp"), "_MyApp")
        }

        func testNameWithNumbers() {
            XCTAssertEqual(sanitizePackageName("MyApp123"), "_MyApp123")
        }

        func testNameWithUnderscores() {
            XCTAssertEqual(sanitizePackageName("My_App"), "_My_App")
        }

        func testNameWithHyphens() {
            XCTAssertEqual(sanitizePackageName("my-app"), "_my_app")
        }

        func testNameWithDots() {
            XCTAssertEqual(sanitizePackageName("com.example.app"), "_com_example_app")
        }

        func testNameWithSpecialCharacters() {
            XCTAssertEqual(sanitizePackageName("My-App@v2!"), "_My_App_v2_")
        }

        func testNameWithSpaces() {
            XCTAssertEqual(sanitizePackageName("My App"), "_My_App")
        }

        func testNameWithNonASCII() {
            XCTAssertEqual(sanitizePackageName("MüApp"), "_M_App")
        }

        func testEmptyName() {
            XCTAssertNil(sanitizePackageName(""))
        }

        func testAllSpecialCharacters() {
            // All chars replaced with underscores — still valid
            XCTAssertEqual(sanitizePackageName("@#$"), "____")
        }

        func testSingleCharName() {
            XCTAssertEqual(sanitizePackageName("A"), "_A")
        }

        func testNumericOnlyName() {
            XCTAssertEqual(sanitizePackageName("123"), "_123")
        }

        func testLeadingUnderscore() {
            XCTAssertEqual(sanitizePackageName("_private"), "__private")
        }
    }

    final class CheckoutPathDetectionTests: XCTestCase {

        func testValidCheckoutPath() {
            let path = "/Users/dev/MyApp/.build/checkouts/KSCrash"
            XCTAssertEqual(consumerRootFromCheckoutPath(path), "/Users/dev/MyApp")
        }

        func testValidCheckoutPathWithDeepNesting() {
            let path = "/Users/dev/Projects/iOS/MyApp/.build/checkouts/KSCrash"
            XCTAssertEqual(consumerRootFromCheckoutPath(path), "/Users/dev/Projects/iOS/MyApp")
        }

        func testDevelopmentPath() {
            let path = "/Users/dev/KSCrash"
            XCTAssertNil(consumerRootFromCheckoutPath(path))
        }

        func testPathWithoutBuildDir() {
            let path = "/Users/dev/MyApp/checkouts/KSCrash"
            XCTAssertNil(consumerRootFromCheckoutPath(path))
        }

        func testPathWithBuildButNotCheckouts() {
            let path = "/Users/dev/MyApp/.build/repositories/KSCrash"
            XCTAssertNil(consumerRootFromCheckoutPath(path))
        }

        func testRootLevelCheckout() {
            let path = "/MyApp/.build/checkouts/KSCrash"
            XCTAssertEqual(consumerRootFromCheckoutPath(path), "/MyApp")
        }

        func testMultipleBuildDirs() {
            // The last `.build/checkouts` pair should win
            let path = "/workspace/.build/checkouts/SomeDep/.build/checkouts/KSCrash"
            XCTAssertEqual(
                consumerRootFromCheckoutPath(path),
                "/workspace/.build/checkouts/SomeDep"
            )
        }

        func testCheckoutsWithExtraSubdirectories() {
            let path = "/Users/dev/MyApp/.build/checkouts/KSCrash/Sources"
            XCTAssertEqual(consumerRootFromCheckoutPath(path), "/Users/dev/MyApp")
        }
    }

    final class XcodePathDetectionTests: XCTestCase {

        func testStandardXcodeDerivedDataPath() {
            let path =
                "/Users/dev/Library/Developer/Xcode/DerivedData/MyApp-bwrfhsjkqlnvep/SourcePackages/checkouts/KSCrash"
            XCTAssertEqual(projectNameFromXcodePath(path), "MyApp")
        }

        func testXcodeProjectWithHyphens() {
            // Project name contains hyphens — last hyphen separates the hash
            let path =
                "/Users/dev/Library/Developer/Xcode/DerivedData/my-cool-app-abcdef123456/SourcePackages/checkouts/KSCrash"
            XCTAssertEqual(projectNameFromXcodePath(path), "my-cool-app")
        }

        func testCustomDerivedDataLocation() {
            let path = "/Volumes/Build/DerivedData/MyApp-xyz123/SourcePackages/checkouts/KSCrash"
            XCTAssertEqual(projectNameFromXcodePath(path), "MyApp")
        }

        func testDerivedDataSubdirWithoutHash() {
            // No hyphen in directory name — can't extract project name
            let path = "/Users/dev/DerivedData/MyApp/SourcePackages/checkouts/KSCrash"
            XCTAssertNil(projectNameFromXcodePath(path))
        }

        func testSPMPathNotMatchedAsXcode() {
            let path = "/Users/dev/MyApp/.build/checkouts/KSCrash"
            XCTAssertNil(projectNameFromXcodePath(path))
        }

        func testDevelopmentPathNotMatched() {
            let path = "/Users/dev/KSCrash"
            XCTAssertNil(projectNameFromXcodePath(path))
        }

        func testSourcePackagesWithExtraSubdirectories() {
            let path = "/Users/dev/DerivedData/MyApp-abc123/SourcePackages/checkouts/KSCrash/Sources"
            XCTAssertEqual(projectNameFromXcodePath(path), "MyApp")
        }
    }

    final class PackageNameExtractionTests: XCTestCase {

        func testStandardPackageSwift() {
            let contents = """
                // swift-tools-version:5.9
                import PackageDescription
                let package = Package(
                    name: "MyApp",
                    products: []
                )
                """
            XCTAssertEqual(extractPackageName(from: contents), "MyApp")
        }

        func testPackageNameWithHyphen() {
            let contents = """
                let package = Package(
                    name: "my-cool-app",
                    platforms: [.iOS(.v15)]
                )
                """
            XCTAssertEqual(extractPackageName(from: contents), "my-cool-app")
        }

        func testPackageNameWithSpacesAroundColon() {
            let contents = """
                let package = Package(
                    name : "SpaceyApp",
                    products: []
                )
                """
            XCTAssertEqual(extractPackageName(from: contents), "SpaceyApp")
        }

        func testNoNameField() {
            let contents = """
                let package = Package(
                    products: []
                )
                """
            XCTAssertNil(extractPackageName(from: contents))
        }

        func testMalformedNoClosingQuote() {
            let contents = """
                let package = Package(
                    name: "Broken
                )
                """
            // The closing quote is on the next line at the closing paren, but let's see what happens
            // Actually "Broken\n)" — there IS no quote before newline in the same way
            // The function looks for the next `"` after the open quote, which would be missing
            // Actually... "Broken\n    )\n    " — wait, triple-quoted strings.
            // Let me think: the contents string is:
            //   ...name: "Broken\n)\n"
            // openQuote points to the `"` before Broken
            // afterOpen points to `B`
            // closeQuote searches for `"` in "Broken\n)\n" — there is a `"` at the end of the triple quote
            // Actually no, in the raw string `"Broken` is followed by newline, then `)`, newline, then `"""` closing
            // But the actual string contents won't have `"""` — the Swift multiline string literal produces:
            //   ...name: "Broken\n)\n
            // So there's no closing `"` character in the parsed string content... wait, there IS a `"` wrapping "Broken"
            // Hmm, in the Package.swift source text, name: "Broken\n is the literal characters, and the `"` before Broken IS there
            // After the opening `"`, it searches for the NEXT `"` — but there isn't one in "Broken\n)\n"
            // Wait: the literal text is: name: "Broken followed by newline. So the open quote is found, afterOpen is "B",
            // and the search for closeQuote in "Broken\n)\n" finds no `"`, so it returns nil. Good.
            XCTAssertNil(extractPackageName(from: contents))
        }

        func testEmptyPackageName() {
            let contents = """
                let package = Package(
                    name: "",
                    products: []
                )
                """
            XCTAssertEqual(extractPackageName(from: contents), "")
        }

        func testNameFieldInComment() {
            // name: appears in a comment first, then in actual code
            // The function finds the FIRST occurrence of "name:" which is in the comment
            let contents = """
                // name: "CommentedName"
                let package = Package(
                    name: "RealName",
                    products: []
                )
                """
            XCTAssertEqual(extractPackageName(from: contents), "CommentedName")
        }
    }

    final class EndToEndDetectionTests: XCTestCase {

        func testDevelopmentModeReturnsNil() {
            let result = detectNamespace(
                packageDir: "/Users/dev/KSCrash",
                consumerPackageContents: nil
            )
            XCTAssertNil(result)
        }

        func testCheckoutWithValidConsumer() {
            let result = detectNamespace(
                packageDir: "/Users/dev/MyApp/.build/checkouts/KSCrash",
                consumerPackageContents: """
                    let package = Package(
                        name: "MyApp",
                        products: []
                    )
                    """
            )
            XCTAssertEqual(result, "_MyApp")
        }

        func testCheckoutWithHyphenatedConsumer() {
            let result = detectNamespace(
                packageDir: "/Users/dev/my-app/.build/checkouts/KSCrash",
                consumerPackageContents: """
                    let package = Package(
                        name: "my-cool-app",
                        products: []
                    )
                    """
            )
            XCTAssertEqual(result, "_my_cool_app")
        }

        func testCheckoutWithMalformedConsumerPackage() {
            let result = detectNamespace(
                packageDir: "/Users/dev/MyApp/.build/checkouts/KSCrash",
                consumerPackageContents: "this is not a valid Package.swift"
            )
            XCTAssertNil(result)
        }

        func testCheckoutWithEmptyConsumerName() {
            let result = detectNamespace(
                packageDir: "/Users/dev/MyApp/.build/checkouts/KSCrash",
                consumerPackageContents: """
                    let package = Package(
                        name: "",
                        products: []
                    )
                    """
            )
            XCTAssertNil(result)
        }

        // -- Xcode paths --

        func testXcodeDerivedDataPath() {
            let result = detectNamespace(
                packageDir:
                    "/Users/dev/Library/Developer/Xcode/DerivedData/MyApp-bwrfhsjkqlnvep/SourcePackages/checkouts/KSCrash",
                consumerPackageContents: nil  // not used for Xcode path
            )
            XCTAssertEqual(result, "_MyApp")
        }

        func testXcodeProjectWithHyphens() {
            let result = detectNamespace(
                packageDir: "/Users/dev/DerivedData/my-cool-app-abc123/SourcePackages/checkouts/KSCrash",
                consumerPackageContents: nil
            )
            XCTAssertEqual(result, "_my_cool_app")
        }

        func testXcodeProjectWithoutHash() {
            // No hyphen in DerivedData subdir — can't determine project name
            let result = detectNamespace(
                packageDir: "/Users/dev/DerivedData/MyApp/SourcePackages/checkouts/KSCrash",
                consumerPackageContents: nil
            )
            XCTAssertNil(result)
        }
    }

    // MARK: - Integration tests using swift package dump-package

    final class PackageManifestIntegrationTests: XCTestCase {

        private let kscrashRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // KSCrashNamespaceDetectionTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // KSCrash/
            .path

        private func dumpPackage(env: [String: String] = [:]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swift", "package", "dump-package"]
            process.currentDirectoryURL = URL(fileURLWithPath: kscrashRoot)

            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env {
                environment[key] = value
            }
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "PackageManifestIntegrationTests",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "swift package dump-package failed"]
                )
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }

        func testDevelopmentModeNoNamespace() throws {
            let json = try dumpPackage()
            // In development mode, no KSCRASH_NAMESPACE define should be present
            XCTAssertFalse(
                json.contains("KSCRASH_NAMESPACE"),
                "Development mode should not contain KSCRASH_NAMESPACE defines"
            )
        }

        func testEnvVarOverride() throws {
            let json = try dumpPackage(env: ["KSCRASH_NAMESPACE": "_TestNS"])
            XCTAssertTrue(
                json.contains("KSCRASH_NAMESPACE"),
                "Env var override should produce KSCRASH_NAMESPACE defines"
            )
            XCTAssertTrue(
                json.contains("_TestNS"),
                "Env var override value should appear in the manifest"
            )
        }

        func testEmptyEnvVarDisablesNamespace() throws {
            let json = try dumpPackage(env: ["KSCRASH_NAMESPACE": ""])
            XCTAssertFalse(
                json.contains("KSCRASH_NAMESPACE"),
                "Empty env var should disable namespace (no defines)"
            )
        }
    }

    // MARK: - End-to-end build integration test

    final class SymbolNamespacingBuildTests: XCTestCase {

        private var kscrashRoot: String {
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // KSCrashNamespaceDetectionTests/
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // KSCrash/
                .path
        }

        /// Full end-to-end test of automatic namespace detection.
        ///
        /// Simulates the real consumer experience: a package named "MyTestApp"
        /// adds KSCrash as a versioned dependency, runs `swift build`, and
        /// — without any configuration — compiled KSCrash symbols carry a
        /// suffix derived from the consumer's package name.
        ///
        /// Steps:
        /// 1. Creates a local git repo from the current KSCrash source and tags it.
        /// 2. Creates a consumer package ("MyTestApp") depending on KSCrash via
        ///    a `file://` URL, exactly like a real versioned dependency.
        /// 3. Builds. SPM clones KSCrash into `.build/checkouts/KSCrash/`,
        ///    triggering path-based auto-detection in Package.swift.
        /// 4. Uses `nm` to verify `kscrash_install` became `kscrash_install_MyTestApp`.
        func testAutoNamespacingEndToEnd() throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("KSCrashAutoNS_\(ProcessInfo.processInfo.globallyUniqueString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // -- Local git repo from current KSCrash source --

            let repoDir = tempDir.appendingPathComponent("KSCrash").path
            try FileManager.default.createDirectory(
                atPath: repoDir, withIntermediateDirectories: true
            )

            // Export committed tree
            try shell("cd '\(kscrashRoot)' && git archive HEAD | tar -x -C '\(repoDir)'")

            // Overlay uncommitted changes (the namespace feature itself)
            try shell(
                """
                cp '\(kscrashRoot)/Package.swift' '\(repoDir)/Package.swift'
                cp '\(kscrashRoot)/Sources/KSCrashCore/include/KSCrashNamespace.h' \
                   '\(repoDir)/Sources/KSCrashCore/include/KSCrashNamespace.h'
                mkdir -p '\(repoDir)/Tests/KSCrashNamespaceDetectionTests'
                cp '\(kscrashRoot)/Tests/KSCrashNamespaceDetectionTests/NamespaceDetectionTests.swift' \
                   '\(repoDir)/Tests/KSCrashNamespaceDetectionTests/'
                """)

            // SPM rejects .unsafeFlags in dependencies — strip them so the
            // package can be consumed as a versioned dependency.
            try shell("sed -i '' '/\\.unsafeFlags(warningFlags)/d' '\(repoDir)/Package.swift'")

            // Commit and tag
            try shell(
                """
                cd '\(repoDir)' && \
                git init -q && \
                git add -A && \
                git -c user.name=test -c user.email=test@test.com \
                    commit -q -m 'ns test' --no-gpg-sign && \
                git tag 99.0.0
                """)

            // -- Consumer package ("MyTestApp") --

            let consumerDir = tempDir.appendingPathComponent("MyTestApp").path
            try FileManager.default.createDirectory(
                atPath: consumerDir + "/Sources/MyTestApp",
                withIntermediateDirectories: true
            )

            try """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(
                name: "MyTestApp",
                platforms: [.macOS(.v12), .iOS(.v16)],
                dependencies: [
                    .package(url: "file://\(repoDir)", exact: "99.0.0")
                ],
                targets: [
                    .target(name: "MyTestApp",
                            dependencies: [.product(name: "Recording", package: "KSCrash")])
                ]
            )
            """.write(
                toFile: consumerDir + "/Package.swift",
                atomically: true, encoding: .utf8)

            try "public let _placeholder = 0\n".write(
                toFile: consumerDir + "/Sources/MyTestApp/Placeholder.swift",
                atomically: true, encoding: .utf8
            )

            // -- Build (no env vars, no configuration — pure auto-detection) --

            try shell("swift build --package-path '\(consumerDir)'")

            // -- Verify symbols --
            // Auto-detected namespace: "MyTestApp" → "_MyTestApp"
            // kscrash_install → kscrash_install_MyTestApp → _kscrash_install_MyTestApp in nm

            let symbols = try shell(
                """
                find '\(consumerDir)/.build' -name '*.o' -path '*KSCrash*' \
                    -exec nm -gU {} + 2>/dev/null
                """)

            XCTAssertFalse(symbols.isEmpty, "nm should find symbols in KSCrash object files")

            XCTAssertTrue(
                symbols.contains("_kscrash_install_MyTestApp"),
                "Expected auto-namespaced symbol _kscrash_install_MyTestApp"
            )

            let hasUnnamespaced = symbols.split(separator: "\n").contains { line in
                line.hasSuffix(" _kscrash_install")
            }
            XCTAssertFalse(
                hasUnnamespaced,
                "Un-namespaced _kscrash_install should not appear as a defined symbol"
            )
        }

        // MARK: - Helpers

        /// Runs a shell command, returns stdout. Throws on non-zero exit.
        @discardableResult
        private func shell(_ command: String) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]

            // Use temp files instead of pipes to avoid buffer-full deadlocks
            // on large build output.
            let outFile = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let errFile = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: outFile.path, contents: nil)
            FileManager.default.createFile(atPath: errFile.path, contents: nil)
            defer {
                try? FileManager.default.removeItem(at: outFile)
                try? FileManager.default.removeItem(at: errFile)
            }

            process.standardOutput = try FileHandle(forWritingTo: outFile)
            process.standardError = try FileHandle(forWritingTo: errFile)
            try process.run()
            process.waitUntilExit()

            let stdout = (try? String(contentsOf: outFile, encoding: .utf8)) ?? ""
            let stderr = (try? String(contentsOf: errFile, encoding: .utf8)) ?? ""

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "SymbolNamespacingBuildTests",
                    code: Int(process.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Command failed (\(process.terminationStatus)):\n\(stderr.suffix(2000))"
                    ]
                )
            }
            return stdout
        }
    }

#endif  // os(macOS)
