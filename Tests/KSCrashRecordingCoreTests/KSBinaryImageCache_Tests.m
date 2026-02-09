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
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

#import "KSBinaryImageCache.h"
#import "KSDynamicLinker.h"

// Test state for image callback tests
static const struct mach_header *g_lastCallbackHeader = NULL;
static intptr_t g_lastCallbackSlide = 0;
static int g_callbackCount = 0;

static void testImageAddedCallback(const struct mach_header *mh, intptr_t vmaddr_slide)
{
    g_lastCallbackHeader = mh;
    g_lastCallbackSlide = vmaddr_slide;
    g_callbackCount++;
}

@interface KSBinaryImageCache_Tests : XCTestCase
@end

@implementation KSBinaryImageCache_Tests

- (void)setUp
{
    [super setUp];

    // Reset callback test state
    g_lastCallbackHeader = NULL;
    g_lastCallbackSlide = 0;
    g_callbackCount = 0;

    // Unregister any callback before reset
    ksbic_registerForImageAdded(NULL);

    extern void ksbic_resetCache(void);
    ksbic_resetCache();
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ksbic_init();
#pragma clang diagnostic pop
}

- (void)tearDown
{
    // Unregister any callback
    ksbic_registerForImageAdded(NULL);
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

#pragma mark - Regression Tests

/// Regression test: Verify that __PAGEZERO is not included in image address bounds.
/// The main executable's __PAGEZERO segment has vmaddr=0 and vmsize=4GB, but filesize=0.
/// If included in bounds calculation, addresses below the actual image start would
/// incorrectly match the main executable.
- (void)testFindImageForAddress_DoesNotIncludePageZero
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    // Get the main executable (typically first image)
    const struct mach_header *mainHeader = images[0].imageLoadAddress;
    uintptr_t headerAddress = (uintptr_t)mainHeader;

    // The ASLR slide is typically the difference between the loaded address and
    // the __TEXT segment's vmaddr (which is typically 0x100000000 on 64-bit)
    // If __PAGEZERO is incorrectly included, addresses starting from the slide
    // value (around 0x100000000 or so) would match the main executable.

    // Test an address that's significantly below the header but above zero.
    // This address should NOT match any image.
    // We use headerAddress - 0x10000 which is definitely before the image start.
    uintptr_t addressBeforeImage = headerAddress - 0x10000;

    // This address should not find the main executable
    uintptr_t slide = 0;
    const char *name = NULL;
    const struct mach_header *foundHeader = ksbic_findImageForAddress(addressBeforeImage, &slide, &name);

    // The address before the image should either:
    // - Return NULL (not in any image), or
    // - Return a DIFFERENT image (if another image happens to be there)
    // It should NOT return the main executable
    XCTAssertTrue(foundHeader != mainHeader,
                  @"Address 0x%lx before main image should not match main executable at 0x%lx. "
                  @"This may indicate __PAGEZERO is incorrectly included in bounds.",
                  (unsigned long)addressBeforeImage, (unsigned long)headerAddress);
}

/// Regression test: Verify that image address ranges are reasonable sizes.
/// With __PAGEZERO incorrectly included, the range would be ~4GB.
/// Without it, the range should be much smaller (typically < 100MB for most binaries).
- (void)testImageAddressRangesAreReasonable
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    for (uint32_t i = 0; i < MIN(count, 10); i++) {
        const struct mach_header *header = images[i].imageLoadAddress;
        uintptr_t headerAddress = (uintptr_t)header;

        // Look up an address within the image
        uintptr_t slide = 0;
        const char *name = NULL;
        const struct mach_header *foundHeader = ksbic_findImageForAddress(headerAddress, &slide, &name);

        if (foundHeader == NULL) {
            continue;
        }

        // Get image size info
        KSBinaryImage imageInfo = { 0 };
        bool success = ksdl_binaryImageForHeader(foundHeader, name, &imageInfo);
        if (!success) {
            continue;
        }

        // The image size should be reasonable (less than 1GB for normal binaries)
        // If __PAGEZERO is incorrectly included, size would be ~4GB
        uint64_t reasonableMaxSize = 1ULL * 1024 * 1024 * 1024;  // 1GB
        XCTAssertLessThan(imageInfo.size, reasonableMaxSize,
                          @"Image %@ size should be < 1GB, got %llu bytes. "
                          @"This may indicate __PAGEZERO is incorrectly included.",
                          @(i), (unsigned long long)imageInfo.size);
    }
}

#pragma mark - ksbic_registerForImageAdded Tests

- (void)testRegisterForImageAdded_RegisterAndUnregister
{
    // Should not crash when registering
    ksbic_registerForImageAdded(testImageAddedCallback);

    // Should not crash when unregistering
    ksbic_registerForImageAdded(NULL);
}

