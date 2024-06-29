//
//  KSGZipHelper_Tests.m
//
//  Created by Karl Stenerud on 2012-02-19.
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
#import "KSGZipHelper.h"

@interface NSData_Gzip_Tests : XCTestCase
@end

@implementation NSData_Gzip_Tests

- (void)testCompressDecompress
{
    NSUInteger numBytes = 1000000;
    NSMutableData *data = [NSMutableData dataWithCapacity:numBytes];
    for (NSUInteger i = 0; i < numBytes; i++) {
        unsigned char byte = (unsigned char)i;
        [data appendBytes:&byte length:1];
    }

    NSError *error = nil;
    NSData *original = [NSData dataWithData:data];
    NSData *compressed = [KSGZipHelper gzippedData:original compressionLevel:-1 error:&error];
    XCTAssertNil(error, @"");
    NSData *uncompressed = [KSGZipHelper gunzippedData:compressed error:&error];
    XCTAssertNil(error, @"");

    XCTAssertEqualObjects(uncompressed, original, @"");
    XCTAssertFalse([compressed isEqualToData:uncompressed], @"");
    XCTAssertTrue([compressed length] < [uncompressed length], @"");
}

- (void)testCompressDecompressEmpty
{
    NSError *error = nil;
    NSData *original = [NSData data];
    NSData *compressed = [KSGZipHelper gzippedData:original compressionLevel:-1 error:&error];
    XCTAssertNil(error, @"");
    NSData *uncompressed = [KSGZipHelper gunzippedData:compressed error:&error];
    XCTAssertNil(error, @"");

    XCTAssertEqualObjects(uncompressed, original, @"");
    XCTAssertEqualObjects(compressed, original, @"");
}

- (void)testCompressDecompressNilError
{
    NSUInteger numBytes = 1000;
    NSMutableData *data = [NSMutableData dataWithCapacity:numBytes];
    for (NSUInteger i = 0; i < numBytes; i++) {
        unsigned char byte = (unsigned char)i;
        [data appendBytes:&byte length:1];
    }

    NSData *original = [NSData dataWithData:data];
    NSData *compressed = [KSGZipHelper gzippedData:original compressionLevel:-1 error:NULL];
    NSData *uncompressed = [KSGZipHelper gunzippedData:compressed error:NULL];

    XCTAssertEqualObjects(uncompressed, original, @"");
    XCTAssertFalse([compressed isEqualToData:uncompressed], @"");
    XCTAssertTrue([compressed length] < [uncompressed length], @"");
}

- (void)testCompressDecompressEmptyNilError
{
    NSData *original = [NSData data];
    NSData *compressed = [KSGZipHelper gzippedData:original compressionLevel:-1 error:NULL];
    NSData *uncompressed = [KSGZipHelper gunzippedData:compressed error:NULL];

    XCTAssertEqualObjects(uncompressed, original, @"");
    XCTAssertEqualObjects(compressed, original, @"");
}

@end
