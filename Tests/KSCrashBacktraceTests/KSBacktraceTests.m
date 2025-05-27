//
//  KSBacktraceTests.m
//
//  Created by Alexander Cohen on 2025-05-27.
//
//  Copyright (c) 2025 Alexander Cohen. All rights reserved.
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

#import <XCTest/XCTest.h>

#import <dispatch/dispatch.h>

#import "KSBacktrace.h"

@interface KSBacktrace_tests : XCTestCase

@end

@implementation KSBacktrace_tests

- (void)testBacktrace
{
    XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Backtrace"];
    
    pthread_t thread = pthread_self();
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        
        const size_t frameCount = 512;
        uintptr_t addresses[frameCount] = {0};
        size_t count = ks_backtrace(thread, addresses, frameCount);
        
        [expectation fulfill];
    });
    
    [self waitForExpectations:@[expectation] timeout:5];
}

@end
