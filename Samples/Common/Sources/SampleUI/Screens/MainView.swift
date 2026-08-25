//
//  MainView.swift
//
//  Created by Nikolay Volosatov on 2024-07-21.
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
import SwiftUI

struct MainView: View {

    @ObservedObject var bridge: InstallBridge

    @State var alertMessage: String?
    @State var alertIsPresented: Bool = false

    var body: some View {
        List {
            Section {
                Text("KSCrash is installed successfully")
                    .foregroundStyle(Color.secondary)
            }

            NavigationLink("Crash", destination: CrashView())
            if let reportsDirectory = bridge.reportsDirectory {
                NavigationLink(
                    "Report",
                    destination: ReportingView(reports: PendingReports(directory: reportsDirectory)))
            } else {
                Text("Reporting is not available")
            }
            if bridge.useSamplePipeline {
                Button("Send reports via sample pipeline") {
                    bridge.sendViaSamplePipeline { error in
                        alertMessage = error?.localizedDescription
                        alertIsPresented = error != nil
                    }
                }
            }
        }
        .alert(isPresented: $alertIsPresented) {
            Alert(
                title: Text("Error"),
                message: Text(alertMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
