//
//  UserInfoInputView.swift
//
//  Created by Nikolay Volosatov on 2024-07-20.
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
import LibraryBridge
import Logging
import SwiftUI

struct UserInfoInputView: View {
    private static let logger = Logger(label: "UserInfoInputView")

    @Binding var userInfo: [String: Any]?

    @State private var text: String?
    @State private var errorMessage: String?

    @FocusState private var isEditing: Bool

    private var formattedUserInfo: String? {
        guard let userInfo else { return nil }
        do {
            let encodedData = try JSONSerialization.data(
                withJSONObject: userInfo,
                options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            )
            return String(data: encodedData, encoding: .utf8)!
        } catch {
            Self.logger.error("Unexpected non-serializable user info: \(userInfo)")
            return nil
        }
    }

    private var textBinding: Binding<String> {
        .init(
            get: {
                if let text { return text }
                guard userInfo != nil else { return "" }
                return formattedUserInfo ?? ""
            },
            set: { newText in
                text = newText
                errorMessage = nil

                guard let text, !text.isEmpty else {
                    userInfo = nil
                    return
                }
                guard let data = text.data(using: .utf8) else {
                    errorMessage = "Can't encode"
                    return
                }
                do {
                    let object = try JSONSerialization.jsonObject(with: data)
                    guard let userInfo = object as? [String: Any]? else {
                        errorMessage = "JSON should have an object as a root element"
                        return
                    }
                    self.userInfo = userInfo
                } catch {
                    errorMessage = "Can't parse JSON: \(error.localizedDescription)"
                }
            }
        )
    }

    func setPreset(_ val: [String: Any]?) {
        userInfo = val
        text = formattedUserInfo
        isEditing = false
    }

    var body: some View {
        List {
            Section(header: Text("JSON text")) {
                #if os(tvOS) || os(watchOS)
                    Text("Editing is not available, use presets")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                #else
                    TextEditor(text: textBinding)
                        .focused($isEditing)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.asciiCapable)
                        #endif
                        .frame(minHeight: 200)
                #endif
            }
            Section(header: Text("Presets")) {
                Button("nil") { setPreset(nil) }
                Button(##"{"a":"b"}"##) { setPreset(["a": "b"]) }
                Button(##"{"a":{"b":["1","2"]}}"##) { setPreset(["a": ["b": ["1", "2"]]]) }
            }
            Section(header: Text("Validation")) {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Color.red)
                } else {
                    Group {
                        if let formattedUserInfo {
                            Text(formattedUserInfo)
                        } else {
                            Text("nil")
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.secondary)
                }
            }
        }
    }
}