- (void)testRegisterForImageAdded_CallbackCalledOnDlopen
{
    // Register our callback
    ksbic_registerForImageAdded(testImageAddedCallback);

    int initialCount = g_callbackCount;

    // Load a system library that's likely not already loaded
    // libz is commonly available and small
    void *handle = dlopen("/usr/lib/libz.dylib", RTLD_NOW);

    if (handle != NULL) {
        // If the library was loaded (not already in memory), we should have received a callback
        // Note: if the library was already loaded, we won't get a callback
        // So we just verify no crash and the callback count >= initial
        XCTAssertGreaterThanOrEqual(g_callbackCount, initialCount, @"Callback count should not decrease");

        if (g_callbackCount > initialCount) {
            // We got a callback - verify the parameters are valid
            XCTAssertNotEqual(g_lastCallbackHeader, NULL, @"Callback should receive valid header");

            uint32_t magic = g_lastCallbackHeader->magic;
            XCTAssertTrue(magic == MH_MAGIC || magic == MH_MAGIC_64 || magic == MH_CIGAM || magic == MH_CIGAM_64,
                          @"Callback header should have valid Mach-O magic");
        }

        dlclose(handle);
    }

    ksbic_registerForImageAdded(NULL);
}

- (void)testRegisterForImageAdded_NullCallbackDoesNotCrash
{
    // Register NULL callback
    ksbic_registerForImageAdded(NULL);

    // Load a library - should not crash even with NULL callback
    void *handle = dlopen("/usr/lib/libz.dylib", RTLD_NOW);
    if (handle != NULL) {
        dlclose(handle);
    }

    // Test passes if we get here without crashing
}

- (void)testRegisterForImageAdded_ReplaceCallback
{
    // Register first callback
    ksbic_registerForImageAdded(testImageAddedCallback);

    // Replace with NULL
    ksbic_registerForImageAdded(NULL);

    int countAfterUnregister = g_callbackCount;

    // Load a library
    void *handle = dlopen("/usr/lib/libbz2.dylib", RTLD_NOW);
    if (handle != NULL) {
        dlclose(handle);
    }

    // Callback count should not have changed since we unregistered
    XCTAssertEqual(g_callbackCount, countAfterUnregister, @"Callback should not be called after unregistering");
}

#pragma mark - ksbic_getUnwindInfoForAddress Tests

- (void)testGetUnwindInfoForAddress_ValidAddress
{
    // Use our own function address - we know it's in a valid image
    uintptr_t address = (uintptr_t)&ksbic_getUnwindInfoForAddress;

    KSBinaryImageUnwindInfo unwindInfo = { 0 };
    bool found = ksbic_getUnwindInfoForAddress(address, &unwindInfo);

    XCTAssertTrue(found, @"Should find unwind info for valid code address");
    XCTAssertNotEqual(unwindInfo.header, NULL, @"Unwind info should have valid header");
    // Note: We don't assert slide != 0 because ASLR can legitimately produce a zero slide
    // in some configurations (e.g., simulator, ASLR disabled, or specific memory layouts)

    // At least one of compact unwind or eh_frame should be present
    bool hasUnwindData = unwindInfo.hasCompactUnwind || unwindInfo.hasEhFrame;
    XCTAssertTrue(hasUnwindData, @"Image should have at least one type of unwind data");
}

- (void)testGetUnwindInfoForAddress_InvalidAddress
{
    KSBinaryImageUnwindInfo unwindInfo = { 0 };
    bool found = ksbic_getUnwindInfoForAddress(0, &unwindInfo);

    XCTAssertFalse(found, @"Should not find unwind info for invalid address");
}

- (void)testGetUnwindInfoForAddress_NullOutInfo
{
    uintptr_t address = (uintptr_t)&ksbic_getUnwindInfoForAddress;

    // Should not crash with NULL outInfo
    bool found = ksbic_getUnwindInfoForAddress(address, NULL);
    XCTAssertTrue(found, @"Should still return true for valid address with NULL outInfo");
}

#pragma mark - ksbic_getUnwindInfoForHeader Tests

- (void)testGetUnwindInfoForHeader_ValidHeader
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    const struct mach_header *header = images[0].imageLoadAddress;

    KSBinaryImageUnwindInfo unwindInfo = { 0 };
    bool found = ksbic_getUnwindInfoForHeader(header, &unwindInfo);

    XCTAssertTrue(found, @"Should find unwind info for valid header");
    XCTAssertEqual(unwindInfo.header, header, @"Unwind info header should match input header");
}

- (void)testGetUnwindInfoForHeader_NullHeader
{
    KSBinaryImageUnwindInfo unwindInfo = { 0 };
    bool found = ksbic_getUnwindInfoForHeader(NULL, &unwindInfo);

    XCTAssertFalse(found, @"Should not find unwind info for NULL header");
}

#pragma mark - ksbic_getAppHeader / ksbic_getDyldHeader Tests

- (void)testGetAppHeader_ReturnsMainExecutable
{
    const struct mach_header *appHeader = ksbic_getAppHeader();
    XCTAssertNotEqual(appHeader, NULL, @"Should return app header");

    // Should match the first image in the dyld list
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0);
    XCTAssertEqual(appHeader, images[0].imageLoadAddress, @"App header should be the first image");
}

