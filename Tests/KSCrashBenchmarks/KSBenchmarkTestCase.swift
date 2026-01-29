//
//  KSBenchmarkTestCase.swift
//
//  Created by Alexander Cohen on 2026-01-29.
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

import XCTest

/// Base class for all KSCrash benchmark tests.
///
/// On physical devices (non-simulator), reduces the default XCTest
/// measurement iteration count from 10 to 5. With 9 benchmark classes
/// running across 3 BrowserStack shards, the default 10 iterations adds
/// significant wall-clock time and CI cost. 5 iterations still provides
/// statistically meaningful results while keeping total execution time
/// reasonable.
///
/// On simulators, the default 10 iterations are preserved since
/// simulator runs are local and faster to iterate on.
class KSBenchmarkTestCase: XCTestCase {
    override class var defaultMeasureOptions: XCTMeasureOptions {
        let options = super.defaultMeasureOptions
        #if !targetEnvironment(simulator)
            options.iterationCount = 5
        #endif
        return options
    }
}
