//
//  CrashReportDecoder.swift
//
//  Created by KSCrash on 2024.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// A decoder for KSCrash crash reports.
public struct CrashReportDecoder: Sendable {
    private let decoder: JSONDecoder

    /// Creates a new crash report decoder.
    public init() {
        self.decoder = JSONDecoder()
    }

    /// Decodes a crash report from JSON data.
    ///
    /// - Parameter data: The JSON data representing a crash report.
    /// - Returns: The decoded crash report.
    /// - Throws: `DecodingError` if the data cannot be decoded.
    public func decode(from data: Data) throws -> CrashReport {
        try decoder.decode(CrashReport.self, from: data)
    }

    /// Decodes a crash report from a file URL.
    ///
    /// - Parameter url: The URL of a JSON file containing a crash report.
    /// - Returns: The decoded crash report.
    /// - Throws: `DecodingError` if the file cannot be read or decoded.
    public func decode(from url: URL) throws -> CrashReport {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }

    /// Decodes a crash report from a JSON string.
    ///
    /// - Parameter jsonString: A JSON string representing a crash report.
    /// - Returns: The decoded crash report.
    /// - Throws: `DecodingError` if the string cannot be decoded.
    public func decode(from jsonString: String) throws -> CrashReport {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Could not convert string to UTF-8 data"
                )
            )
        }
        return try decode(from: data)
    }
}

// MARK: - CrashReport Convenience Initializers

extension CrashReport {
    /// Decodes a crash report from JSON data.
    ///
    /// - Parameter data: The JSON data representing a crash report.
    /// - Returns: The decoded crash report.
    /// - Throws: `DecodingError` if the data cannot be decoded.
    public static func decode(from data: Data) throws -> CrashReport {
        try CrashReportDecoder().decode(from: data)
    }

    /// Decodes a crash report from a file URL.
    ///
    /// - Parameter url: The URL of a JSON file containing a crash report.
    /// - Returns: The decoded crash report.
    /// - Throws: `DecodingError` if the file cannot be read or decoded.
    public static func decode(from url: URL) throws -> CrashReport {
        try CrashReportDecoder().decode(from: url)
    }

    /// Decodes a crash report from a JSON string.
    ///
    /// - Parameter jsonString: A JSON string representing a crash report.
    /// - Returns: The decoded crash report.
    /// - Throws: `DecodingError` if the string cannot be decoded.
    public static func decode(from jsonString: String) throws -> CrashReport {
        try CrashReportDecoder().decode(from: jsonString)
    }
}
