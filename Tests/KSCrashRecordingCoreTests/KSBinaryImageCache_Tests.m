//
//  KSBinaryImageCache_Tests.m
//
//  Created by Gleb Linnik on 2025-04-20.
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
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

#import "KSBinaryImageCache.h"
#import "KSDynamicLinker.h"

// Declare external function only for testing
extern void ksbic_resetCache(void);

@interface KSBinaryImageCache_Tests : XCTestCase
@end

@implementation KSBinaryImageCache_Tests

- (void)setUp
{
    [super setUp];
    ksbic_resetCache();
    ksbic_init();
    ksdl_init();
    [NSThread sleepForTimeInterval:0.1];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testImageCount
{
    // The counts can often be off by a few since `dyld_image_count`
    // doesn't contain removed images.

    uint32_t cachedCount = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&cachedCount);
    (void)images;
    uint32_t actualCount = _dyld_image_count();

    XCTAssertGreaterThan(cachedCount, 0, @"There should be at least some images loaded");
    XCTAssertGreaterThanOrEqual(cachedCount, actualCount, @"Cached count should be at least 100%% of actual count");
}

- (void)testImageHeader
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);

    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        const struct mach_header *cachedHeader = images[i].imageLoadAddress;

        XCTAssertNotEqual(cachedHeader, NULL, @"Should get valid cached header for image %@", @(i));
        uint32_t magic = cachedHeader->magic;
        XCTAssertTrue(magic == MH_MAGIC || magic == MH_MAGIC_64 || magic == MH_CIGAM || magic == MH_CIGAM_64,
                      @"Header should have a valid Mach-O magic number for image %@", @(i));
    }
}

- (void)testImageName
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        const char *cachedName = images[i].imageFilePath;

        XCTAssertNotEqual(cachedName, NULL, @"Should get valid cached name for image %@", @(i));
        XCTAssertGreaterThan(strlen(cachedName), 0, @"Image name should not be empty for image %@", @(i));
    }
}

- (void)testImageVMAddrSlide
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        KSBinaryImage buffer = { 0 };
        ksdl_binaryImageForHeader(images[i].imageLoadAddress, images[i].imageFilePath, &buffer);
        uintptr_t cachedSlide = buffer.vmAddressSlide;

        XCTAssertTrue(cachedSlide < UINTPTR_MAX / 2, @"Slide should be a reasonable value for image %@", @(i));

        // find the actual one from dyld
        intptr_t actualSlide = INTPTR_MAX;
        for (uint32_t d = 0; d < _dyld_image_count(); d++) {
            const struct mach_header *dyldHeader = _dyld_get_image_header(d);
            if (dyldHeader == images[i].imageLoadAddress) {
                actualSlide = _dyld_get_image_vmaddr_slide(d);
                break;
                ;
            }
        }

        if (actualSlide == INTPTR_MAX) {
            // not found, not an error.
            // It's possible that _dyld
            // doesn't have this image cached.
            continue;
        }

        XCTAssertEqual(cachedSlide, (uintptr_t)actualSlide, @"Cached slide should match actual slide for image %@",
                       @(i));
    }
}

- (void)testCachedImagesHaveConsistentData
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 10); i++) {
        const struct mach_header *header = images[i].imageLoadAddress;
        const char *name = images[i].imageFilePath;

        KSBinaryImage buffer = { 0 };
        ksdl_binaryImageForHeader(images[i].imageLoadAddress, images[i].imageFilePath, &buffer);

        uintptr_t slide = buffer.vmAddressSlide;
        (void)slide;

        XCTAssertNotEqual(header, NULL, @"Should have valid header for image %@", @(i));
        XCTAssertNotEqual(name, NULL, @"Should have valid name for image %@", @(i));

        uint32_t magic = header->magic;
        XCTAssertTrue(magic == MH_MAGIC || magic == MH_MAGIC_64 || magic == MH_CIGAM || magic == MH_CIGAM_64,
                      @"Header should have a valid Mach-O magic number for image %@", @(i));
        XCTAssertGreaterThan(strlen(name), 0, @"Image name should not be empty for image %@", @(i));
    }
}

@end
