//
//  KeychainRelay.swift
//
//  Created by Alexander Cohen on 2026-09-26.
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

import Foundation
import KSCrash
import KSCrashReportModel
import Security
import os

/// Carries finished reports from the extension to the app through the keychain, for when
/// the two share no container.
///
/// That is how BrowserStack runs them: its re-signing strips the App Group from both
/// targets and emulates the group for the app alone, inside the app's own container, but
/// leaves the two one shared keychain access group. On a device signed as built the group
/// resolves and nothing goes through here.
///
/// Compiled into both targets. The extension moves each report it captured into a
/// keychain item named by the report's file name; the app reads them back as a
/// `ReportSource`, so they reach its store the way any source's reports do.
enum KeychainRelay {
    private static let service = "com.github.kstenerud.KSCrash.CorpseRelay"
    private static let log = OSLog(subsystem: "com.github.kstenerud.KSCrash.CorpseApp", category: "relay")

    /// Moves every finished report in `reportsDirectory` into the keychain, deleting each
    /// file once its item is stored. A report that cannot be stored stays for the next crash.
    static func moveReports(in reportsDirectory: URL) {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: reportsDirectory.path)
        } catch {
            os_log(.error, log: log, "Could not list %{public}@: %{public}@", reportsDirectory.path, "\(error)")
            return
        }
        for name in names where identity(ofReportNamed: name) != nil {
            let file = reportsDirectory.appendingPathComponent(name)
            do {
                try store(try Data(contentsOf: file), named: name)
                try FileManager.default.removeItem(at: file)
            } catch {
                os_log(.error, log: log, "Could not relay %{public}@: %{public}@", name, "\(error)")
            }
        }
    }

    /// The report's id and write time, from a store's report file name
    /// ("<20-digit nanoseconds>-<lowercase uuid>.json"); nil for any other name.
    static func identity(ofReportNamed name: String) -> (id: Report.ID, timestamp: Date)? {
        let parts = name.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 20, parts[0].allSatisfy(\.isASCII), parts[1].hasSuffix(".json"),
            let ns = UInt64(parts[0]), let id = Report.ID(String(parts[1].dropLast(".json".count)))
        else { return nil }
        return (id, Date(timeIntervalSince1970: Double(ns) / 1_000_000_000))
    }

    private static func item(named name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
    }

    private static func store(_ data: Data, named name: String) throws {
        SecItemDelete(item(named: name) as CFDictionary)
        var add = item(named: name)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// The names of every relayed report waiting in the keychain.
    fileprivate static func relayedNames() throws -> [String] {
        var query = item(named: "")
        query.removeValue(forKey: kSecAttrAccount as String)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let attributes = found as? [[String: Any]] else {
            throw KeychainError(status: status)
        }
        return attributes.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    fileprivate static func data(named name: String) throws -> Data {
        var query = item(named: name)
        query[kSecReturnData as String] = true
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        guard status == errSecSuccess, let data = found as? Data else { throw KeychainError(status: status) }
        return data
    }

    fileprivate static func logFailure(_ what: String, _ name: String, _ error: Error) {
        os_log(.error, log: log, "Could not %{public}@ %{public}@: %{public}@", what, name, "\(error)")
    }

    fileprivate static func delete(named name: String) {
        let status = SecItemDelete(item(named: name) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            os_log(.error, log: log, "Could not remove relayed report %{public}@: %{public}d", name, status)
        }
    }

    struct KeychainError: Error {
        let status: OSStatus
    }
}

/// The reports the extension relayed through the keychain, offered to the app's send.
struct KeychainReportSource: ReportSource {
    func makeReader() -> Reader { Reader() }

    struct Reader: ReportReader {
        private var names: [String]?
        /// The item the last report came from, deleted once the store has taken it.
        private var offered: String?

        mutating func next() async throws -> IncomingReport? {
            if names == nil {
                names = try KeychainRelay.relayedNames()
            }
            while let name = names?.popLast() {
                guard let identity = KeychainRelay.identity(ofReportNamed: name) else { continue }
                let data: Data
                do {
                    data = try KeychainRelay.data(named: name)
                } catch {
                    // One unreadable item stays for a later send; the rest still go.
                    KeychainRelay.logFailure("read relayed report", name, error)
                    continue
                }
                offered = name
                return IncomingReport(content: .data(data), id: identity.id, timestamp: identity.timestamp)
            }
            return nil
        }

        mutating func finish(_ report: IncomingReport, as disposition: IncomingReport.Disposition) async {
            guard disposition == .taken, let offered else { return }
            KeychainRelay.delete(named: offered)
        }
    }
}
