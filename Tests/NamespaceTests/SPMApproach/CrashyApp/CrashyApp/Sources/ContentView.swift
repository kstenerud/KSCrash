import SwiftUI

public struct ContentView: View {
    public init() {}

    func crash() {
        fatalError("Crash!")
    }

    public var body: some View {
        Button("Crash Now!") {
            crash()
        }.padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
