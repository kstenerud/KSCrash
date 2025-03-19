//
//  PartialCrashReport.swift
//
//  Created by Nikolay Volosatov on 2024-08-03.
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

// swift-format-ignore: AlwaysUseLowerCamelCase
struct PartialCrashReport: Decodable {
    struct BinaryImage: Decodable {
        var image_addr: UInt64?
        var image_size: UInt64?
        var name: String?
        var uuid: String?
        var cpu_type: Int?
        var cpu_subtype: Int?
        var major_version: Int?
        var minor_version: Int?
        var revision_version: Int?
    }

    struct Report: Decodable {
        var binary_images: [BinaryImage]?
    }

    struct Crash: Decodable {
        struct Error: Decodable {
            struct Signal: Decodable {
                var signal: Int?
                var name: String?
                var code: Int?
                var code_name: String?
            }
            struct NSException: Decodable {
                var name: String?
                var userInfo: String?
            }
            struct UserReported: Decodable {
                var name: String?
                var language: String?
                var line_of_code: String?
                var backtrace: [String]?  // Can be actually any JSON encodable structure
            }

            var reason: String?
            var type: String?

            var signal: Signal?
            var nsexception: NSException?
            var user_reported: UserReported?
        }

        struct Thread: Decodable {
            struct Backtrace: Decodable {
                struct Frame: Decodable {
                    var instruction_addr: UInt64

                    var object_addr: UInt64?
                    var object_name: String?

                    var symbol_addr: UInt64?
                    var symbol_name: String?
                }

                var contents: [Frame]
            }

            var index: Int
            var state: String
            var crashed: Bool
            var backtrace: Backtrace
        }

        var error: Error?
        var threads: [Thread]?
    }

    var crash: Crash?
    var report: Report?
    var binary_images: [BinaryImage]?
}
