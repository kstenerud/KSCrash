//
//  KSBacktraceTests.m
//
//  Created by Alexander Cohen on 2025-05-27.
//
// Copyright (c) 2012 Karl Stenerud. All rights reserved.
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
import Darwin
import KSCrashRecordingCore

#if !os(watchOS)  // there are no backtraces on watchOS
class KSBacktrace_Tests:XCTestCase{
    
    func testBacktrace(){
        
        let expectation = XCTestExpectation()
        let thread = pthread_self()
        
        DispatchQueue.global(qos:.default).async{
            
            let entries = 512
            var addresses: [UInt] = Array(repeating: 0, count:entries)
            let count = ks_captureBacktrace(thread, &addresses, Int32(entries))
            
            XCTAssert(count > 0)
            XCTAssert(count <= entries);
            for index in 0..<count {
                XCTAssert(addresses[Int(index)] != 0)
            }
            
            expectation.fulfill()
        }
        
        self.wait(for: [expectation], timeout: 5)
    }
}
#endif
