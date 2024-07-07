//
//  InstallBridge.swift
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
import Combine
import SwiftUI
import KSCrashRecording

public enum BasePath: String, CaseIterable {
    case `default`
    case cache
    case applicationSupport
}

public class InstallBridge: ObservableObject {
    public typealias MonitorType = KSCrashRecording.MonitorType

    private static func setBasePath(_ value: BasePath) {
        let basePath = value.basePaths.first.flatMap { $0 + "/KSCrash" }
        print("Setting KSCrash base path to: \(basePath ?? "<default>")")
        KSCrash.setBasePath(basePath)
    }

    public static let allRawMonitorTypes: [(String, MonitorType)] = [
        ("machException", .machException),
        ("signal", .signal),
        ("cppException", .cppException),
        ("nsException", .nsException),
        ("mainThreadDeadlock", .mainThreadDeadlock),
        ("userReported", .userReported),
        ("system", .system),
        ("applicationState", .applicationState),
        ("zombie", .zombie),
        ("memoryTermination", .memoryTermination),
    ]

    public static let allCompositeMonitorTypes: [(String, MonitorType)] = [
        ("all", .all),
        ("fatal", .fatal),
        ("experimental", .experimental),
        ("debuggerUnsafe", .debuggerUnsafe),
        ("asyncSafe", .asyncSafe),
        ("optional", .optional),
        ("asyncUnsafe", .asyncUnsafe),
        ("debuggerSafe", .debuggerSafe),
        ("productionSafe", .productionSafe),
        ("productionSafeMinimal", .productionSafeMinimal),
        ("required", .required),
        ("manual", .manual),
    ]

    private var config: KSCrashConfiguration
    private var disposables = Set<AnyCancellable>()

    @Published public var basePath: BasePath = .default

    public func configBinding<T>(for keyPath: WritableKeyPath<KSCrashConfiguration, T>) -> Binding<T> {
        .init { [config] in
            config[keyPath: keyPath]
        } set: { [weak self] val in
            self?.objectWillChange.send()
            self?.config[keyPath: keyPath] = val
        }

    }

    public init() {
        config = .init()

        $basePath
            .removeDuplicates()
            .sink(receiveValue: Self.setBasePath(_:))
            .store(in: &disposables)
    }

    public func install() {
        KSCrash.shared().install(with: config)
    }
}

extension BasePath {
    var basePaths: [String] {
        switch self {
        case .default:
            return []
        case .cache:
            return NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        case .applicationSupport:
            return NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        }
    }
}
