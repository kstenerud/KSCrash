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
import KSCrash
import LibraryBridge
import SwiftUI

struct InstallView: View {
    @ObservedObject var bridge: InstallBridge

    @State private var showingInstallAlert = false

    private var memoryIntrospectionBinding: Binding<Bool> {
        let binding = bridge.configBinding(for: \.memoryIntrospection)
        return .init {
            binding.wrappedValue != .disabled
        } set: { enabled in
            binding.wrappedValue = enabled ? .enabled(excludingClasses: []) : .disabled
        }
    }

    var body: some View {
        List {
            Button("Install") {
                bridge.install()
            }

            Section(header: Text("Static Config")) {
                Picker("Container", selection: $bridge.container) {
                    ForEach(ContainerChoice.allCases, id: \.self) { choice in
                        Text(choice.rawValue)
                    }
                }
            }

            Section(header: Text("Install Config")) {
                NavigationLink("Monitors") {
                    MonitorTypeView(monitors: bridge.configBinding(for: \.monitors))
                        .navigationTitle("Monitors")
                }
                Toggle(isOn: bridge.configBinding(for: \.searchesQueueNames)) {
                    Text("Queue name search")
                }
                Toggle(isOn: memoryIntrospectionBinding) {
                    Text("Memory introspection")
                }
                Toggle(isOn: bridge.configBinding(for: \.includesConsoleLog)) {
                    Text("Add KSCrash console log to report")
                }
                Toggle(isOn: bridge.configBinding(for: \.printsPreviousLog)) {
                    Text("Print previous log on startup")
                }
                Toggle(isOn: bridge.configBinding(for: \.swapsCxaThrow)) {
                    Text("Swap __cxa_throw")
                }
                Toggle(isOn: bridge.configBinding(for: \.reportsResolvedHangs)) {
                    Text("Report resolved hangs")
                }
            }

            Section(header: Text("Sample send pipeline")) {
                Button("Install + use sample send pipeline") {
                    bridge.useSampleSendPipeline()
                }
            }
        }
        .alert(isPresented: $showingInstallAlert) {
            Alert(
                title: Text("Installation Failed"),
                message: Text(bridge.error?.errorDescription ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
        .onReceive(bridge.$error) { if $0 != nil { showingInstallAlert = true } }
    }
}
