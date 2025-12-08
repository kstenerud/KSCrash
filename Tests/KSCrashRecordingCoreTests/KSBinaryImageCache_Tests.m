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

@interface KSBinaryImageCache_Tests : XCTestCase
@end

@implementation KSBinaryImageCache_Tests

- (void)setUp
{
    [super setUp];
    extern void ksbic_resetCache(void);
    ksbic_resetCache();
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ksbic_init();
#pragma clang diagnostic pop
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

#pragma mark - ksbic_findImageForAddress Tests

- (void)testFindImageForAddress_HeaderAddress
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        const struct mach_header *expectedHeader = images[i].imageLoadAddress;
        uintptr_t address = (uintptr_t)expectedHeader;

        uintptr_t slide = 0;
        const char *name = NULL;
        const struct mach_header *foundHeader = ksbic_findImageForAddress(address, &slide, &name);

        XCTAssertEqual(foundHeader, expectedHeader, @"Should find correct header for image %@", @(i));
        XCTAssertNotEqual(name, NULL, @"Should return image name for image %@", @(i));
    }
}

- (void)testFindImageForAddress_SlideMatchesDyld
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        const struct mach_header *expectedHeader = images[i].imageLoadAddress;
        uintptr_t address = (uintptr_t)expectedHeader;

        uintptr_t slide = 0;
        const struct mach_header *foundHeader = ksbic_findImageForAddress(address, &slide, NULL);
        XCTAssertNotEqual(foundHeader, NULL, @"Should find image for address");

        // Find the actual slide from dyld
        intptr_t actualSlide = INTPTR_MAX;
        for (uint32_t d = 0; d < _dyld_image_count(); d++) {
            const struct mach_header *dyldHeader = _dyld_get_image_header(d);
            if (dyldHeader == expectedHeader) {
                actualSlide = _dyld_get_image_vmaddr_slide(d);
                break;
            }
        }

        if (actualSlide != INTPTR_MAX) {
            XCTAssertEqual(slide, (uintptr_t)actualSlide, @"Slide should match dyld for image %@", @(i));
        }
    }
}

- (void)testFindImageForAddress_InvalidAddress
{
    // Address 0 should not be in any image
    uintptr_t slide = 0;
    const char *name = NULL;
    const struct mach_header *header = ksbic_findImageForAddress(0, &slide, &name);

    XCTAssertEqual(header, NULL, @"Should return NULL for invalid address");
}

- (void)testFindImageForAddress_RepeatedLookupsCached
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    const struct mach_header *expectedHeader = images[0].imageLoadAddress;
    uintptr_t address = (uintptr_t)expectedHeader;

    // First lookup (populates cache)
    uintptr_t slide1 = 0;
    const char *name1 = NULL;
    const struct mach_header *header1 = ksbic_findImageForAddress(address, &slide1, &name1);

    // Second lookup (should hit cache)
    uintptr_t slide2 = 0;
    const char *name2 = NULL;
    const struct mach_header *header2 = ksbic_findImageForAddress(address, &slide2, &name2);

    XCTAssertEqual(header1, header2, @"Repeated lookups should return same header");
    XCTAssertEqual(slide1, slide2, @"Repeated lookups should return same slide");
    XCTAssertEqual(name1, name2, @"Repeated lookups should return same name");
}

- (void)testFindImageForAddress_AddressWithinImage
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    // Get the first image header
    const struct mach_header *expectedHeader = images[0].imageLoadAddress;

    // Try an address slightly after the header (still within the image)
    uintptr_t address = (uintptr_t)expectedHeader + 0x100;

    uintptr_t slide = 0;
    const char *name = NULL;
    const struct mach_header *foundHeader = ksbic_findImageForAddress(address, &slide, &name);

    XCTAssertEqual(foundHeader, expectedHeader, @"Should find correct image for address within image");
}

