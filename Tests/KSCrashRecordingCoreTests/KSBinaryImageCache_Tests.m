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

@interface KSBinaryImageCache_Tests : XCTestCase
@end

@implementation KSBinaryImageCache_Tests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testImageCount
{
    uint32_t cachedCount = ksbic_imageCount();
    uint32_t actualCount = _dyld_image_count();

    XCTAssertGreaterThan(cachedCount, 0, @"There should be at least some images loaded");

    // The cached count could be less than or equal to actual count since our cache has a limit
    // and new libraries could be loaded after initialization
    XCTAssertLessThanOrEqual(cachedCount, actualCount, @"Cached count should not exceed actual count");

    // But we should have most of the images
    XCTAssertGreaterThanOrEqual(cachedCount, actualCount * 0.8,
                                @"Cached count should be at least 80%% of actual count");
}

- (void)testImageHeader
{
    uint32_t count = ksbic_imageCount();
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    // Test first few images and compare with dyld values
    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        const struct mach_header *cachedHeader = ksbic_imageHeader(i);
        const struct mach_header *actualHeader = _dyld_get_image_header(i);

        XCTAssertNotEqual(cachedHeader, NULL, @"Should get valid cached header for image %@", @(i));
        XCTAssertNotEqual(actualHeader, NULL, @"Should get valid actual header for image %@", @(i));

        // The headers should either be the same pointer or have the same content
        if (cachedHeader != actualHeader) {
            // Check magic number in header is valid
            XCTAssertEqual(cachedHeader->magic, actualHeader->magic,
                           @"Cached header magic number should match actual for image %@", @(i));
            XCTAssertEqual(cachedHeader->cputype, actualHeader->cputype,
                           @"Cached header CPU type should match actual for image %@", @(i));
            XCTAssertEqual(cachedHeader->cpusubtype, actualHeader->cpusubtype,
                           @"Cached header CPU subtype should match actual for image %@", @(i));
        }

        // Check magic number is valid regardless
        uint32_t magic = cachedHeader->magic;
        XCTAssertTrue(magic == MH_MAGIC || magic == MH_MAGIC_64 || magic == MH_CIGAM || magic == MH_CIGAM_64,
                      @"Header should have a valid Mach-O magic number for image %@", @(i));
    }

    // Test invalid index
    XCTAssertEqual(ksbic_imageHeader(UINT32_MAX), NULL, @"Should return NULL for invalid image index");
}

- (void)testImageName
{
    uint32_t count = ksbic_imageCount();
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    // Test first few images and compare with dyld values
    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        const char *cachedName = ksbic_imageName(i);
        const char *actualName = _dyld_get_image_name(i);

        XCTAssertNotEqual(cachedName, NULL, @"Should get valid cached name for image %@", @(i));
        XCTAssertNotEqual(actualName, NULL, @"Should get valid actual name for image %@", @(i));

        // The names might not be the same pointer, but the content should match
        if (cachedName != actualName) {
            // The strings should be equivalent
            XCTAssertTrue(strcmp(cachedName, actualName) == 0, @"Cached name should match actual name for image %@",
                          @(i));
        }

        // Cached name should be valid regardless
        XCTAssertGreaterThan(strlen(cachedName), 0, @"Image name should not be empty for image %@", @(i));
    }

    // Test invalid index
    XCTAssertEqual(ksbic_imageName(UINT32_MAX), NULL, @"Should return NULL for invalid image index");
}

- (void)testImageVMAddrSlide
{
    uint32_t count = ksbic_imageCount();
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    // Test first few images and compare with dyld values
    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        uintptr_t cachedSlide = ksbic_imageVMAddrSlide(i);
        intptr_t actualSlide = _dyld_get_image_vmaddr_slide(i);

        // The slides should match
        XCTAssertEqual(cachedSlide, (uintptr_t)actualSlide, @"Cached slide should match actual slide for image %@",
                       @(i));

        // The slide is platform-dependent, but we can at least check it's a reasonable value
        XCTAssertTrue(cachedSlide < UINTPTR_MAX / 2, @"Slide should be a reasonable value for image %@", @(i));
    }

    // Test invalid index returns 0
    XCTAssertEqual(ksbic_imageVMAddrSlide(UINT32_MAX), 0, @"Should return 0 for invalid image index");
}

- (void)testCachedImagesHaveConsistentData
{
    uint32_t count = ksbic_imageCount();
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    // Sample a few images and check they have consistent data
    for (uint32_t i = 0; i < MIN(count, 10); i++) {
        const struct mach_header *header = ksbic_imageHeader(i);
        const char *name = ksbic_imageName(i);
        uintptr_t slide = ksbic_imageVMAddrSlide(i);

        XCTAssertNotEqual(header, NULL, @"Should have valid header for image %@", @(i));
        XCTAssertNotEqual(name, NULL, @"Should have valid name for image %@", @(i));

        // Check that the magic number is valid
        uint32_t magic = header->magic;
        XCTAssertTrue(magic == MH_MAGIC || magic == MH_MAGIC_64 || magic == MH_CIGAM || magic == MH_CIGAM_64,
                      @"Header should have a valid Mach-O magic number for image %@", @(i));

        // Check that name is a valid string
        XCTAssertGreaterThan(strlen(name), 0, @"Image name should not be empty for image %@", @(i));
    }
}

// Test that cached binary image data is consistent with itself -
// header pointers correspond to correct names and slides
- (void)testInternalConsistency
{
    uint32_t count = ksbic_imageCount();
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    // Keep a map of pointers to indices to ensure uniqueness
    NSMutableDictionary *headerToIndex = [NSMutableDictionary dictionary];
    NSMutableDictionary *nameToIndex = [NSMutableDictionary dictionary];

    // Sample images and check consistency
    for (uint32_t i = 0; i < MIN(count, 10); i++) {
        const struct mach_header *header = ksbic_imageHeader(i);
        const char *name = ksbic_imageName(i);

        // Headers should be unique per index
        NSNumber *headerIndex = headerToIndex[@((uintptr_t)header)];
        if (headerIndex) {
            XCTAssertEqual([headerIndex unsignedIntValue], i,
                           @"Same header pointer returned for different indices: %@ and %@", headerIndex, @(i));
        } else {
            headerToIndex[@((uintptr_t)header)] = @(i);
        }

        // Cached names should be consistent
        NSString *nsName = @(name);
        NSNumber *nameIndex = nameToIndex[nsName];
        if (nameIndex) {
            // Name could be duplicated in rare cases - just report it
            NSLog(@"Note: Same image name appears at indices %@ and %@: %@", nameIndex, @(i), nsName);
        } else {
            nameToIndex[nsName] = @(i);
        }
    }
}

@end
