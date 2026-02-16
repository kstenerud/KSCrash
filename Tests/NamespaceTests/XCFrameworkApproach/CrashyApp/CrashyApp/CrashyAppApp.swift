//
//  CrashyAppApp.swift
//  CrashyApp
//
//  Created by Karl Stenerud on 03.09.25.
//

import CrashLibA
import CrashLibB
import SwiftUI

@main
struct CrashyAppApp: App {
    init() {
        CrashLibA.start()
        CrashLibB.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
