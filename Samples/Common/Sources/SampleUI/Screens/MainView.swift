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
                if bridge.reportsOnlySetup {
                    Text(
                        "It's only reporting that was set up. Crashes won't be caught. You can go back to the install screen."
                    )
                    .foregroundStyle(Color.secondary)
                    Button("Back to Install") {
                        bridge.reportsOnlySetup = false
                    }
                } else {
                    Text("KSCrash is installed successfully")
                        .foregroundStyle(Color.secondary)
                }
            }

            NavigationLink("Crash", destination: CrashView())
            if let store = bridge.reportStore {
                NavigationLink("Report", destination: ReportingView(store: store))
            } else {
                Text("Reporting is not available")
            }
            if let installation = bridge.installation {
                Button("Send reports via installation") {
                    installation.sendAllReports { _, error in
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
