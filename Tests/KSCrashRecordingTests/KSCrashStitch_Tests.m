//
//  KSCrashStitch_Tests.m
//
//  Created by Alexander Cohen on 2026-10-03.
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

#import "KSCrashStitch.h"

@interface KSCrashStitch_Tests : XCTestCase
@end

@implementation KSCrashStitch_Tests

- (NSDictionary *)stitch:(NSDictionary *)report
                    path:(const char *)path
                   scope:(KSCrashSidecarScope)scope
                    read:(KSCrashSidecarReadResult)readResult
                  edited:(BOOL *)edited
{
    *edited = NO;
    return ksstitch_stitchedReport(
        report, path, scope, KSCrashSidecarScopeRun,
        ^(__unused const char *sidecarPath) {
            return readResult;
        },
        ^(NSMutableDictionary *dict) {
            *edited = YES;
            dict[@"stitched"] = @YES;
        });
}

#pragma mark - ksstitch_stitchedReport

- (void)testEditsACopyWhenTheSidecarReads
{
    NSDictionary *report = @{ @"k" : @"v" };
    BOOL edited = NO;
    NSDictionary *result = [self stitch:report
                                   path:"/sidecar"
                                  scope:KSCrashSidecarScopeRun
                                   read:KSCrashSidecarReadOK
                                 edited:&edited];
    XCTAssertTrue(edited);
    XCTAssertEqualObjects(result, (@{ @"k" : @"v", @"stitched" : @YES }));
    XCTAssertNil(report[@"stitched"]);
}

- (void)testAnotherScopeReturnsTheSameReport
{
    NSDictionary *report = @{ @"k" : @"v" };
    BOOL edited = NO;
    NSDictionary *result = [self stitch:report
                                   path:NULL
                                  scope:KSCrashSidecarScopeFinal
                                   read:KSCrashSidecarReadOK
                                 edited:&edited];
    XCTAssertTrue(result == report);
    XCTAssertFalse(edited);
}

- (void)testAnotherScopeDoesNotReadTheSidecar
{
    NSDictionary *report = @{ @"k" : @"v" };
    __block BOOL didRead = NO;
    NSDictionary *result =
        ksstitch_stitchedReport(report, "/sidecar", KSCrashSidecarScopeReport, KSCrashSidecarScopeRun,
                                ^KSCrashSidecarReadResult(__unused const char *sidecarPath) {
                                    didRead = YES;
                                    return KSCrashSidecarReadOK;
                                },
                                ^(__unused NSMutableDictionary *dict) {
                                });
    XCTAssertFalse(didRead);
    XCTAssertTrue(result == report);
}

- (void)testAReadFailureAsksForARetry
{
    BOOL edited = NO;
    XCTAssertNil([self stitch:@{}
                         path:"/sidecar"
                        scope:KSCrashSidecarScopeRun
                         read:KSCrashSidecarReadFailure
                       edited:&edited]);
    XCTAssertFalse(edited);
}

- (void)testAnUnrecoverableSidecarDeliversTheReportUnchanged
{
    NSDictionary *report = @{ @"k" : @"v" };
    BOOL edited = NO;
    NSDictionary *result = [self stitch:report
                                   path:"/sidecar"
                                  scope:KSCrashSidecarScopeRun
                                   read:KSCrashSidecarReadUnrecoverable
                                 edited:&edited];
    XCTAssertTrue(result == report);
    XCTAssertFalse(edited);
}

- (void)testNoReportIsNil
{
    BOOL edited = NO;
    XCTAssertNil([self stitch:nil
                         path:"/sidecar"
                        scope:KSCrashSidecarScopeRun
                         read:KSCrashSidecarReadOK
                       edited:&edited]);
    XCTAssertFalse(edited);
}

- (void)testNoSidecarPathInItsScopeIsNil
{
    BOOL edited = NO;
    XCTAssertNil([self stitch:@{} path:NULL scope:KSCrashSidecarScopeRun read:KSCrashSidecarReadOK edited:&edited]);
    XCTAssertFalse(edited);
}

#pragma mark - ksstitch_object

- (void)testObjectCopiesAnExistingObjectAndStoresItBack
{
    NSDictionary *inner = @{ @"a" : @1 };
    NSMutableDictionary *parent = [@{ @"key" : inner } mutableCopy];
    NSMutableDictionary *object = ksstitch_object(parent, @"key");
    object[@"b"] = @2;
    XCTAssertEqualObjects(parent[@"key"], (@{ @"a" : @1, @"b" : @2 }));
    XCTAssertEqualObjects(inner, @{ @"a" : @1 });
}

- (void)testObjectCreatesOneWhenAbsent
{
    NSMutableDictionary *parent = [NSMutableDictionary dictionary];
    ksstitch_object(parent, @"key")[@"b"] = @2;
    XCTAssertEqualObjects(parent[@"key"], @{ @"b" : @2 });
}

- (void)testObjectReplacesAValueThatIsNotAnObject
{
    NSMutableDictionary *parent = [@{ @"key" : @"text" } mutableCopy];
    ksstitch_object(parent, @"key")[@"b"] = @2;
    XCTAssertEqualObjects(parent[@"key"], @{ @"b" : @2 });
}

@end
