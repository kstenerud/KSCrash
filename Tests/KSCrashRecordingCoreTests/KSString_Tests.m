//
//  KSString_Tests.m
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

#import "KSString.h"

@interface KSString_Tests : XCTestCase
@end

@implementation KSString_Tests

- (void)testExtractHexValue
{
    const char *string = "Some string with 0x12345678 and such";
    uint64_t expected = 0x12345678;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, (int)strlen(string), &result);
    XCTAssertTrue(success, @"");
    XCTAssertEqual(result, expected, @"");
}

- (void)testExtractHexValue2
{
    const char *string = "Some string with 0x1 and such";
    uint64_t expected = 0x1;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, (int)strlen(string), &result);
    XCTAssertTrue(success, @"");
    XCTAssertEqual(result, expected, @"");
}

- (void)testExtractHexValue3
{
    const char *string = "Some string with 0x1234567890123456 and such";
    uint64_t expected = 0x1234567890123456;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, (int)strlen(string), &result);
    XCTAssertTrue(success, @"");
    XCTAssertEqual(result, expected, @"");
}

- (void)testExtractHexValueBeginning
{
    const char *string = "0x12345678 Some string";
    uint64_t expected = 0x12345678;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, (int)strlen(string), &result);
    XCTAssertTrue(success, @"");
    XCTAssertEqual(result, expected, @"");
}

- (void)testExtractHexValueEnd
{
    const char *string = "Some string with 0x12345678";
    uint64_t expected = 0x12345678;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, (int)strlen(string), &result);
    XCTAssertTrue(success, @"");
    XCTAssertEqual(result, expected, @"");
}

- (void)testExtractHexValueEmpty
{
    const char *string = "";
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, (int)strlen(string), &result);
    XCTAssertFalse(success, @"");
}

- (void)testExtractHexValueInvalid
{
    const char *string = "Some string with 0xoo and such";
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, (int)strlen(string), &result);
    XCTAssertFalse(success, @"");
}

- (void)testExtractHexValueInvalid2
{
    const char *string = "Some string with 0xoo";
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, (int)strlen(string), &result);
    XCTAssertFalse(success, @"");
}

- (void)testIsNullTerminatedUTF8String
{
    const char *string = "A string";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    XCTAssertTrue(success, @"");
}

- (void)testIsNullTerminatedUTF8String2
{
    const char *string = "テスト";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    XCTAssertTrue(success, @"");
}

- (void)testIsNullTerminatedUTF8String3
{
    const char *string = "aŸঠ𐅐 and so on";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    XCTAssertTrue(success, @"");
}

- (void)testIsNullTerminatedUTF8StringTooShort
{
    const char *string = "A string";
    bool success = ksstring_isNullTerminatedUTF8String(string, 10, 100);
    XCTAssertFalse(success, @"");
}

- (void)testIsNullTerminatedUTF8StringTooLong
{
    const char *string = "A string";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 5);
    XCTAssertFalse(success, @"");
}

- (void)testIsNullTerminatedUTF8StringInvalid
{
    const char *string = "A string\xf8";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    XCTAssertFalse(success, @"");
}

- (void)testIsNullTerminatedUTF8StringInvalid2
{
    const char *string = "A string\xc1zzz";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    XCTAssertFalse(success, @"");
}

- (void)testIsNullTerminatedUTF8StringInvalid3
{
    const char *string = "\xc0";
    bool success = ksstring_isNullTerminatedUTF8String(string, 1, 1);
    XCTAssertFalse(success, @"");
}

- (void)testIsNullTerminatedUTF8StringInvalid4
{
    const char *string = "blah \x80";
    bool success = ksstring_isNullTerminatedUTF8String(string, 1, 100);
    XCTAssertFalse(success, @"");
}

- (void)testIsNullTerminatedUTF8StringInvalid5
{
    const char *string = "\x01\x02\x03";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    XCTAssertFalse(success, @"");
}

- (void)testSafeStrcmpBothStringsAreNull
{
    const char *str1 = NULL;
    const char *str2 = NULL;
    int result = ksstring_safeStrcmp(str1, str2);
    XCTAssertEqual(result, 0, @"Expected 0 when both strings are NULL.");
}

- (void)testSafeStrcmpFirstStringIsNull
{
    const char *str1 = NULL;
    const char *str2 = "test";
    int result = ksstring_safeStrcmp(str1, str2);
    XCTAssertTrue(result < 0, @"Expected a negative value when first string is NULL.");
}

- (void)testSafeStrcmpSecondStringIsNull
{
    const char *str1 = "test";
    const char *str2 = NULL;
    int result = ksstring_safeStrcmp(str1, str2);
    XCTAssertTrue(result > 0, @"Expected a positive value when second string is NULL.");
}

- (void)testSafeStrcmpBothStringsAreEqual
{
    const char *str1 = "test";
    const char *str2 = "test";
    int result = ksstring_safeStrcmp(str1, str2);
    XCTAssertEqual(result, 0, @"Expected 0 when both strings are identical.");
}

- (void)testSafeStrcmpFirstStringLessThanSecond
{
    const char *str1 = "abc";
    const char *str2 = "def";
    int result = ksstring_safeStrcmp(str1, str2);
    XCTAssertTrue(result < 0, @"Expected a negative value when first string is less than second.");
}

- (void)testSafeStrcmpFirstStringGreaterThanSecond
{
    const char *str1 = "def";
    const char *str2 = "abc";
    int result = ksstring_safeStrcmp(str1, str2);
    XCTAssertTrue(result > 0, @"Expected a positive value when first string is greater than second.");
}

@end
