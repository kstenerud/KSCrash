//
//  ContentView.swift
//  CrashyApp
//
//  Created by Karl Stenerud on 03.09.25.
//

import SwiftUI

struct ContentView: View {
    func crash() {
        let arr = [] as [Int]
        print("\(arr[100])")
    }

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Button("Crash") {
                crash()
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
