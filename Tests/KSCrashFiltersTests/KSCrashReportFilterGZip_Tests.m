//
//  KSCrashReportFilterGZip_Tests.m
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
#import "KSCrashReportFilterGZip.h"
#import "KSGZipHelper.h"

@interface KSCrashReportFilterGZip_Tests : XCTestCase

@property(nonatomic, copy) NSArray *decompressedReports;
@property(nonatomic, copy) NSArray *compressedReports;

@end

@implementation KSCrashReportFilterGZip_Tests

- (void)setUp
{
    self.decompressedReports = @[
        [KSCrashReportData reportWithValue:[@"this is a test" dataUsingEncoding:NSUTF8StringEncoding]],
        [KSCrashReportData reportWithValue:[@"here is another test" dataUsingEncoding:NSUTF8StringEncoding]],
        [KSCrashReportData reportWithValue:[@"testing is fun!" dataUsingEncoding:NSUTF8StringEncoding]],
    ];

    NSError *error = nil;
    NSMutableArray *compressed = [NSMutableArray array];
    for (KSCrashReportData *report in self.decompressedReports) {
        NSData *newData = [KSGZipHelper gzippedData:report.value compressionLevel:-1 error:&error];
        [compressed addObject:[KSCrashReportData reportWithValue:newData]];
    }
    self.compressedReports = [compressed copy];
}

- (void)testFilterGZipCompress
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1];
    [filter filterReports:self.decompressedReports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error2) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error2, @"");
                 XCTAssertEqualObjects(filteredReports, self.compressedReports, @"");
             }];
}

- (void)testFilterGZipDecompress
{
    id<KSCrashReportFilter> filter = [KSCrashReportFilterGZipDecompress filter];
    [filter filterReports:self.compressedReports
             onCompletion:^(NSArray *filteredReports, BOOL completed, NSError *error2) {
                 XCTAssertTrue(completed, @"");
                 XCTAssertNil(error2, @"");
                 XCTAssertEqualObjects(filteredReports, self.decompressedReports, @"");
             }];
}

@end
