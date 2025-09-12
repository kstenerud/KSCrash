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
