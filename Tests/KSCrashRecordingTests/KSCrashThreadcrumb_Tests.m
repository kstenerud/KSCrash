//
//  KSCrashThreadcrumb_Tests.m
//
//  Created by Alexander Cohen on 2026-02-03.
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

#import "KSCrashThreadcrumb.h"

@interface KSCrashThreadcrumb_Tests : XCTestCase
@end

@implementation KSCrashThreadcrumb_Tests

#pragma mark - Basic Encoding

- (void)testLogReturnsAddressesForEachCharacter
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"ABC"];

    XCTAssertEqual(addresses.count, 3, @"Should return one address per character");
}

- (void)testLogReturnsNonZeroAddresses
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"XYZ"];

    for (NSNumber *addr in addresses) {
        XCTAssertGreaterThan(addr.unsignedLongLongValue, 0, @"Addresses should be non-zero");
    }
}

- (void)testLogReturnsUniqueAddressesForDifferentCharacters
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"AB"];

    XCTAssertEqual(addresses.count, 2);
    XCTAssertNotEqualObjects(addresses[0], addresses[1], @"Different characters should have different addresses");
}

- (void)testLogReturnsAddressesForRepeatedCharacter
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"AA"];

    // Same character produces two addresses (different call sites)
    XCTAssertEqual(addresses.count, 2);
    // Both should be valid non-zero addresses
    XCTAssertGreaterThan(addresses[0].unsignedLongLongValue, 0);
    XCTAssertGreaterThan(addresses[1].unsignedLongLongValue, 0);
}

#pragma mark - Character Set Handling

- (void)testLogHandlesLowercaseLetters
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"abc"];

    XCTAssertEqual(addresses.count, 3);
}

- (void)testLogHandlesUppercaseLetters
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"ABC"];

    XCTAssertEqual(addresses.count, 3);
}

- (void)testLogHandlesDigits
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"0123456789"];

    XCTAssertEqual(addresses.count, 10);
}

- (void)testLogHandlesUnderscore
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"A_B"];

    XCTAssertEqual(addresses.count, 3);
}

- (void)testLogStripsInvalidCharacters
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"A-B.C!D"];

    // Should only encode A, B, C, D (strips -, ., !)
    XCTAssertEqual(addresses.count, 4);
}

- (void)testLogStripsSpaces
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"A B C"];

    XCTAssertEqual(addresses.count, 3);
}

#pragma mark - Edge Cases

- (void)testLogEmptyString
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@""];

    XCTAssertEqual(addresses.count, 0);
}

- (void)testLogOnlyInvalidCharacters
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSArray<NSNumber *> *addresses = [crumb log:@"---...!!!"];

    XCTAssertEqual(addresses.count, 0);
}

- (void)testLogMaximumLength
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];

    // Create a string longer than max
    NSMutableString *longString = [NSMutableString string];
    for (NSInteger i = 0; i < KSCrashThreadcrumbMaximumMessageLength + 10; i++) {
        [longString appendString:@"A"];
    }

    NSArray<NSNumber *> *addresses = [crumb log:longString];

    XCTAssertEqual((NSInteger)addresses.count, KSCrashThreadcrumbMaximumMessageLength,
                   @"Should truncate to max length");
}

#pragma mark - UUID Encoding

- (void)testLogUUIDWithoutHyphens
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    // UUID without hyphens = 32 hex characters
    NSString *uuid = @"550e8400e29b41d4a716446655440000";
    NSArray<NSNumber *> *addresses = [crumb log:uuid];

    XCTAssertEqual(addresses.count, 32, @"Should encode all 32 hex characters");
}

- (void)testLogUUIDWithHyphensStripped
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    // Standard UUID format - hyphens will be stripped
    NSString *uuid = @"550e8400-e29b-41d4-a716-446655440000";
    NSArray<NSNumber *> *addresses = [crumb log:uuid];

    XCTAssertEqual(addresses.count, 32, @"Should encode 32 characters after stripping hyphens");
}

#pragma mark - Multiple Calls

- (void)testMultipleLogCallsReturnSameCount
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];

    NSArray<NSNumber *> *addresses1 = [crumb log:@"ABC"];
    NSArray<NSNumber *> *addresses2 = [crumb log:@"ABC"];

    XCTAssertEqual(addresses1.count, addresses2.count,
                   @"Same message should return same number of addresses");
}

- (void)testLogCanBeCalledMultipleTimes
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];

    NSArray<NSNumber *> *first = [crumb log:@"ABC"];
    NSArray<NSNumber *> *second = [crumb log:@"XYZ"];
    NSArray<NSNumber *> *third = [crumb log:@"123"];

    XCTAssertEqual(first.count, 3);
    XCTAssertEqual(second.count, 3);
    XCTAssertEqual(third.count, 3);
}

#pragma mark - All 63 Characters

- (void)testLogHandlesAll63ValidCharacters
{
    KSCrashThreadcrumb *crumb = [[KSCrashThreadcrumb alloc] init];
    NSString *allChars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
    NSArray<NSNumber *> *addresses = [crumb log:allChars];

    XCTAssertEqual(addresses.count, 63, @"Should handle all 63 valid characters");

    // All addresses should be non-zero
    for (NSNumber *addr in addresses) {
        XCTAssertGreaterThan(addr.unsignedLongLongValue, 0);
    }
}

@end
