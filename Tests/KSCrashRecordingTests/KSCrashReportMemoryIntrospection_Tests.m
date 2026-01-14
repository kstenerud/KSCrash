//
//  KSCrashReportMemoryIntrospection_Tests.m
//
//  Created by Alexander Cohen on 2026-01-08.
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

#import "KSCrashReportMemoryIntrospection.h"

@interface KSCrashReportMemoryIntrospection_Tests : XCTestCase
@end

@implementation KSCrashReportMemoryIntrospection_Tests

- (void)setUp
{
    [super setUp];
    // Reset state before each test
    kscrmi_setIntrospectMemory(false);
    kscrmi_setDoNotIntrospectClasses(NULL, 0);
}

- (void)tearDown
{
    // Clean up after each test
    kscrmi_setIntrospectMemory(false);
    kscrmi_setDoNotIntrospectClasses(NULL, 0);
    [super tearDown];
}

#pragma mark - Introspection Enabled Tests

- (void)testIntrospectionDisabledByDefault
{
    // After reset in setUp, introspection should be disabled
    XCTAssertFalse(kscrmi_isIntrospectionEnabled(), @"Introspection should be disabled by default");
}

- (void)testSetIntrospectMemoryEnabled
{
    kscrmi_setIntrospectMemory(true);
    XCTAssertTrue(kscrmi_isIntrospectionEnabled(), @"Introspection should be enabled after setting to true");
}

- (void)testSetIntrospectMemoryDisabled
{
    kscrmi_setIntrospectMemory(true);
    kscrmi_setIntrospectMemory(false);
    XCTAssertFalse(kscrmi_isIntrospectionEnabled(), @"Introspection should be disabled after setting to false");
}

- (void)testSetIntrospectMemoryToggle
{
    XCTAssertFalse(kscrmi_isIntrospectionEnabled());

    kscrmi_setIntrospectMemory(true);
    XCTAssertTrue(kscrmi_isIntrospectionEnabled());

    kscrmi_setIntrospectMemory(false);
    XCTAssertFalse(kscrmi_isIntrospectionEnabled());

    kscrmi_setIntrospectMemory(true);
    XCTAssertTrue(kscrmi_isIntrospectionEnabled());
}

#pragma mark - Do Not Introspect Classes Tests

- (void)testSetDoNotIntrospectClassesWithNull
{
    // Should not crash when setting NULL
    kscrmi_setDoNotIntrospectClasses(NULL, 0);
    // If we get here without crashing, the test passes
}

- (void)testSetDoNotIntrospectClassesWithEmptyArray
{
    const char *classes[] = {};
    kscrmi_setDoNotIntrospectClasses(classes, 0);
    // Should not crash
}

- (void)testSetDoNotIntrospectClassesWithSingleClass
{
    const char *classes[] = { "NSObject" };
    kscrmi_setDoNotIntrospectClasses(classes, 1);
    // Should not crash
}

- (void)testSetDoNotIntrospectClassesWithMultipleClasses
{
    const char *classes[] = { "NSObject", "NSString", "NSArray", "NSDictionary" };
    kscrmi_setDoNotIntrospectClasses(classes, 4);
    // Should not crash
}

- (void)testSetDoNotIntrospectClassesReplacesExisting
{
    const char *classes1[] = { "NSObject", "NSString" };
    kscrmi_setDoNotIntrospectClasses(classes1, 2);

    const char *classes2[] = { "NSArray" };
    kscrmi_setDoNotIntrospectClasses(classes2, 1);
    // Should not crash, and old classes should be freed
}

- (void)testSetDoNotIntrospectClassesClearsWithNull
{
    const char *classes[] = { "NSObject", "NSString" };
    kscrmi_setDoNotIntrospectClasses(classes, 2);

    kscrmi_setDoNotIntrospectClasses(NULL, 0);
    // Should not crash, and classes should be cleared
}

- (void)testSetDoNotIntrospectClassesMultipleTimes
{
    // Test repeated setting to ensure memory management is correct
    for (int i = 0; i < 100; i++) {
        const char *classes[] = { "NSObject", "NSString", "NSArray" };
        kscrmi_setDoNotIntrospectClasses(classes, 3);
    }
    // Should not leak memory (would need to check with instruments/sanitizers)
    kscrmi_setDoNotIntrospectClasses(NULL, 0);
}

#pragma mark - Valid Pointer Tests

- (void)testIsValidPointerWithNull
{
    XCTAssertFalse(kscrmi_isValidPointer((uintptr_t)NULL), @"NULL should not be a valid pointer");
}

- (void)testIsValidPointerWithValidAddress
{
    int value = 42;
    XCTAssertTrue(kscrmi_isValidPointer((uintptr_t)&value), @"Stack address should be valid");
}

#pragma mark - Valid String Tests

- (void)testIsValidStringWithNull
{
    XCTAssertFalse(kscrmi_isValidString(NULL), @"NULL should not be a valid string");
}

- (void)testIsValidStringWithValidString
{
    const char *str = "Hello, World!";
    XCTAssertTrue(kscrmi_isValidString(str), @"Valid C string should be recognized");
}

- (void)testIsValidStringWithShortString
{
    const char *str = "Hi";  // Less than kMinStringLength (4)
    XCTAssertFalse(kscrmi_isValidString(str), @"Short string should not be valid");
}

- (void)testIsValidStringWithExactMinLength
{
    const char *str = "Test";  // Exactly kMinStringLength (4)
    XCTAssertTrue(kscrmi_isValidString(str), @"String with exact min length should be valid");
}

@end
