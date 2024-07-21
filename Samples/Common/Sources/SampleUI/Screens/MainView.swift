//
//  File.swift
//  
//
//  Created by Nikolay Volosatov on 21/07/2024.
//

import Foundation
import SwiftUI

struct MainView: View {

    @Binding var installSkipped: Bool

    var body: some View {
        List {
            Section {
                if installSkipped {
                    Button("Back to Install") {
                        installSkipped = false
                    }
                } else {
                    Text("KSCrash is installed successfully")
                        .foregroundStyle(Color.secondary)
                }
            }

            NavigationLink("Crash", destination: CrashView())
            NavigationLink("Report", destination: ReportingView())
        }
    }
}
