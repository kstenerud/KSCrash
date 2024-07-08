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

#import "KSCrashReport.h"
#import "KSCrashReportFilterJSON.h"

@interface KSCrashReportFilterJSON_Tests : XCTestCase

@property(nonatomic, copy) NSArray *decodedReports;
@property(nonatomic, copy) NSArray *encodedReports;

@end

@implementation KSCrashReportFilterJSON_Tests

- (void)setUp
{
    self.decodedReports = @[
        [KSCrashReportDictionary reportWithValue:@{ @"a" : @"b" }],
        [KSCrashReportDictionary reportWithValue:@{ @"1" : @ { @"2" : @"3" } }],
        [KSCrashReportDictionary reportWithValue:@{ @"?" : @[ @1, @2, @3 ] }],
    ];
    self.encodedReports = @[
        [KSCrashReportData reportWithValue:[@"{\"a\":\"b\"}" dataUsingEncoding:NSUTF8StringEncoding]],
        [KSCrashReportData reportWithValue:[@"{\"1\":{\"2\":\"3\"}}" dataUsingEncoding:NSUTF8StringEncoding]],
        [KSCrashReportData reportWithValue:[@"{\"?\":[1,2,3]}" dataUsingEncoding:NSUTF8StringEncoding]],
    ];
}

- (void)testFilterJSONEncode
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONEncode filterWithOptions:0];
    [filter filterReports:self.decodedReports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error2) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error2, @"");
                 XCTAssertEqualObjects(filteredReports, self.encodedReports, @"");
             }];
}

- (void)testFilterJSONEncodeInvalid
{
    NSArray *decoded = @[
        [KSCrashReportDictionary reportWithValue:@{ @1 : @2 }],  // Not a JSON
    ];

    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONEncode filterWithOptions:0];
    [filter filterReports:decoded
             onCompletion:^(__unused NSArray *filteredReports, BOOL completed, NSError *error2) {
                 XCTAssertFalse(completed, @"");
                 XCTAssertNotNil(error2, @"");
             }];
}

- (void)testFilterJSONDencode
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONDecode filterWithOptions:0];
    [filter filterReports:self.encodedReports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error2) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error2, @"");
                 XCTAssertEqualObjects(filteredReports, self.decodedReports, @"");
             }];
}

- (void)testFilterJSONDencodeInvalid
{
    NSArray *encoded = @[
        [KSCrashReportData reportWithValue:[@"[\"1\"\",\"2\",\"3\"]" dataUsingEncoding:NSUTF8StringEncoding]],
    ];

    id<KSCrashReportFilter> filter = [KSCrashReportFilterJSONDecode filterWithOptions:0];
    [filter filterReports:encoded
             onCompletion:^(__unused NSArray *filteredReports, BOOL completed, NSError *error2) {
                 XCTAssertFalse(completed, @"");
                 XCTAssertNotNil(error2, @"");
             }];
}

@end
