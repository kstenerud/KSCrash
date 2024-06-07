//
//  KSCrashReportFilterJSON_Tests.m
//
//  Created by Karl Stenerud on 2013-03-09.
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

#import "KSCrashReportFilterJSON.h"


@interface KSCrashReportFilterJSON_Tests : XCTestCase @end


@implementation KSCrashReportFilterJSON_Tests

- (void) testFilterJSONEncode
{
    NSArray* decoded = [NSArray arrayWithObjects:
                        [NSArray arrayWithObjects:@"1", @"2", @"3", nil],
                        [NSArray arrayWithObjects:@"4", @"5", @"6", nil],
                        [NSArray arrayWithObjects:@"7", @"8", @"9", nil],
                        nil];
    NSArray* encoded = [NSArray arrayWithObjects:
                        (id _Nonnull)[@"[\"1\",\"2\",\"3\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        (id _Nonnull)[@"[\"4\",\"5\",\"6\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        (id _Nonnull)[@"[\"7\",\"8\",\"9\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        nil];
    
    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONEncode filterWithOptions:0];
    [filter filterReports:decoded onCompletion:^(NSArray* filteredReports,
                                                 BOOL completed,
                                                 NSError* error2)
     {
         XCTAssertTrue(completed, @"");
         XCTAssertNil(error2, @"");
         XCTAssertEqualObjects(encoded, filteredReports, @"");
     }];
}

- (void) testFilterJSONEncodeInvalid
{
    NSArray* decoded = [NSArray arrayWithObjects:
                        [NSException exceptionWithName:@"" reason:@"" userInfo:nil],
                        nil];
    
    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONEncode filterWithOptions:0];
    [filter filterReports:decoded onCompletion:^(__unused NSArray* filteredReports,
                                                 BOOL completed,
                                                 NSError* error2)
     {
         XCTAssertFalse(completed, @"");
         XCTAssertNotNil(error2, @"");
     }];
}

- (void) testFilterJSONDencode
{
    NSArray* decoded = [NSArray arrayWithObjects:
                        [NSArray arrayWithObjects:@"1", @"2", @"3", nil],
                        [NSArray arrayWithObjects:@"4", @"5", @"6", nil],
                        [NSArray arrayWithObjects:@"7", @"8", @"9", nil],
                        nil];
    NSArray* encoded = [NSArray arrayWithObjects:
                        (id _Nonnull)[@"[\"1\",\"2\",\"3\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        (id _Nonnull)[@"[\"4\",\"5\",\"6\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        (id _Nonnull)[@"[\"7\",\"8\",\"9\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        nil];
    
    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONDecode filterWithOptions:0];
    [filter filterReports:encoded onCompletion:^(NSArray* filteredReports,
                                                 BOOL completed,
                                                 NSError* error2)
     {
         XCTAssertTrue(completed, @"");
         XCTAssertNil(error2, @"");
         XCTAssertEqualObjects(decoded, filteredReports, @"");
     }];
}

- (void) testFilterJSONDencodeInvalid
{
    NSArray* encoded = [NSArray arrayWithObjects:
                        (id _Nonnull)[@"[\"1\"\",\"2\",\"3\"]" dataUsingEncoding:NSUTF8StringEncoding],
                        nil];
    
    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONDecode filterWithOptions:0];
    [filter filterReports:encoded onCompletion:^(__unused NSArray* filteredReports,
                                                 BOOL completed,
                                                 NSError* error2)
     {
         XCTAssertFalse(completed, @"");
         XCTAssertNotNil(error2, @"");
     }];
}

@end
