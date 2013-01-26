//
//  KSString_Tests.m
//  KSCrash
//
//  Created by Karl Stenerud on 1/26/13.
//  Copyright (c) 2013 Karl Stenerud. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import "KSString.h"

@interface KSString_Tests : SenTestCase @end

@implementation KSString_Tests

- (void) testExtractHexValue
{
    const char* string = "Some string with 0x12345678 and such";
    uint64_t expected = 0x12345678;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, strlen(string), &result);
    STAssertTrue(success, @"");
    STAssertEquals(result, expected, @"");
}

- (void) testExtractHexValue2
{
    const char* string = "Some string with 0x1 and such";
    uint64_t expected = 0x1;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, strlen(string), &result);
    STAssertTrue(success, @"");
    STAssertEquals(result, expected, @"");
}

- (void) testExtractHexValue3
{
    const char* string = "Some string with 0x1234567890123456 and such";
    uint64_t expected = 0x1234567890123456;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, strlen(string), &result);
    STAssertTrue(success, @"");
    STAssertEquals(result, expected, @"");
}

- (void) testExtractHexValueBeginning
{
    const char* string = "0x12345678 Some string";
    uint64_t expected = 0x12345678;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, strlen(string), &result);
    STAssertTrue(success, @"");
    STAssertEquals(result, expected, @"");
}

- (void) testExtractHexValueEnd
{
    const char* string = "Some string with 0x12345678";
    uint64_t expected = 0x12345678;
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, strlen(string), &result);
    STAssertTrue(success, @"");
    STAssertEquals(result, expected, @"");
}

- (void) testExtractHexValueEmpty
{
    const char* string = "";
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, strlen(string), &result);
    STAssertFalse(success, @"");
}

- (void) testExtractHexValueInvalid
{
    const char* string = "Some string with 0xoo and such";
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, strlen(string), &result);
    STAssertFalse(success, @"");
}

- (void) testExtractHexValueInvalid2
{
    const char* string = "Some string with 0xoo";
    uint64_t result = 0;
    bool success = ksstring_extractHexValue(string, strlen(string), &result);
    STAssertFalse(success, @"");
}

- (void) testIsNullTerminatedUTF8String
{
    const char* string = "A string";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    STAssertTrue(success, @"");
}

- (void) testIsNullTerminatedUTF8String2
{
    const char* string = "テスト";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    STAssertTrue(success, @"");
}

- (void) testIsNullTerminatedUTF8String3
{
    const char* string = "aŸঠ𐅐 and so on";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    STAssertTrue(success, @"");
}

- (void) testIsNullTerminatedUTF8StringTooShort
{
    const char* string = "A string";
    bool success = ksstring_isNullTerminatedUTF8String(string, 10, 100);
    STAssertFalse(success, @"");
}

- (void) testIsNullTerminatedUTF8StringTooLong
{
    const char* string = "A string";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 5);
    STAssertFalse(success, @"");
}

- (void) testIsNullTerminatedUTF8StringInvalid
{
    const char* string = "A string\xf8";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    STAssertFalse(success, @"");
}

- (void) testIsNullTerminatedUTF8StringInvalid2
{
    const char* string = "A string\xc1zzz";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    STAssertFalse(success, @"");
}

- (void) testIsNullTerminatedUTF8StringInvalid3
{
    const char* string = "\xc0";
    bool success = ksstring_isNullTerminatedUTF8String(string, 1, 1);
    STAssertFalse(success, @"");
}

- (void) testIsNullTerminatedUTF8StringInvalid4
{
    const char* string = "blah \x80";
    bool success = ksstring_isNullTerminatedUTF8String(string, 1, 100);
    STAssertFalse(success, @"");
}

- (void) testIsNullTerminatedUTF8StringInvalid5
{
    const char* string = "\x01\x02\x03";
    bool success = ksstring_isNullTerminatedUTF8String(string, 2, 100);
    STAssertFalse(success, @"");
}

@end