- (void)testGetDyldHeader_ReturnsValidHeader
{
    const struct mach_header *dyldHeader = ksbic_getDyldHeader();
    XCTAssertNotEqual(dyldHeader, NULL, @"Should return dyld header");

    uint32_t magic = dyldHeader->magic;
    XCTAssertTrue(magic == MH_MAGIC || magic == MH_MAGIC_64, @"dyld header should have valid Mach-O magic");
}

- (void)testGetDyldHeader_NotInImageList
{
    const struct mach_header *dyldHeader = ksbic_getDyldHeader();
    XCTAssertNotEqual(dyldHeader, NULL);

    // dyld should NOT be in the normal image list
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    for (uint32_t i = 0; i < count; i++) {
        XCTAssertNotEqual(images[i].imageLoadAddress, dyldHeader, @"dyld should not appear in the infoArray (image %@)",
                          @(i));
    }
}

- (void)testGetDyldPath_ReturnsValidPath
{
    const char *path = ksbic_getDyldPath();
    XCTAssertNotEqual(path, NULL, @"Should return a dyld path");
    XCTAssertTrue(strlen(path) > 0, @"Path should not be empty");
    XCTAssertTrue(strstr(path, "dyld") != NULL, @"Path should contain 'dyld'");
}

#pragma mark - ksbic_getUUIDForHeader Tests

- (void)testGetUUIDForHeader_ReturnsValidUUID
{
    const struct mach_header *appHeader = ksbic_getAppHeader();
    XCTAssertNotEqual(appHeader, NULL);

    const uint8_t *uuid = ksbic_getUUIDForHeader(appHeader);
    XCTAssertNotEqual(uuid, NULL, @"App should have a UUID");

    // UUID should not be all zeros
    bool allZero = true;
    for (int i = 0; i < 16; i++) {
        if (uuid[i] != 0) {
            allZero = false;
            break;
        }
    }
    XCTAssertFalse(allZero, @"UUID should not be all zeros");
}

- (void)testGetUUIDForHeader_MatchesDynamicLinker
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0);

    const struct mach_header *header = images[0].imageLoadAddress;

    // Get UUID from our cache
    const uint8_t *cachedUUID = ksbic_getUUIDForHeader(header);
    XCTAssertNotEqual(cachedUUID, NULL);

    // Get UUID from ksdl_binaryImageForHeader
    KSBinaryImage image = { 0 };
    bool success = ksdl_binaryImageForHeader(header, images[0].imageFilePath, &image);
    XCTAssertTrue(success);
    XCTAssertNotEqual(image.uuid, NULL);

    // They should match
    XCTAssertEqual(memcmp(cachedUUID, image.uuid, 16), 0, @"Cached UUID should match ksdl_binaryImageForHeader UUID");
}

- (void)testGetUUIDForHeader_DyldHasUUID
{
    const struct mach_header *dyldHeader = ksbic_getDyldHeader();
    XCTAssertNotEqual(dyldHeader, NULL);

    const uint8_t *uuid = ksbic_getUUIDForHeader(dyldHeader);
    XCTAssertNotEqual(uuid, NULL, @"dyld should have a UUID");
}

- (void)testGetUUIDForHeader_NullHeader
{
    const uint8_t *uuid = ksbic_getUUIDForHeader(NULL);
    XCTAssertEqual(uuid, NULL, @"NULL header should return NULL UUID");
}

- (void)testGetUUIDForHeader_ConsistentAcrossCalls
{
    const struct mach_header *appHeader = ksbic_getAppHeader();
    XCTAssertNotEqual(appHeader, NULL);

    const uint8_t *uuid1 = ksbic_getUUIDForHeader(appHeader);
    const uint8_t *uuid2 = ksbic_getUUIDForHeader(appHeader);

    XCTAssertNotEqual(uuid1, NULL);
    XCTAssertEqual(uuid1, uuid2, @"Repeated calls should return the same pointer");
}

- (void)testGetUnwindInfoForHeader_ConsistentWithAddressLookup
{
    // Get an image and look up its unwind info both by header and by address
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"There should be at least some images loaded");

    const struct mach_header *header = images[0].imageLoadAddress;
    uintptr_t address = (uintptr_t)header;

    KSBinaryImageUnwindInfo infoByHeader = { 0 };
    KSBinaryImageUnwindInfo infoByAddress = { 0 };

    bool foundByHeader = ksbic_getUnwindInfoForHeader(header, &infoByHeader);
    bool foundByAddress = ksbic_getUnwindInfoForAddress(address, &infoByAddress);

    XCTAssertTrue(foundByHeader, @"Should find by header");
    XCTAssertTrue(foundByAddress, @"Should find by address");

    // Both should return the same unwind info
    XCTAssertEqual(infoByHeader.header, infoByAddress.header, @"Headers should match");
    XCTAssertEqual(infoByHeader.slide, infoByAddress.slide, @"Slides should match");
    XCTAssertEqual(infoByHeader.hasCompactUnwind, infoByAddress.hasCompactUnwind, @"hasCompactUnwind should match");
    XCTAssertEqual(infoByHeader.hasEhFrame, infoByAddress.hasEhFrame, @"hasEhFrame should match");
}

@end
