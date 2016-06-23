//
//  KSSafeCollections_Tests.m
//
//  Created by Karl Stenerud on 2013-01-26.
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
#import "KSSafeCollections.h"


@interface KSSafeCollections_Tests : XCTestCase @end


@implementation KSSafeCollections_Tests

- (void) testAddObjectIfNotNil
{
    NSMutableArray* array = [NSMutableArray array];
    id object = @"blah";
    [array ksc_addObjectIfNotNil:object];
    XCTAssertTrue([array count] == 1, @"");
}

- (void) testAddObjectIfNotNil2
{
    NSMutableArray* array = [NSMutableArray array];
    id object = nil;
    [array ksc_addObjectIfNotNil:object];
    XCTAssertTrue([array count] == 0, @"");
}

- (void) testSafeAddObject
{
    NSMutableArray* array = [NSMutableArray array];
    id object = @"blah";
    [array ksc_safeAddObject:object];
    XCTAssertTrue([array count] == 1, @"");
}

- (void) testSafeAddObject2
{
    NSMutableArray* array = [NSMutableArray array];
    id object = nil;
    [array ksc_safeAddObject:object];
    XCTAssertTrue([array count] == 1, @"");
}

- (void) testInsertObjectIfNotNil
{
    NSMutableArray* array = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
    id object = @"blah";
    [array ksc_insertObjectIfNotNil:object atIndex:1];
    XCTAssertTrue([array count] == 3, @"");
}

- (void) testInsertObjectIfNotNil2
{
    NSMutableArray* array = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
    id object = nil;
    [array ksc_insertObjectIfNotNil:object atIndex:1];
    XCTAssertTrue([array count] == 2, @"");
}

- (void) testSafeInsertObject
{
    NSMutableArray* array = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
    id object = @"blah";
    [array ksc_safeInsertObject:object atIndex:1];
    XCTAssertTrue([array count] == 3, @"");
}

- (void) testSafeInsertObject2
{
    NSMutableArray* array = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
    id object = nil;
    [array ksc_safeInsertObject:object atIndex:1];
    XCTAssertTrue([array count] == 3, @"");
}

- (void) testSetObjectIfNotNil
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = @"blah";
    [dict ksc_setObjectIfNotNil:object forKey:key];
    id result = [dict objectForKey:key];
    XCTAssertEqual(result, object, @"");
}

- (void) testSetObjectIfNotNil2
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = nil;
    [dict ksc_setObjectIfNotNil:object forKey:key];
    id result = [dict objectForKey:key];
    XCTAssertNil(result, @"");
}

- (void) testSafeSetObject
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = @"blah";
    [dict ksc_safeSetObject:object forKey:key];
    id result = [dict objectForKey:key];
    XCTAssertEqual(result, object, @"");
}

- (void) testSafeSetObject2
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = nil;
    [dict ksc_safeSetObject:object forKey:key];
    id result = [dict objectForKey:key];
    XCTAssertNotNil(result, @"");
}

- (void) testSetValueIfNotNil
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = @"blah";
    [dict ksc_setValueIfNotNil:object forKey:key];
    id result = [dict valueForKey:key];
    XCTAssertEqual(result, object, @"");
}

- (void) testSetValueIfNotNil2
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = nil;
    [dict ksc_setValueIfNotNil:object forKey:key];
    id result = [dict valueForKey:key];
    XCTAssertNil(result, @"");
}

- (void) testSafeSetValue
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = @"blah";
    [dict ksc_safeSetValue:object forKey:key];
    id result = [dict valueForKey:key];
    XCTAssertEqual(result, object, @"");
}

- (void) testSafeSetValue2
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    id key = @"key";
    id object = nil;
    [dict ksc_safeSetValue:object forKey:key];
    id result = [dict valueForKey:key];
    XCTAssertNotNil(result, @"");
}

@end