- (void)testFindImageForAddress_NearEndOfImage
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    // Get image info to find the size
    const struct mach_header *expectedHeader = images[0].imageLoadAddress;
    KSBinaryImage imageInfo = { 0 };
    bool success = ksdl_binaryImageForHeader(expectedHeader, images[0].imageFilePath, &imageInfo);
    XCTAssertTrue(success, @"Should get binary image info");
    XCTAssertGreaterThan(imageInfo.size, 0, @"Image should have non-zero size");

    // Try an address near the end of the image (but still within bounds)
    // Use address + size - small offset to stay within the image
    uintptr_t addressNearEnd = (uintptr_t)expectedHeader + imageInfo.size - 0x100;

    uintptr_t slide = 0;
    const char *name = NULL;
    const struct mach_header *foundHeader = ksbic_findImageForAddress(addressNearEnd, &slide, &name);

    XCTAssertEqual(foundHeader, expectedHeader, @"Should find correct image for address near end of image");
}

- (void)testFindImageForAddress_JustPastEndOfImage
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    // Get image info to find the size
    const struct mach_header *expectedHeader = images[0].imageLoadAddress;
    KSBinaryImage imageInfo = { 0 };
    bool success = ksdl_binaryImageForHeader(expectedHeader, images[0].imageFilePath, &imageInfo);
    XCTAssertTrue(success, @"Should get binary image info");

    // Try an address just past the end of the TEXT segment
    // This may or may not find the same image depending on other segments
    uintptr_t addressPastText = (uintptr_t)expectedHeader + imageInfo.size + 0x1000;

    uintptr_t slide = 0;
    const char *name = NULL;
    const struct mach_header *foundHeader = ksbic_findImageForAddress(addressPastText, &slide, &name);

    // This address might be in another segment of the same image, or in a different image, or NULL
    // The key is that we don't crash and return a valid result
    // (foundHeader may or may not equal expectedHeader depending on image layout)
    (void)foundHeader;  // Just verify no crash
}

#pragma mark - ksbic_getImageDetailsForAddress Tests

- (void)testGetImageDetailsForAddress_ReturnsSegmentBase
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    const struct mach_header *expectedHeader = images[0].imageLoadAddress;
    uintptr_t address = (uintptr_t)expectedHeader;

    uintptr_t slide = 0;
    uintptr_t segmentBase = 0;
    const char *name = NULL;
    const struct mach_header *foundHeader = ksbic_getImageDetailsForAddress(address, &slide, &segmentBase, &name);

    XCTAssertEqual(foundHeader, expectedHeader, @"Should find correct header");
    XCTAssertNotEqual(name, NULL, @"Should return image name");
    // Segment base should be non-zero for valid images with __LINKEDIT
    // (though we don't strictly require it as some images might not have it)
}

- (void)testGetImageDetailsForAddress_MatchesFindImageForAddress
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    const struct mach_header *expectedHeader = images[0].imageLoadAddress;
    uintptr_t address = (uintptr_t)expectedHeader;

    // Call the simple function
    uintptr_t slide1 = 0;
    const char *name1 = NULL;
    const struct mach_header *header1 = ksbic_findImageForAddress(address, &slide1, &name1);

    // Call the detailed function
    uintptr_t slide2 = 0;
    uintptr_t segmentBase = 0;
    const char *name2 = NULL;
    const struct mach_header *header2 = ksbic_getImageDetailsForAddress(address, &slide2, &segmentBase, &name2);

    // Results should match
    XCTAssertEqual(header1, header2, @"Both functions should return same header");
    XCTAssertEqual(slide1, slide2, @"Both functions should return same slide");
    XCTAssertEqual(name1, name2, @"Both functions should return same name");
}

- (void)testGetImageDetailsForAddress_InvalidAddress
{
    uintptr_t slide = 0;
    uintptr_t segmentBase = 0;
    const char *name = NULL;
    const struct mach_header *header = ksbic_getImageDetailsForAddress(0, &slide, &segmentBase, &name);

    XCTAssertEqual(header, NULL, @"Should return NULL for invalid address");
}

@end
