
//
//  KSCrashTestDylib.swift
//
//  Created by Gleb Linnik on 2025-04-11.
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

@objc public class KSCrashTestDylib: NSObject {
    @objc public static let shared = KSCrashTestDylib()
    
    private override init() {
        super.init()
        print("KSCrashTestDylib initialized")
    }
    
    @objc public func identifiableFunction() -> String {
        return "This function is from KSCrashTestDylib"
    }
    
    deinit {
        print("KSCrashTestDylib destroyed")
    }
}

// Ensure we have some global symbols that would appear in a crash report
@_cdecl("KSCrashTestDylibFunction")
public func KSCrashTestDylibFunction() -> Int32 {
    print("KSCrashTestDylibFunction called")
    return 42
}
