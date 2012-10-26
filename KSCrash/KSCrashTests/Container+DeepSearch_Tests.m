//
//  Container+DeepSearch_Tests.m
//
//  Created by Karl Stenerud on 2012-08-26.
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


#import <SenTestingKit/SenTestingKit.h>
#import "Container+DeepSearch.h"


@interface Container_DeepSearch_Tests : SenTestCase @end

@implementation Container_DeepSearch_Tests

- (void) testDeepSearchDictionary
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil], @"key2",
                     nil], @"key1",
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:@"key1", @"key2", @"key3", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchDictionaryPath
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil], @"key2",
                     nil], @"key1",
                    nil];

    id actual = [container objectForKeyPath:@"key1/key2/key3"];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchDictionary2
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"3",
                      nil], @"2",
                     nil], @"1",
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:@"1", @"2", @"3", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchDictionary2Path
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"3",
                      nil], @"2",
                     nil], @"1",
                    nil];

    id actual = [container objectForKeyPath:@"1/2/3"];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchArray
{
    id expected = @"Object";
    id container = [NSArray arrayWithObjects:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSArray arrayWithObjects:
                      @"blah2",
                      expected,
                      nil],
                     nil],
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:
                        [NSNumber numberWithInt:0],
                        [NSNumber numberWithInt:1],
                        [NSNumber numberWithInt:1],
                        nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchArrayString
{
    id expected = @"Object";
    id container = [NSArray arrayWithObjects:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSArray arrayWithObjects:
                      @"blah2",
                      expected,
                      nil],
                     nil],
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:@"0", @"1", @"1", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchArrayString2
{
    id expected = @"Object";
    id container = [NSArray arrayWithObjects:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSArray arrayWithObjects:
                      @"blah2",
                      expected,
                      nil],
                     nil],
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:@"0", @"1", @"key", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertNil(actual, @"");
}

- (void) testDeepSearchArrayPath
{
    id expected = @"Object";
    id container = [NSArray arrayWithObjects:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSArray arrayWithObjects:
                      @"blah2",
                      expected,
                      nil],
                     nil],
                    nil];

    id actual = [container objectForKeyPath:@"0/1/1"];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchMixed
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil],
                     nil], @"key1",
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:
                        @"key1",
                        [NSNumber numberWithInt:1],
                        @"key3", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchMixedPath
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil],
                     nil], @"key1",
                    nil];

    id actual = [container objectForKeyPath:@"key1/1/key3"];
    STAssertEqualObjects(expected, actual, @"");
}

- (void) testDeepSearchNotFound
{
    id container = [NSDictionary dictionary];
    NSArray* deepKey = [NSArray arrayWithObjects:@"key1", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertNil(actual, @"");
}

- (void) testDeepSearchNotFoundArray
{
    id container = [NSArray array];
    NSArray* deepKey = [NSArray arrayWithObjects:@"key1", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertNil(actual, @"");
}

- (void) testDeepSearchNonContainerObject
{
    id expected = @"Object";
    id container = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSArray arrayWithObjects:
                     @"blah",
                     [NSDictionary dictionaryWithObjectsAndKeys:
                      expected, @"key3",
                      nil],
                     nil], @"key1",
                    nil];

    NSArray* deepKey = [NSArray arrayWithObjects:
                        @"key1",
                        [NSNumber numberWithInt:1],
                        @"key3",
                        @"key4", nil];
    id actual = [container objectForDeepKey:deepKey];
    STAssertNil(actual, @"");
}


@end
