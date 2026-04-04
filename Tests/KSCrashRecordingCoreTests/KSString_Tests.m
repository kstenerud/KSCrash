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

#import "KSID.h"
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

#pragma mark - uint64ToHex

- (void)testUint64ToHexZero
{
    char buf[17];
    size_t len = ksstring_uint64ToHex(0, buf, sizeof(buf), 1, false);
    XCTAssertEqual(len, 1u);
    XCTAssertEqualObjects(@(buf), @"0");
}

- (void)testUint64ToHexZeroPadded
{
    char buf[17];
    size_t len = ksstring_uint64ToHex(0, buf, sizeof(buf), 8, false);
    XCTAssertEqual(len, 8u);
    XCTAssertEqualObjects(@(buf), @"00000000");
}

- (void)testUint64ToHexMax
{
    char buf[17];
    size_t len = ksstring_uint64ToHex(UINT64_MAX, buf, sizeof(buf), 1, false);
    XCTAssertEqual(len, 16u);
    XCTAssertEqualObjects(@(buf), @"ffffffffffffffff");
}

- (void)testUint64ToHexMaxUppercase
{
    char buf[17];
    size_t len = ksstring_uint64ToHex(UINT64_MAX, buf, sizeof(buf), 1, true);
    XCTAssertEqual(len, 16u);
    XCTAssertEqualObjects(@(buf), @"FFFFFFFFFFFFFFFF");
}

- (void)testUint64ToHexValue
{
    char buf[17];
    size_t len = ksstring_uint64ToHex(0x2fe5c7f8, buf, sizeof(buf), 1, false);
    XCTAssertEqual(len, 8u);
    XCTAssertEqualObjects(@(buf), @"2fe5c7f8");
}

- (void)testUint64ToHexMinDigitsClamped
{
    char buf[17];
    size_t len = ksstring_uint64ToHex(0xAB, buf, sizeof(buf), 0, true);
    XCTAssertEqual(len, 2u);
    XCTAssertEqualObjects(@(buf), @"AB");

    len = ksstring_uint64ToHex(0xAB, buf, sizeof(buf), 20, true);
    XCTAssertEqual(len, 16u);
    XCTAssertEqualObjects(@(buf), @"00000000000000AB");
}

- (void)testUint64ToHexSingleBytePadded
{
    char buf[17];
    size_t len = ksstring_uint64ToHex(0x0A, buf, sizeof(buf), 2, true);
    XCTAssertEqual(len, 2u);
    XCTAssertEqualObjects(@(buf), @"0A");
}

- (void)testUint64ToHexTruncated
{
    char buf[5];
    size_t len = ksstring_uint64ToHex(0x12345678, buf, sizeof(buf), 1, false);
    XCTAssertEqual(len, 4u);
    XCTAssertEqualObjects(@(buf), @"1234");
}

- (void)testUint64ToHexBufSizeOne
{
    char buf[1];
    size_t len = ksstring_uint64ToHex(0xFF, buf, sizeof(buf), 1, false);
    XCTAssertEqual(len, 0u);
    XCTAssertEqual(buf[0], '\0');
}

- (void)testUint64ToHexBufSizeTwo
{
    char buf[2];
    size_t len = ksstring_uint64ToHex(0xFF, buf, sizeof(buf), 1, false);
    XCTAssertEqual(len, 1u);
    XCTAssertEqualObjects(@(buf), @"f");
}

- (void)testUint64ToHexExactFit
{
    char buf[9];
    size_t len = ksstring_uint64ToHex(0x12345678, buf, sizeof(buf), 1, false);
    XCTAssertEqual(len, 8u);
    XCTAssertEqualObjects(@(buf), @"12345678");
}

- (void)testUint64ToHexZeroBufSize
{
    char buf[17] = "untouched";
    size_t len = ksstring_uint64ToHex(0xFF, buf, 0, 1, false);
    XCTAssertEqual(len, 0u);
    XCTAssertEqualObjects(@(buf), @"untouched");
}

- (void)testUint64ToHexTruncatedWithPadding
{
    char buf[4];
    size_t len = ksstring_uint64ToHex(0xAB, buf, sizeof(buf), 16, true);
    XCTAssertEqual(len, 3u);
    XCTAssertEqualObjects(@(buf), @"000");
}

#pragma mark - intToDecimal

- (void)testIntToDecimalZero
{
    char buf[12];
    size_t len = ksstring_intToDecimal(0, buf, sizeof(buf));
    XCTAssertEqual(len, 1u);
    XCTAssertEqualObjects(@(buf), @"0");
}

- (void)testIntToDecimalPositive
{
    char buf[12];
    size_t len = ksstring_intToDecimal(31, buf, sizeof(buf));
    XCTAssertEqual(len, 2u);
    XCTAssertEqualObjects(@(buf), @"31");
}

- (void)testIntToDecimalNegative
{
    char buf[12];
    size_t len = ksstring_intToDecimal(-42, buf, sizeof(buf));
    XCTAssertEqual(len, 3u);
    XCTAssertEqualObjects(@(buf), @"-42");
}

- (void)testIntToDecimalIntMin
{
    char buf[12];
    size_t len = ksstring_intToDecimal(INT_MIN, buf, sizeof(buf));
    NSString *expected = [NSString stringWithFormat:@"%d", INT_MIN];
    XCTAssertEqual(len, expected.length);
    XCTAssertEqualObjects(@(buf), expected);
}

- (void)testIntToDecimalIntMax
{
    char buf[12];
    size_t len = ksstring_intToDecimal(INT_MAX, buf, sizeof(buf));
    NSString *expected = [NSString stringWithFormat:@"%d", INT_MAX];
    XCTAssertEqual(len, expected.length);
    XCTAssertEqualObjects(@(buf), expected);
}

