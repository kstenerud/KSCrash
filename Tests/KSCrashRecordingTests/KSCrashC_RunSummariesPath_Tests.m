//
//  KSCrashC_RunSummariesPath_Tests.m
//
//  Created by Alexander Cohen on 2026-05-17.
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

extern bool kscrash_testcode_deriveReportsSiblingDir(const char *reportsPath, const char *installPath,
                                                     const char *subdir, char *out, size_t outSize);

@interface KSCrashC_RunSummariesPath_Tests : XCTestCase
@end

@implementation KSCrashC_RunSummariesPath_Tests

- (NSString *)derive:(const char *)subdir reports:(const char *)reportsPath install:(const char *)installPath
{
    char out[1024] = { 0 };
    if (!kscrash_testcode_deriveReportsSiblingDir(reportsPath, installPath, subdir, out, sizeof(out))) {
        return nil;
    }
    return @(out);
}

- (void)testNoTrailingSlashUsesSiblingOfReports
{
    XCTAssertEqualObjects([self derive:"Runs" reports:"/tmp/Reports" install:"/tmp/Install"], @"/tmp/Runs");
}

- (void)testSingleTrailingSlashIsNormalized
{
    // Regression: a trailing slash must not yield "/tmp/Reports/Runs" (a child
    // of reports that the store never scans). It must match the ObjC
    // -stringByDeletingLastPathComponent result, "/tmp/Runs".
    XCTAssertEqualObjects([self derive:"Runs" reports:"/tmp/Reports/" install:"/tmp/Install"], @"/tmp/Runs");
}

- (void)testMultipleTrailingSlashesAreNormalized
{
    XCTAssertEqualObjects([self derive:"Runs" reports:"/tmp/Reports///" install:"/tmp/Install"], @"/tmp/Runs");
}

- (void)testNestedReportsPath
{
    XCTAssertEqualObjects([self derive:"Runs" reports:"/a/b/c/Reports/" install:"/x"], @"/a/b/c/Runs");
}

- (void)testNoParentFallsBackToInstallPath
{
    // No usable parent directory → fall back to subdir under installPath.
    XCTAssertEqualObjects([self derive:"Runs" reports:"Reports" install:"/tmp/Install"], @"/tmp/Install/Runs");
    XCTAssertEqualObjects([self derive:"Runs" reports:"/Reports" install:"/tmp/Install"], @"/tmp/Install/Runs");
    XCTAssertEqualObjects([self derive:"Runs" reports:NULL install:"/tmp/Install"], @"/tmp/Install/Runs");
}

- (void)testSidecarsAndRunSidecarsUseSameSiblingRule
{
    // The default Sidecars / RunSidecars dirs must be siblings of reportsPath,
    // matching the ObjC config, not children of installPath.
    XCTAssertEqualObjects([self derive:"Sidecars" reports:"/custom/Reports" install:"/var/Install"],
                          @"/custom/Sidecars");
    XCTAssertEqualObjects([self derive:"RunSidecars" reports:"/custom/Reports/" install:"/var/Install"],
                          @"/custom/RunSidecars");
}

- (void)testTooLongReturnsFalse
{
    char out[8];
    XCTAssertFalse(kscrash_testcode_deriveReportsSiblingDir("/tmp/Reports", "/tmp/Install", "Runs", out, sizeof(out)));
}

@end
