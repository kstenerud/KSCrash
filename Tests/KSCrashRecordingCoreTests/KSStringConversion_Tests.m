//
//  KSStringConversion_Tests.m
//
//  Created by Robert B on 2025-04-23.
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

#import "KSStringConversion.h"

@interface KSStringConversion_Tests : XCTestCase
@end

@implementation KSStringConversion_Tests

- (void)testConvertUint64ZeroToString
{
    uint64_t value = 0;
    char result[17];

    size_t size = kssc_uint64_to_hex(value, result, 0, false);

    NSString *resultString = [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    XCTAssertEqual(size, 1);
    XCTAssertTrue([resultString isEqualToString:@"0"]);
}

- (void)testConvertUint64ZeroWithMinDigitsToString
{
    uint64_t value = 0;
    char result[17];

    size_t size = kssc_uint64_to_hex(value, result, 10, false);

    NSString *resultString = [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    XCTAssertEqual(size, 10);
    XCTAssertTrue([resultString isEqualToString:@"0000000000"]);
}

- (void)testConvertUint64MaxToString
{
    uint64_t value = UINT64_MAX;
    char result[17];

    size_t size = kssc_uint64_to_hex(value, result, 0, false);

    NSString *resultString = [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    XCTAssertEqual(size, 16);
    XCTAssertTrue([resultString isEqualToString:@"ffffffffffffffff"]);
}

- (void)testConvertUint64MaxToUppercaseString
{
    uint64_t value = UINT64_MAX;
    char result[17];

    size_t size = kssc_uint64_to_hex(value, result, 0, true);

    NSString *resultString = [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    XCTAssertEqual(size, 16);
    XCTAssertTrue([resultString isEqualToString:@"FFFFFFFFFFFFFFFF"]);
}

- (void)testConvertUint64ToString
{
    uint64_t value = 0x2fe5c7f8;
    char result[17];

    size_t size = kssc_uint64_to_hex(value, result, 0, false);

    NSString *resultString = [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    XCTAssertEqual(size, 8);
    XCTAssertTrue([resultString isEqualToString:@"2fe5c7f8"]);
}

- (void)testConvertUint64ToUppercaseString
{
    uint64_t value = 0x2fe5c7f8;
    char result[17];

    size_t size = kssc_uint64_to_hex(value, result, 0, true);

    NSString *resultString = [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    XCTAssertEqual(size, 8);
    XCTAssertTrue([resultString isEqualToString:@"2FE5C7F8"]);
}

- (void)testConvertAllZerosUUIDToString
{
    uuid_t uuid = { 0 };
    char result[37];

    kssc_uuid_to_string(uuid, result);

    NSString *resultString = [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    XCTAssertTrue([resultString isEqualToString:@"00000000-0000-0000-0000-000000000000"]);
}

- (void)testConvertUUIDToString
{
    uuid_t uuid = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    char result[37];

    kssc_uuid_to_string(uuid, result);

    NSString *resultString = [NSString stringWithCString:result encoding:NSUTF8StringEncoding];
    XCTAssertTrue([resultString isEqualToString:@"00010203-0405-0607-0809-0A0B0C0D0E0F"]);
}

@end
