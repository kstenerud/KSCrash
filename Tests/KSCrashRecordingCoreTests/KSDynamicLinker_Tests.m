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
    const ks_dyld_image_info *images = ksbic_getImages(&count);

    KSBinaryImage buffer = { 0 };
    ksdl_binaryImageForHeader(images[4].imageLoadAddress, images[4].imageFilePath, &buffer);

    XCTAssertTrue(buffer.uuid != NULL, @"");
}

- (void)testDladdr_FindsSymbol
{
    // Use the address of a known function (ksbic_init itself)
    uintptr_t address = (uintptr_t)ksbic_init;

    Dl_info info = { 0 };
    bool result = ksdl_dladdr(address, &info);

    XCTAssertTrue(result, @"Should find symbol for valid address");
    XCTAssertNotEqual(info.dli_fname, NULL, @"Should have file name");
    XCTAssertNotEqual(info.dli_fbase, NULL, @"Should have file base");
    // Symbol name may or may not be available depending on stripping
}

- (void)testDladdr_ReturnsCorrectImageBase
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"Should have images");

    // Use the header address itself
    uintptr_t address = (uintptr_t)images[0].imageLoadAddress;

    Dl_info info = { 0 };
    bool result = ksdl_dladdr(address, &info);

    XCTAssertTrue(result, @"Should find image for header address");
    XCTAssertEqual(info.dli_fbase, images[0].imageLoadAddress, @"File base should match image header");
}

- (void)testDladdr_InvalidAddress
{
    Dl_info info = { 0 };
    bool result = ksdl_dladdr(0, &info);

    XCTAssertFalse(result, @"Should return false for invalid address");
}

- (void)testDladdr_RepeatedCalls
{
    uintptr_t address = (uintptr_t)ksbic_init;

    Dl_info info1 = { 0 };
    Dl_info info2 = { 0 };

    bool result1 = ksdl_dladdr(address, &info1);
    bool result2 = ksdl_dladdr(address, &info2);

    XCTAssertTrue(result1 && result2, @"Both calls should succeed");
    XCTAssertEqual(info1.dli_fbase, info2.dli_fbase, @"Should return consistent results");
    XCTAssertEqual(info1.dli_fname, info2.dli_fname, @"Should return consistent file name");
}

- (void)testDladdr_ExactMatchReturnsCorrectSymbol
{
    // Use the address of a known function - should be an exact match
    uintptr_t address = (uintptr_t)ksbic_init;

    Dl_info info = { 0 };
    bool result = ksdl_dladdr(address, &info);

    XCTAssertTrue(result, @"Should find symbol for function address");
    XCTAssertNotEqual(info.dli_fbase, NULL, @"Should have file base");
    // For exact match, symbol address should equal the lookup address
    XCTAssertEqual((uintptr_t)info.dli_saddr, address, @"Symbol address should match for exact function entry");
}

- (void)testDladdr_NonExactMatchReturnsNearestSymbol
{
    // Use an address slightly after function entry
    uintptr_t baseAddress = (uintptr_t)ksbic_init;
    uintptr_t offsetAddress = baseAddress + 0x10;  // 16 bytes into function

    Dl_info info = { 0 };
    bool result = ksdl_dladdr(offsetAddress, &info);

    XCTAssertTrue(result, @"Should find symbol for address inside function");
    XCTAssertNotEqual(info.dli_fbase, NULL, @"Should have file base");
    // Symbol address should be <= the lookup address (nearest preceding symbol)
    XCTAssertLessThanOrEqual((uintptr_t)info.dli_saddr, offsetAddress, @"Symbol should precede or equal address");
    // Symbol address should be the function entry point
    XCTAssertEqual((uintptr_t)info.dli_saddr, baseAddress, @"Should find the containing function");
}

@end
