//
//  InstallView.swift
//
//  Created by Nikolay Volosatov on 2024-07-07.
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
import SwiftUI
import LibraryBridge

struct InstallView: View {
    @ObservedObject var bridge = InstallBridge()

    @Binding var installed: Bool

    var body: some View {
        List {
            Button("Install") {
                bridge.install()
                installed = true
            }
            .foregroundColor(.primary)

            Section(header: Text("Static Config")) {
                Picker("Base path", selection: $bridge.basePath) {
                    ForEach(BasePath.allCases, id: \.self) { path in
                        Text(path.rawValue)
                    }
                }
            }

            Section(header: Text("Install Config")) {
                NavigationLink("Monitors") {
                    MonitorTypeView(monitors: bridge.configBinding(for: \.monitors))
                }
                Toggle(isOn: bridge.configBinding(for: \.enableQueueNameSearch)) {
                    Text("Queue name search")
                }
                Toggle(isOn: bridge.configBinding(for: \.addConsoleLogToReport)) {
                    Text("Add KSCrash console log to report")
                }
                Toggle(isOn: bridge.configBinding(for: \.printPreviousLogOnStartup)) {
                    Text("Print previous log on startup")
                }
                Toggle(isOn: bridge.configBinding(for: \.enableSwapCxaThrow)) {
                    Text("Swap __cxa_throw")
                }
            }

            Button("Skip install") {
                installed = true
            }
            .foregroundColor(.red)
        }
    }
}