- (void)testIntToDecimalSingleDigit
{
    char buf[12];
    size_t len = ksstring_intToDecimal(7, buf, sizeof(buf));
    XCTAssertEqual(len, 1u);
    XCTAssertEqualObjects(@(buf), @"7");
}

- (void)testIntToDecimalTruncated
{
    char buf[3];
    size_t len = ksstring_intToDecimal(12345, buf, sizeof(buf));
    XCTAssertEqual(len, 2u);
    XCTAssertEqualObjects(@(buf), @"12");
}

- (void)testIntToDecimalNegativeTruncated
{
    char buf[3];
    size_t len = ksstring_intToDecimal(-42, buf, sizeof(buf));
    XCTAssertEqual(len, 2u);
    XCTAssertEqualObjects(@(buf), @"-4");
}

- (void)testIntToDecimalBufSizeOne
{
    char buf[1];
    size_t len = ksstring_intToDecimal(42, buf, sizeof(buf));
    XCTAssertEqual(len, 0u);
    XCTAssertEqual(buf[0], '\0');
}

- (void)testIntToDecimalBufSizeTwo
{
    char buf[2];
    size_t len = ksstring_intToDecimal(42, buf, sizeof(buf));
    XCTAssertEqual(len, 1u);
    XCTAssertEqualObjects(@(buf), @"4");
}

- (void)testIntToDecimalExactFit
{
    char buf[3];
    size_t len = ksstring_intToDecimal(42, buf, sizeof(buf));
    XCTAssertEqual(len, 2u);
    XCTAssertEqualObjects(@(buf), @"42");
}

- (void)testIntToDecimalZeroBufSizeOne
{
    char buf[2];
    size_t len = ksstring_intToDecimal(0, buf, 1);
    XCTAssertEqual(len, 0u);
    XCTAssertEqual(buf[0], '\0');
}

- (void)testIntToDecimalZeroBufSizeTwo
{
    char buf[2];
    size_t len = ksstring_intToDecimal(0, buf, sizeof(buf));
    XCTAssertEqual(len, 1u);
    XCTAssertEqualObjects(@(buf), @"0");
}

- (void)testIntToDecimalIntMaxBufSizeOne
{
    char buf[1];
    size_t len = ksstring_intToDecimal(INT_MAX, buf, sizeof(buf));
    XCTAssertEqual(len, 0u);
    XCTAssertEqual(buf[0], '\0');
}

- (void)testIntToDecimalIntMaxBufSizeTwo
{
    char buf[2];
    size_t len = ksstring_intToDecimal(INT_MAX, buf, sizeof(buf));
    XCTAssertEqual(len, 1u);
    XCTAssertEqualObjects(@(buf), @"2");
}

- (void)testIntToDecimalIntMinBufSizeOne
{
    char buf[1];
    size_t len = ksstring_intToDecimal(INT_MIN, buf, sizeof(buf));
    XCTAssertEqual(len, 0u);
    XCTAssertEqual(buf[0], '\0');
}

- (void)testIntToDecimalIntMinBufSizeTwo
{
    char buf[2];
    size_t len = ksstring_intToDecimal(INT_MIN, buf, sizeof(buf));
    XCTAssertEqual(len, 1u);
    XCTAssertEqualObjects(@(buf), @"-");
}

- (void)testIntToDecimalZeroBufSize
{
    char buf[12] = "untouched";
    size_t len = ksstring_intToDecimal(42, buf, 0);
    XCTAssertEqual(len, 0u);
    XCTAssertEqualObjects(@(buf), @"untouched");
}

#pragma mark - ksid_generate

- (void)testKSIDGenerateFormat
{
    char buf[37];
    ksid_generate(buf);
    NSString *uuid = [NSString stringWithUTF8String:buf];
    XCTAssertEqual(uuid.length, 36u);
    XCTAssertEqual([uuid characterAtIndex:8], '-');
    XCTAssertEqual([uuid characterAtIndex:13], '-');
    XCTAssertEqual([uuid characterAtIndex:18], '-');
    XCTAssertEqual([uuid characterAtIndex:23], '-');

    NSCharacterSet *valid = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF-"];
    NSCharacterSet *chars = [NSCharacterSet characterSetWithCharactersInString:uuid];
    XCTAssertTrue([valid isSupersetOfSet:chars], @"UUID should only contain uppercase hex and hyphens: %@", uuid);

    // Must round-trip through uuid_parse
    uuid_t parsed;
    XCTAssertEqual(uuid_parse(buf, parsed), 0, @"Generated string should be a valid UUID");

    // UUID v4: version nibble must be '4', variant nibble must be 8/9/A/B
    XCTAssertEqual([uuid characterAtIndex:14], '4', @"Version nibble should be 4");
    unichar variant = [uuid characterAtIndex:19];
    XCTAssertTrue(variant == '8' || variant == '9' || variant == 'A' || variant == 'B',
                  @"Variant nibble should be 8/9/A/B, got %C", variant);
}

- (void)testKSIDGenerateUniqueness
{
    char buf1[37], buf2[37];
    ksid_generate(buf1);
    ksid_generate(buf2);
    XCTAssertFalse(strcmp(buf1, buf2) == 0, @"Two generated IDs should not be equal");
}

- (void)testKSIDGenerateValidUUID100Times
{
    for (int i = 0; i < 100; i++) {
        char buf[37];
        ksid_generate(buf);
        uuid_t parsed;
        XCTAssertEqual(uuid_parse(buf, parsed), 0, @"Iteration %d: uuid_parse failed for %s", i, buf);
    }
}

@end
