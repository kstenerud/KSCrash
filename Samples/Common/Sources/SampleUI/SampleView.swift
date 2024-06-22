import SwiftUI
import LibraryBridge
import CrashTriggers

public struct SampleView: View {
    public init() { }
    
    public var body: some View {
        VStack {
            Text("Hello, World!")
            Button("Crash") {
                CrashTriggers.nsexception()
            }
            Button("Log Crashes") {
                ReportingSample.logToConsole()
            }
        }
        .onAppear {
            RecordingSample.simple()
        }
    }
}
