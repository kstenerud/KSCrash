//
//  KSJSONCodecDecodeBenchmarks.m
//
//  Created by Alexander Cohen on 2026-08-30.
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

#import "KSBenchmarkTestCase.h"
#import "KSJSONCodecObjC.h"

@interface KSJSONCodecDecodeBenchmarks : KSBenchmarkTestCaseObjC
@end

@implementation KSJSONCodecDecodeBenchmarks

/// A report-shaped payload (8 threads, 64 frames each), built as a JSON string
/// so no nested ObjC literals are involved.
- (NSData *)reportShapedData
{
    NSMutableString *json = [NSMutableString stringWithString:@"{\"report\":{\"id\":\"benchmark\"},\"threads\":["];
    for (int t = 0; t < 8; t++) {
        if (t > 0) {
            [json appendString:@","];
        }
        [json appendFormat:@"{\"index\":%d,\"crashed\":%s,\"backtrace\":{\"contents\":[", t, t == 0 ? "true" : "false"];
        for (int f = 0; f < 64; f++) {
            if (f > 0) {
                [json appendString:@","];
            }
            [json appendFormat:@"{\"instruction_addr\":%llu,\"object_name\":\"BenchmarkApp\",\"symbol_name\":"
                               @"\"symbol_%d_%d\"}",
                               0x100000000ULL + (unsigned long long)(f * 0x40), t, f];
        }
        [json appendString:@"]}}"];
    }
    [json appendString:@"]}"];
    return [json dataUsingEncoding:NSUTF8StringEncoding];
}

/// 500 decodes of a small container, the shape a metadata stitch reads.
- (void)testBenchmarkDecodeSmallContainer
{
    NSData *data = [@"{\"items\":3,\"flags\":[true],\"name\":\"kscrash\"}" dataUsingEncoding:NSUTF8StringEncoding];
    __block id value = nil;
    [self measureBlock:^{
        for (int i = 0; i < 500; i++) {
            value = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
        }
    }];
    XCTAssertTrue([value isKindOfClass:[NSDictionary class]]);
}

/// 10 decodes of a report-shaped payload, the send path's per-report read.
- (void)testBenchmarkDecodeReportShapedPayload
{
    NSData *data = [self reportShapedData];
    __block id value = nil;
    [self measureBlock:^{
        for (int i = 0; i < 10; i++) {
            value = [KSJSONCodec decode:data options:KSJSONDecodeOptionNone error:nil];
        }
    }];
    XCTAssertTrue([value isKindOfClass:[NSDictionary class]]);
}

/// 500 decodes of a null-salted container with the null-dropping options the
/// delivery reads use.
- (void)testBenchmarkDecodeIgnoringNulls
{
    NSData *data = [@"{\"kept\":1,\"nope\":null,\"list\":[\"a\",null,\"b\",null,\"c\"],\"deep\":{\"x\":null,\"y\":2}}"
        dataUsingEncoding:NSUTF8StringEncoding];
    __block id value = nil;
    [self measureBlock:^{
        for (int i = 0; i < 500; i++) {
            value = [KSJSONCodec decode:data
                                options:KSJSONDecodeOptionIgnoreNullInArray | KSJSONDecodeOptionIgnoreNullInObject
                                  error:nil];
        }
    }];
    XCTAssertTrue([value isKindOfClass:[NSDictionary class]]);
}

@end
