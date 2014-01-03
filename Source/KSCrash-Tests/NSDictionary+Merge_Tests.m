//
//  NSDictionary+Merge_Tests.m
//
//  Created by Karl Stenerud on 2012-10-01.
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


#import <XCTest/XCTest.h>

#import "NSDictionary+Merge.h"


@interface NSDictionary_Merge_Tests : XCTestCase @end


@implementation NSDictionary_Merge_Tests

- (void) testBasicMerge
{
    id src = [NSDictionary dictionaryWithObjectsAndKeys:
              @"one", @"a",
              nil];
    id dst = [NSDictionary dictionaryWithObjectsAndKeys:
              @"two", @"b",
              nil];
    NSDictionary* expected = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"one", @"a",
                              @"two", @"b",
                              nil];
    NSDictionary* actual = [src mergedInto:dst];
    XCTAssertEqualObjects(expected, actual, @"");
}

- (void) testOverwrite
{
    id src = [NSDictionary dictionaryWithObjectsAndKeys:
              @"one", @"a",
              nil];
    id dst = [NSDictionary dictionaryWithObjectsAndKeys:
              @"two", @"a",
              nil];
    NSDictionary* expected = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"one", @"a",
                              nil];
    NSDictionary* actual = [src mergedInto:dst];
    XCTAssertEqualObjects(expected, actual, @"");
}

- (void) testSrcEmpty
{
    id src = [NSDictionary dictionary];
    id dst = [NSDictionary dictionaryWithObjectsAndKeys:
              @"two", @"b",
              nil];
    NSDictionary* expected = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"two", @"b",
                              nil];
    NSDictionary* actual = [src mergedInto:dst];
    XCTAssertEqualObjects(expected, actual, @"");
}

- (void) testDstEmpty
{
    id src = [NSDictionary dictionaryWithObjectsAndKeys:
              @"one", @"a",
              nil];
    id dst = [NSDictionary dictionary];
    NSDictionary* expected = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"one", @"a",
                              nil];
    NSDictionary* actual = [src mergedInto:dst];
    XCTAssertEqualObjects(expected, actual, @"");
}

- (void) testDstNil
{
    id src = [NSDictionary dictionaryWithObjectsAndKeys:
              @"one", @"a",
              nil];
    id dst = nil;
    NSDictionary* expected = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"one", @"a",
                              nil];
    NSDictionary* actual = [src mergedInto:dst];
    XCTAssertEqualObjects(expected, actual, @"");
}

- (void) testSrcDict
{
    id src = [NSDictionary dictionaryWithObjectsAndKeys:
              [NSDictionary dictionaryWithObjectsAndKeys:@"blah", @"x", nil], @"a",
              nil];
    id dst = [NSDictionary dictionaryWithObjectsAndKeys:
              @"two", @"a",
              nil];
    NSDictionary* expected = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSDictionary dictionaryWithObjectsAndKeys:@"blah", @"x", nil], @"a",
                              nil];
    NSDictionary* actual = [src mergedInto:dst];
    XCTAssertEqualObjects(expected, actual, @"");
}

- (void) testDstDict
{
    id src = [NSDictionary dictionaryWithObjectsAndKeys:
              @"one", @"a",
              nil];
    id dst = [NSDictionary dictionaryWithObjectsAndKeys:
              [NSDictionary dictionaryWithObjectsAndKeys:@"blah", @"x", nil], @"a",
              nil];
    NSDictionary* expected = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"one", @"a",
                              nil];
    NSDictionary* actual = [src mergedInto:dst];
    XCTAssertEqualObjects(expected, actual, @"");
}

- (void) testSrcDstDict
{
    id src = [NSDictionary dictionaryWithObjectsAndKeys:
              [NSDictionary dictionaryWithObjectsAndKeys:@"blah", @"x", nil], @"a",
              nil];
    id dst = [NSDictionary dictionaryWithObjectsAndKeys:
              [NSDictionary dictionaryWithObjectsAndKeys:@"something", @"y", nil], @"a",
              nil];
    NSDictionary* expected = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSDictionary dictionaryWithObjectsAndKeys:
                               @"blah", @"x",
                               @"something", @"y",
                               nil], @"a",
                              nil];
    NSDictionary* actual = [src mergedInto:dst];
    XCTAssertEqualObjects(expected, actual, @"");
}

@end
