//
//  KSDynamicLinker_Tests.m
//
//  Created by Karl Stenerud on 2013-10-02.
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

#import "KSBinaryImageCache.h"
#import "KSDynamicLinker.h"

@interface KSDynamicLinker_Tests : XCTestCase
@end

// Declare external function only for testing
extern void ksbic_resetCache(void);
extern void ksbic_init(void);

@implementation KSDynamicLinker_Tests

- (void)setUp
{
    [super setUp];
    ksbic_resetCache();
    ksbic_init();
    [NSThread sleepForTimeInterval:0.1];
}

- (void)testImageUUID
{
    uint32_t count = 0;
    const struct ks_dyld_image_info *images = ksbic_getImages(&count);

    KSBinaryImage buffer = { 0 };
    ksdl_binaryImageForHeader(images[4].imageLoadAddress, images[4].imageFilePath, &buffer);

    XCTAssertTrue(buffer.uuid != NULL, @"");
}

@end
