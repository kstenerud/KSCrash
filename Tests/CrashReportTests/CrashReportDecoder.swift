//
//  CrashReportDecoder.swift
//
//  Created by Alexander Cohen on 2024-12-09.
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

import CrashReport
import Foundation

extension CrashReport where UserData == NoUserData {
    static func decode(from json: String) throws -> CrashReport<NoUserData> {
        guard let data = json.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to convert JSON string to UTF-8 data"
                )
            )
        }
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> CrashReport<NoUserData> {
        let decoder = JSONDecoder()
        return try decoder.decode(CrashReport<NoUserData>.self, from: data)
    }

    static func decode(from url: URL) throws -> CrashReport<NoUserData> {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }
}
