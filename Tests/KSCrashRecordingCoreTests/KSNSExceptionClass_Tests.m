//
//  KSNSExceptionClass_Tests.m
//
//  Created by Alexander Cohen on 2026-09-27.
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
#import <objc/runtime.h>

#import "KSNSExceptionClass.h"

@interface KSNSExceptionClass_TestSubclass : NSException
@end

@implementation KSNSExceptionClass_TestSubclass
@end

@interface KSNSExceptionClass_Tests : XCTestCase
@end

@implementation KSNSExceptionClass_Tests

- (void)testNSExceptionAndItsSubclassesAreNSExceptions
{
    XCTAssertTrue(ksobjc_isNSExceptionClass([NSException class]));
    XCTAssertTrue(ksobjc_isNSExceptionClass([KSNSExceptionClass_TestSubclass class]));
}

- (void)testOtherClassesAreNot
{
    XCTAssertFalse(ksobjc_isNSExceptionClass([NSString class]));
    XCTAssertFalse(ksobjc_isNSExceptionClass([NSObject class]));
    XCTAssertFalse(ksobjc_isNSExceptionClass(Nil));
}

- (void)testANameThatOnlyStartsWithNSExceptionIsNot
{
    // Registered once per process: a repeated run finds the class already there.
    const char *name = "NSExceptionLookalike_KSCrashTest";
    Class lookalike = objc_lookUpClass(name);
    if (lookalike == Nil) {
        lookalike = objc_allocateClassPair([NSObject class], name, 0);
        XCTAssertTrue(lookalike != Nil);
        objc_registerClassPair(lookalike);
    }
    XCTAssertFalse(ksobjc_isNSExceptionClass(lookalike));
}

@end
