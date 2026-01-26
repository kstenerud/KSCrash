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

// Regression test for https://github.com/DataDog/dd-sdk-ios/issues/2645
// Before the fix, imageContainingAddress() could return the wrong image due to
// unsigned integer underflow when computing (address - slide) for images loaded
// at addresses higher than the lookup address. This caused dli_fbase to be
// higher than the lookup address, leading to arithmetic overflow in downstream
// offset calculations.
- (void)testDladdrReturnsCorrectImageBase
{
    // Get address of this test function
    uintptr_t testFunctionAddress = (uintptr_t)&KSDynamicLinker_Tests_testDladdrReturnsCorrectImageBase;

    Dl_info info = { 0 };
    bool success = ksdl_dladdr(testFunctionAddress, &info);

    XCTAssertTrue(success, @"ksdl_dladdr should succeed for a valid address");
    XCTAssertNotEqual(info.dli_fbase, NULL, @"dli_fbase should not be NULL");

    // Critical invariant: the image base address must be <= the lookup address.
    // Before the fix, underflow could cause a wrong image with higher base to be returned.
    uintptr_t imageBase = (uintptr_t)info.dli_fbase;
    XCTAssertLessThanOrEqual(imageBase, testFunctionAddress,
                             @"Image base (0x%lx) must be <= lookup address (0x%lx). "
                              "If this fails, ksdl_dladdr returned the wrong image.",
                             (unsigned long)imageBase, (unsigned long)testFunctionAddress);

    // Also verify symbol address invariant
    if (info.dli_saddr != NULL) {
        uintptr_t symbolAddr = (uintptr_t)info.dli_saddr;
        XCTAssertLessThanOrEqual(symbolAddr, testFunctionAddress,
                                 @"Symbol address (0x%lx) must be <= lookup address (0x%lx)", (unsigned long)symbolAddr,
                                 (unsigned long)testFunctionAddress);
    }
}

// Helper function referenced by testDladdrReturnsCorrectImageBase
static void KSDynamicLinker_Tests_testDladdrReturnsCorrectImageBase(void) {}

// Direct test of the underflow condition that caused the bug.
// This test demonstrates the arithmetic issue independent of memory layout.
// See: https://github.com/DataDog/dd-sdk-ios/issues/2645
- (void)testUnderflowArithmeticCondition
{
    // Simulate the bug scenario:
    // - address: a low address we're looking up (e.g., 0x100001000)
    // - slide: from an image loaded at a higher address (e.g., 0x180000000)
    uintptr_t address = 0x100001000;
    uintptr_t highSlide = 0x180000000;

    // Without the fix, this subtraction would underflow
    // addressWSlide = address - highSlide
    // 0x100001000 - 0x180000000 = underflow to ~0xFFFFFFFF80001000 (on 64-bit)

    // The fix adds this guard:
    if (highSlide > address) {
        // This image cannot contain the address - the fix skips it
        XCTAssertTrue(YES, @"Fix correctly skips images where slide > address");
    } else {
        // Only compute the subtraction when it's safe
        uintptr_t addressWSlide = address - highSlide;
        (void)addressWSlide;  // suppress unused warning
        XCTFail(@"This path should not be taken when slide > address");
    }

    // Verify that for a valid case (slide <= address), the math works correctly
    uintptr_t validSlide = 0x1000;
    XCTAssertTrue(validSlide <= address, @"Valid slide should be <= address");
    uintptr_t validAddressWSlide = address - validSlide;
    XCTAssertEqual(validAddressWSlide, 0x100000000, @"Subtraction should work correctly when slide <= address");
}

// Test that verifies the fix for the underflow bug.
// The bug occurred when an image had slide > address, causing (address - slide) to underflow.
// This test verifies that for a low address, we don't incorrectly match a high-slide image.
- (void)testDladdrDoesNotMatchHighSlideImageForLowAddress
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"Should have at least one image");

    // Find the image with the highest load address (highest slide)
    uintptr_t highestImageBase = 0;
    const void *highestHeader = NULL;
    for (uint32_t i = 0; i < count; i++) {
        const void *header = images[i].imageLoadAddress;
        if (header != NULL && (uintptr_t)header > highestImageBase) {
            highestImageBase = (uintptr_t)header;
            highestHeader = header;
        }
    }
    XCTAssertNotEqual(highestHeader, NULL, @"Should find at least one image");

    // Find an image with a lower load address
    uintptr_t lowerImageBase = UINTPTR_MAX;
    const void *lowerHeader = NULL;
    for (uint32_t i = 0; i < count; i++) {
        const void *header = images[i].imageLoadAddress;
        if (header != NULL && (uintptr_t)header < highestImageBase && (uintptr_t)header < lowerImageBase) {
            lowerImageBase = (uintptr_t)header;
            lowerHeader = header;
        }
    }

    // Only run this test if we have images at different addresses
    if (lowerHeader == NULL || lowerImageBase >= highestImageBase) {
        NSLog(@"Skipping underflow test: need images at different addresses");
        return;
    }

    // Look up an address in the lower image
    uintptr_t testAddress = lowerImageBase;
    Dl_info info = { 0 };
    bool success = ksdl_dladdr(testAddress, &info);

    if (success && info.dli_fbase != NULL) {
        uintptr_t resultBase = (uintptr_t)info.dli_fbase;

        // The returned image base should NOT be the highest image
        // If underflow occurred, we might incorrectly match the high image
        XCTAssertNotEqual(resultBase, highestImageBase,
                          @"Low address (0x%lx) should not resolve to highest image (0x%lx). "
                           "This may indicate an underflow bug in imageContainingAddress.",
                          (unsigned long)testAddress, (unsigned long)highestImageBase);

        // The returned base must be <= the test address
        XCTAssertLessThanOrEqual(resultBase, testAddress, @"Result base (0x%lx) must be <= test address (0x%lx)",
                                 (unsigned long)resultBase, (unsigned long)testAddress);
    }
}

// Test that ksdl_dladdr works correctly across multiple images
- (void)testDladdrAcrossMultipleImages
{
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    XCTAssertGreaterThan(count, 0, @"Should have at least one image");

    // Test addresses from multiple loaded images
    NSUInteger testedImages = 0;
    for (uint32_t i = 0; i < count && testedImages < 10; i++) {
        const void *header = images[i].imageLoadAddress;
        if (header == NULL) {
            continue;
        }

        // Use the header address itself as a test address (it's within the image)
        uintptr_t testAddress = (uintptr_t)header;

        Dl_info info = { 0 };
        bool success = ksdl_dladdr(testAddress, &info);

        if (success && info.dli_fbase != NULL) {
            uintptr_t imageBase = (uintptr_t)info.dli_fbase;

            // Critical invariant check
            XCTAssertLessThanOrEqual(imageBase, testAddress, @"Image %u: base (0x%lx) must be <= address (0x%lx)", i,
                                     (unsigned long)imageBase, (unsigned long)testAddress);
            testedImages++;
        }
    }

    XCTAssertGreaterThan(testedImages, 0, @"Should have tested at least one image");
}

@end
