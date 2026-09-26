//
//  CorpseReporter.swift
//
//  Created by Alexander Cohen on 2026-09-19.
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

// CrashReportExtension ships in the device SDK only and is absent from the
// simulator SDK, so the whole extension is gated on being able to import it.
// Paired with SUPPORTED_PLATFORMS = iphoneos on this target.
#if canImport(CrashReportExtension)

    import CrashReportExtension
    import ExtensionFoundation
    import Foundation
    import KSCrash
    import KSCrashCrashReportExtension
    import os
    import Security

    /// The other half of the test: a real extension the system invokes after the
    /// app dies, in its own process, with a read-only port onto the corpse.
    ///
    /// It shares one thing with the app, the app group, and rebuilds the
    /// `CorpseReportingConfiguration` from it independently. That duplication is
    /// deliberate: a mismatch between the two sides is one of the failures this
    /// test exists to catch, and a shared constant would hide it. Where the group
    /// does not resolve, as on BrowserStack, the store is relayed instead (see
    /// `relayArea`).
    @main
    struct CorpseReporter: CrashReporterExtension {

        private static let logger = Logger(
            subsystem: "com.github.kstenerud.KSCrash.CorpseApp.Reporter", category: "extension")

        static let area = CorpseReportingConfiguration(
            namespace: "KSCrashCorpseTests",
            container: .appGroup("group.com.github.kstenerud.KSCrash.Corpse"))

        /// Where reports go when the app group does not resolve, which is how
        /// BrowserStack runs this extension: its re-signing strips the group from
        /// both targets and emulates it for the host alone, inside the host's own
        /// container. The two processes keep a shared keychain access group, so
        /// the store written here is relayed to the host through the keychain.
        /// On a device signed as built, the group resolves and nothing is relayed.
        static let relayArea = CorpseReportingConfiguration(namespace: "KSCrashCorpseTests", container: .caches)

        /// Whether captures are relayed, decided once at install.
        private static let relays =
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.github.kstenerud.KSCrash.Corpse") == nil

        init() {
            do {
                try KSCrash.shared.installForCorpseReporting(with: Self.relays ? Self.relayArea : Self.area)
            } catch {
                // The app asserts on the report's absence, so a failure here has to
                // be visible in the device log or the test looks like a capture bug.
                Self.logger.error("corpse-reporting install failed: \(error)")
            }
        }

        func processCrashReport(process: CrashedProcess) {
            // reason.exception and reason.codes are the Mach exception type and
            // codes; logging them is what lets a failed run say which termination
            // kind the system actually delivered, versus the one we asked for.
            let exception = process.reason.exception
            let codes = process.reason.codes
            do {
                let id = try KSCrash.shared.captureCrashReport(from: process)
                Self.logger.log("captured \(id.description) exception \(exception) codes \(codes)")
                if Self.relays {
                    Self.relayStore()
                }
            } catch {
                Self.logger.error("capture failed for exception \(exception): \(error)")
            }
        }

        /// Copies every file of the relay area into the keychain, one item per
        /// file, keyed by its path below the namespace directory, which is the
        /// layout the host's corpse area expects. The host restores them and
        /// removes the items.
        private static func relayStore() {
            guard
                let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            else { return }
            let root = caches.appendingPathComponent("KSCrash/\(relayArea.namespace)", isDirectory: true)
            guard let paths = FileManager.default.subpaths(atPath: root.path) else { return }
            for path in paths {
                var isDirectory: ObjCBool = false
                let url = root.appendingPathComponent(path)
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                    !isDirectory.boolValue,
                    let data = try? Data(contentsOf: url)
                else { continue }
                let item: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "com.github.kstenerud.KSCrash.CorpseRelay",
                    kSecAttrAccount as String: path,
                ]
                SecItemDelete(item as CFDictionary)
                var add = item
                add[kSecValueData as String] = data
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                let status = SecItemAdd(add as CFDictionary, nil)
                if status != errSecSuccess {
                    logger.error("could not relay \(path): \(status)")
                }
            }
        }
    }

#endif
