//
//  MonitorTypeView.swift
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

struct MonitorTypeView: View {

    @Binding var monitors: Monitors

    private static let allMonitors: [(monitor: Monitors, name: String, description: String)] = [
        (.machExceptions, "Mach Exceptions", "Low-level system exceptions"),
        (.signals, "Signals", "UNIX-style signals indicating abnormal program termination"),
        (.cppExceptions, "C++ Exceptions", "Unhandled exceptions in C++ code"),
        (.nsExceptions, "NSExceptions", "Unhandled Objective-C exceptions"),
        (.terminations, "Terminations", "OS terminations from resource exhaustion or maintenance"),
        (.hangs, "Hangs", "Main-thread hangs and watchdog timeout terminations"),
        (.zombies, "Zombies", "Attempts to access deallocated objects"),
    ]

    private func monitorBinding(_ monitor: Monitors) -> Binding<Bool> {
        return .init(
            get: {
                monitors.contains(monitor)
            },
            set: { flag in
                if flag {
                    monitors.insert(monitor)
                } else {
                    monitors.remove(monitor)
                }
            })
    }

    var body: some View {
        List {
            Section(header: Text("Monitors")) {
                ForEach(Self.allMonitors, id: \.monitor.rawValue) { (monitor, name, description) in
                    Toggle(isOn: monitorBinding(monitor)) {
                        VStack(alignment: .leading) {
                            Text(name)
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            Section(header: Text("Sets")) {
                Button("Default") { monitors = .default }
                Button("All") { monitors = .all }
                Button("None") { monitors = [] }
            }
        }
    }
}
