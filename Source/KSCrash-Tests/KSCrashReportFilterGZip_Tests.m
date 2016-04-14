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

#import "KSCrashReportFilterGZip.h"
#import "NSData+GZip.h"


@interface KSCrashReportFilterGZip_Tests : XCTestCase @end


@implementation KSCrashReportFilterGZip_Tests

- (void) testFilterGZipCompress
{
    NSArray* decompressed = [NSArray arrayWithObjects:
                             (id _Nonnull)[@"this is a test" dataUsingEncoding:NSUTF8StringEncoding],
                             (id _Nonnull)[@"here is another test" dataUsingEncoding:NSUTF8StringEncoding],
                             (id _Nonnull)[@"testing is fun!" dataUsingEncoding:NSUTF8StringEncoding],
                             nil];
    
    NSError* error = nil;
    NSMutableArray* compressed = [NSMutableArray array];
    for(NSData* data in decompressed)
    {
        NSData* newData = [data gzippedWithCompressionLevel:-1 error:&error];
        XCTAssertNotNil(newData, @"");
        XCTAssertNil(error, @"");
        [compressed addObject:newData];
    }
    
    id<KSCrashReportFilter> filter = [KSCrashReportFilterGZipCompress filterWithCompressionLevel:-1];
    [filter filterReports:decompressed onCompletion:^(NSArray* filteredReports,
                                                      BOOL completed,
                                                      NSError* error2)
     {
         XCTAssertTrue(completed, @"");
         XCTAssertNil(error2, @"");
         XCTAssertEqualObjects(compressed, filteredReports, @"");
     }];
}

- (void) testFilterGZipDecompress
{
    NSArray* decompressed = [NSArray arrayWithObjects:
                             (id _Nonnull)[@"this is a test" dataUsingEncoding:NSUTF8StringEncoding],
                             (id _Nonnull)[@"here is another test" dataUsingEncoding:NSUTF8StringEncoding],
                             (id _Nonnull)[@"testing is fun!" dataUsingEncoding:NSUTF8StringEncoding],
                             nil];
    
    NSError* error = nil;
    NSMutableArray* compressed = [NSMutableArray array];
    for(NSData* data in decompressed)
    {
        NSData* newData = [data gzippedWithCompressionLevel:-1 error:&error];
        XCTAssertNotNil(newData, @"");
        XCTAssertNil(error, @"");
        [compressed addObject:newData];
    }
    
    id<KSCrashReportFilter> filter = [KSCrashReportFilterGZipDecompress filter];
    [filter filterReports:compressed onCompletion:^(NSArray* filteredReports,
                                                    BOOL completed,
                                                    NSError* error2)
     {
         XCTAssertTrue(completed, @"");
         XCTAssertNil(error2, @"");
         XCTAssertEqualObjects(decompressed, filteredReports, @"");
     }];
}

@end
