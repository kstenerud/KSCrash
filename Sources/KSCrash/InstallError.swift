//
//  InstallError.swift
//
//  Created by Alexander Cohen on 2026-08-22.
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
import KSCrashRecording

/// Why `KSCrash.install(_:)` failed.
public enum InstallError: Error, Equatable, Sendable {
    case alreadyInstalled
    case pathTooLong
    case couldNotCreatePath
    case couldNotInitializeStore
    case couldNotInitializeMemory
    case couldNotInitializeCrashState
    case couldNotSetLogFilename
    /// The app group container could not be resolved; the string is the group identifier.
    case containerUnavailable(String)
    /// The configuration cannot be installed as given; the string says why.
    case invalidConfiguration(String)
    /// The live metadata store could not be created; the string says why.
    case metadataStoreUnavailable(String)
    /// A C install error with no Swift case; the value is the raw code.
    case unknown(Int)

    init(code: KSCrashInstallError.Code) {
        switch code {
        case .alreadyInstalled: self = .alreadyInstalled
        case .pathTooLong: self = .pathTooLong
        case .couldNotCreatePath: self = .couldNotCreatePath
        case .couldNotInitializeStore: self = .couldNotInitializeStore
        case .couldNotInitializeMemory: self = .couldNotInitializeMemory
        case .couldNotInitializeCrashState: self = .couldNotInitializeCrashState
        case .couldNotSetLogFilename: self = .couldNotSetLogFilename
        default: self = .unknown(code.rawValue)
        }
    }
}
