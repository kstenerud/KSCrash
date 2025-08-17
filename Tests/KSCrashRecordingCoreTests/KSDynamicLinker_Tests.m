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

#import "KSDynamicLinker.h"

#include <mach-o/dyld.h>

@interface KSDynamicLinker_Tests : XCTestCase
@end

// Declare external function only for testing
extern void ksbic_resetCache(void);
extern void ksbic_init(void);

@implementation KSDynamicLinker_Tests

- (void)setUp
{
    [super setUp];
    ksdl_init();
    ksdl_refreshCache();
    [NSThread sleepForTimeInterval:0.1];
}

- (void)testImageUUID
{
    KSBinaryImage *image = ksdl_imageAtIndex(4);
    XCTAssertNotEqual(image, NULL);
    XCTAssertNotEqual(image->uuid, NULL);
}

- (void)testImageCount
{
    // The counts can often be off by a few since `dyld_image_count`
    // doesn't contain removed images.

    size_t cachedCount = ksdl_imageCount();
    size_t actualCount = _dyld_image_count();

    XCTAssertGreaterThan(cachedCount, 0, @"There should be at least some images loaded");
    XCTAssertGreaterThanOrEqual(cachedCount, actualCount, @"Cached count should be at least 100%% of actual count");
}

- (void)testImageHeader
{
    size_t count = ksdl_imageCount();
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (size_t i = 0; i < MIN(count, 5); i++) {
        KSBinaryImage *image = ksdl_imageAtIndex(i);

        XCTAssertNotEqual(image, NULL, @"Should get valid cached image at index %@", @(i));
        uint32_t magic = image->address->magic;
        XCTAssertTrue(magic == MH_MAGIC || magic == MH_MAGIC_64 || magic == MH_CIGAM || magic == MH_CIGAM_64,
                      @"Header should have a valid Mach-O magic number for image at index %@", @(i));
    }
}

- (void)testImageName
{
    size_t count = ksdl_imageCount();
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (size_t i = 0; i < MIN(count, 5); i++) {
        KSBinaryImage *image = ksdl_imageAtIndex(i);
        const char *cachedName = image->filePath;

        XCTAssertNotEqual(cachedName, NULL, @"Should get valid cached name for image %@", @(i));
        XCTAssertGreaterThan(strlen(cachedName), 0, @"Image name should not be empty for image %@", @(i));
    }
}

- (void)testImageVMAddrSlide
{
    size_t count = ksdl_imageCount();
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (size_t i = 0; i < MIN(count, 5); i++) {
        KSBinaryImage *image = ksdl_imageAtIndex(i);
        uintptr_t cachedSlide = image->vmAddressSlide;

        XCTAssertTrue(cachedSlide < UINTPTR_MAX / 2, @"Slide should be a reasonable value for image %@", @(i));

        // find the actual one from dyld
        intptr_t actualSlide = INTPTR_MAX;
        for (uint32_t d = 0; d < _dyld_image_count(); d++) {
            const struct mach_header *dyldHeader = _dyld_get_image_header(d);
            if ((uintptr_t)dyldHeader == (uintptr_t)image->address) {
                actualSlide = _dyld_get_image_vmaddr_slide(d);
                break;
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
    size_t count = ksdl_imageCount();
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (size_t i = 0; i < MIN(count, 10); i++) {
        KSBinaryImage *image = ksdl_imageAtIndex(i);
        const struct mach_header *header = (struct mach_header *)image->address;
        const char *name = image->filePath;

        uintptr_t slide = image->vmAddressSlide;
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
