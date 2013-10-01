//
//  NSMutableData_AppendUTF8_Tests.m
//
//  Created by Karl Stenerud on 2012-02-26.
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

#import "NSMutableData+AppendUTF8.h"


@interface NSMutableData_AppendUTF8_Tests : XCTestCase @end


@implementation NSMutableData_AppendUTF8_Tests

- (void) testAppendUTF8String
{
    NSString* expected = @"testテスト";
    NSMutableData* data = [NSMutableData data];
    [data appendUTF8String:expected];
    NSString* actual = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    XCTAssertEqualObjects(actual, expected, @"");
}

- (void) testAppendUTF8Format
{
    NSString* expected = @"Testing 1 2.0 3";
    NSMutableData* data = [NSMutableData data];
    [data appendUTF8Format:@"Testing %d %.1f %@", 1, 2.0, @"3"];
    NSString* actual = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    XCTAssertEqualObjects(actual, expected, @"");
}

@end
