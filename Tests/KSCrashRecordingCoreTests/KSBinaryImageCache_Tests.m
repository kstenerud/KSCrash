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
    [NSThread sleepForTimeInterval:0.1];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testImageCount
{
    int cachedCount = 0;
    const struct dyld_image_info *images = ksbic_beginImageAccess(&cachedCount);
    ksbic_endImageAccess(images);
    uint32_t actualCount = _dyld_image_count();

    XCTAssertGreaterThan(cachedCount, 0, @"There should be at least some images loaded");
    XCTAssertLessThanOrEqual(cachedCount, actualCount, @"Cached count should not exceed actual count");
    XCTAssertGreaterThanOrEqual(cachedCount, actualCount * 0.8,
                                @"Cached count should be at least 80%% of actual count");
}

- (void)testImageHeader
{
    int count = 0;
    const struct dyld_image_info *images = ksbic_beginImageAccess(&count);

    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        const struct mach_header *cachedHeader = images[i].imageLoadAddress;

        XCTAssertNotEqual(cachedHeader, NULL, @"Should get valid cached header for image %@", @(i));
        uint32_t magic = cachedHeader->magic;
        XCTAssertTrue(magic == MH_MAGIC || magic == MH_MAGIC_64 || magic == MH_CIGAM || magic == MH_CIGAM_64,
                      @"Header should have a valid Mach-O magic number for image %@", @(i));
    }

    ksbic_endImageAccess(images);
}

- (void)testImageName
{
    int count = 0;
    const struct dyld_image_info *images = ksbic_beginImageAccess(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        const char *cachedName = images[i].imageFilePath;

        XCTAssertNotEqual(cachedName, NULL, @"Should get valid cached name for image %@", @(i));
        XCTAssertGreaterThan(strlen(cachedName), 0, @"Image name should not be empty for image %@", @(i));
    }

    ksbic_endImageAccess(images);
}

- (void)testImageVMAddrSlide
{
    int count = 0;
    const struct dyld_image_info *images = ksbic_beginImageAccess(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 5); i++) {
        KSBinaryImage buffer = { 0 };
        ksdl_binaryImageForHeader(images[i].imageLoadAddress, images[i].imageFilePath, &buffer);
        uintptr_t cachedSlide = buffer.vmAddressSlide;

        // find the actual one from dyld
        intptr_t actualSlide = 0;
        for (int d = 0; d < _dyld_image_count(); d++) {
            const struct mach_header *dyldHeader = _dyld_get_image_header(d);
            if (dyldHeader == images[i].imageLoadAddress) {
                actualSlide = _dyld_get_image_vmaddr_slide(d);
                break;
                ;
            }
        }

        XCTAssertEqual(cachedSlide, (uintptr_t)actualSlide, @"Cached slide should match actual slide for image %@",
                       @(i));
        XCTAssertTrue(cachedSlide < UINTPTR_MAX / 2, @"Slide should be a reasonable value for image %@", @(i));
    }

    ksbic_endImageAccess(images);
}

- (void)testCachedImagesHaveConsistentData
{
    int count = 0;
    const struct dyld_image_info *images = ksbic_beginImageAccess(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 10); i++) {
        const struct mach_header *header = images[i].imageLoadAddress;
        const char *name = images[i].imageFilePath;

        KSBinaryImage buffer = { 0 };
        ksdl_binaryImageForHeader(images[i].imageLoadAddress, images[i].imageFilePath, &buffer);

        uintptr_t slide = buffer.vmAddressSlide;

        XCTAssertNotEqual(header, NULL, @"Should have valid header for image %@", @(i));
        XCTAssertNotEqual(name, NULL, @"Should have valid name for image %@", @(i));

        uint32_t magic = header->magic;
        XCTAssertTrue(magic == MH_MAGIC || magic == MH_MAGIC_64 || magic == MH_CIGAM || magic == MH_CIGAM_64,
                      @"Header should have a valid Mach-O magic number for image %@", @(i));
        XCTAssertGreaterThan(strlen(name), 0, @"Image name should not be empty for image %@", @(i));
    }

    ksbic_endImageAccess(images);
}

- (void)testInternalConsistency
{
    int count = 0;
    const struct dyld_image_info *images = ksbic_beginImageAccess(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    NSMutableDictionary *headerToIndex = [NSMutableDictionary dictionary];
    NSMutableDictionary *nameToIndex = [NSMutableDictionary dictionary];

    for (uint32_t i = 0; i < MIN(count, 10); i++) {
        const struct mach_header *header = images[i].imageLoadAddress;
        const char *name = images[i].imageFilePath;

        NSNumber *headerIndex = headerToIndex[@((uintptr_t)header)];
        if (headerIndex) {
            XCTAssertEqual([headerIndex unsignedIntValue], i,
                           @"Same header pointer returned for different indices: %@ and %@", headerIndex, @(i));
        } else {
            headerToIndex[@((uintptr_t)header)] = @(i);
        }

        NSString *nsName = @(name);
        NSNumber *nameIndex = nameToIndex[nsName];
        if (nameIndex) {
            NSLog(@"Note: Same image name appears at indices %@ and %@: %@", nameIndex, @(i), nsName);
        } else {
            nameToIndex[nsName] = @(i);
        }
    }
}

@end
