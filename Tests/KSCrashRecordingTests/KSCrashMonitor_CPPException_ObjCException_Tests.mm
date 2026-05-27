//
//  KSCrashMonitor_CPPException_ObjCException_Tests.mm
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

// clang-format off
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreserved-macro-identifier"
#import <XCTest/XCTest.h>
#pragma clang diagnostic pop
// clang-format on

#import "KSCrashMonitor_CPPException+Private.h"

#include <cxxabi.h>
#include <string.h>
#include <stdexcept>
#include <typeinfo>

@interface KSCrashMonitor_CPPException_TestNSExceptionSubclass : NSException
@end

@implementation KSCrashMonitor_CPPException_TestNSExceptionSubclass
@end

@interface KSCrashMonitor_CPPException_ObjCException_Tests : XCTestCase
@end

@implementation KSCrashMonitor_CPPException_ObjCException_Tests

// These tests inspect the active exception's ABI type_info. This is the same discriminator the C++ monitor receives
// from __cxa_throw and __cxa_current_exception_type; the tests avoid invoking terminate() or mutating global monitor
// state.
static std::type_info *currentExceptionType(void) { return __cxxabiv1::__cxa_current_exception_type(); }

// Historically, the C++ exception monitor compared type_info->name() to "NSException". That only covers plain
// NSException because Objective-C exceptions expose the thrown object's dynamic class name there (for example an
// NSException subclass or NSString).
static bool legacyNameCheckMatchesNSException(const std::type_info *tinfo)
{
    return tinfo != nullptr && strcmp(tinfo->name(), "NSException") == 0;
}

- (void)testObjectiveCExceptionDetection_NSException_MatchesLegacyAndNSExceptionCheck
{
    @try {
        [NSException raise:NSInvalidArgumentException format:@"Invalid argument"];
    } @catch (...) {
        std::type_info *tinfo = currentExceptionType();
        XCTAssertTrue(legacyNameCheckMatchesNSException(tinfo));
        XCTAssertTrue(kscm_cppexception_isObjCExceptionType(tinfo));
        XCTAssertEqual(kscm_cppexception_objcClassFromTypeInfo(tinfo), NSException.class);
        XCTAssertTrue(kscm_cppexception_isNSException(tinfo));
    }
}

- (void)testObjectiveCExceptionDetection_NSExceptionSubclass_OnlyMatchesNSExceptionCheck
{
    @try {
        [[KSCrashMonitor_CPPException_TestNSExceptionSubclass exceptionWithName:@"TestException"
                                                                         reason:@"Test"
                                                                       userInfo:nil] raise];
    } @catch (...) {
        std::type_info *tinfo = currentExceptionType();
        XCTAssertFalse(legacyNameCheckMatchesNSException(tinfo));
        XCTAssertTrue(kscm_cppexception_isObjCExceptionType(tinfo));
        XCTAssertEqual(kscm_cppexception_objcClassFromTypeInfo(tinfo),
                       KSCrashMonitor_CPPException_TestNSExceptionSubclass.class);
        XCTAssertTrue(kscm_cppexception_isNSException(tinfo));
    }
}

- (void)testObjectiveCExceptionDetection_ArbitraryObjectiveCObject_DoesNotMatchNSExceptionCheck
{
    @try {
        @throw @"Objective-C object exception";
    } @catch (...) {
        std::type_info *tinfo = currentExceptionType();
        XCTAssertFalse(legacyNameCheckMatchesNSException(tinfo));
        XCTAssertTrue(kscm_cppexception_isObjCExceptionType(tinfo));
        XCTAssertEqual(kscm_cppexception_objcClassFromTypeInfo(tinfo),
                       object_getClass(@"Objective-C object exception"));
        XCTAssertFalse(kscm_cppexception_isNSException(tinfo));
    }
}

- (void)testObjectiveCExceptionDetection_CPPException_MatchesNeitherCheck
{
    try {
        throw std::runtime_error("C++ exception");
    } catch (...) {
        std::type_info *tinfo = currentExceptionType();
        XCTAssertFalse(legacyNameCheckMatchesNSException(tinfo));
        XCTAssertFalse(kscm_cppexception_isObjCExceptionType(tinfo));
        XCTAssertEqual(kscm_cppexception_objcClassFromTypeInfo(tinfo), Nil);
        XCTAssertFalse(kscm_cppexception_isNSException(tinfo));
    }
}

@end
