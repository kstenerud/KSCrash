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
#import <string.h>

#import "KSBinaryImageCache.h"
#import "KSDynamicLinker.h"

@interface KSDynamicLinker_Tests : XCTestCase
@end

@implementation KSDynamicLinker_Tests

- (void)setUp
{
    [super setUp];
    ksdl_resetCache();
    ksdl_init();
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
    // Use the address of a known function
    uintptr_t address = (uintptr_t)ksdl_init;

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
    uintptr_t address = (uintptr_t)ksdl_init;

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
    uintptr_t address = (uintptr_t)ksdl_init;

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
    uintptr_t baseAddress = (uintptr_t)ksdl_init;
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

- (void)testDladdr_ReturnsCorrectSymbolName
{
    // Test that we get the actual function name, not GCC_except_table or other wrong symbols
    uintptr_t address = (uintptr_t)ksdl_init;

    Dl_info info = { 0 };
    bool result = ksdl_dladdr(address, &info);

    XCTAssertTrue(result, @"Should find symbol");
    XCTAssertNotEqual(info.dli_sname, NULL, @"Should have symbol name");

    NSString *symbolName = [NSString stringWithUTF8String:info.dli_sname];

    // The symbol should contain "ksdl_init" (possibly with prefix like _ksdl_init)
    XCTAssertTrue([symbolName containsString:@"ksdl_init"], @"Symbol name should be ksdl_init, got: %@", symbolName);

    // Verify it's NOT a GCC_except_table (regression test)
    XCTAssertFalse([symbolName containsString:@"GCC_except_tab"], @"Symbol should not be GCC_except_table, got: %@",
                   symbolName);
}

- (void)testDladdr_DylibSymbolLookup
{
    // Test symbolication of a function in a system dylib
    // This ensures cross-image lookups work correctly and don't return wrong symbols
    // Use strlen from libsystem_c which is a simple C function
    uintptr_t address = (uintptr_t)strlen;

    Dl_info info = { 0 };
    bool result = ksdl_dladdr(address, &info);

    XCTAssertTrue(result, @"Should find symbol in dylib");
    XCTAssertNotEqual(info.dli_fname, NULL, @"Should have file name");
    XCTAssertNotEqual(info.dli_sname, NULL, @"Should have symbol name");

    NSString *symbolName = [NSString stringWithUTF8String:info.dli_sname];
    NSString *fileName = [NSString stringWithUTF8String:info.dli_fname];

    // File should be a system library (not the test binary)
    XCTAssertTrue([fileName containsString:@"/usr/lib/"], @"Should be from a system library, got: %@", fileName);

    // Verify it's NOT a GCC_except_table (regression test for incorrect image matching)
    XCTAssertFalse([symbolName containsString:@"GCC_except_tab"], @"Symbol should not be GCC_except_table, got: %@",
                   symbolName);
}

// The layout libSystem's crash reporter annotations use; mirrors the private crash_info_t in
// KSDynamicLinker.c. Planting one in this test bundle's __DATA,__crash_info gives the
// cross-task reader a real section to find (with task = mach_task_self).
#pragma pack(8)
typedef struct {
    unsigned version;
    const char *message;
    const char *signature;
    const char *backtrace;
    const char *message2;
    void *reserved;
    void *reserved2;
    void *reserved3;
} TestCrashInfo;
#pragma pack()

__attribute__((section("__DATA,__crash_info"))) static TestCrashInfo g_testCrashInfo = {
    .version = 4,
    .message = "test crash message",
    .message2 = "second message",
    .signature = "",  // Empty: the reader must skip it.
    .backtrace = NULL,
};

- (void)testReadCrashInfoFromTaskImage
{
    Dl_info dlinfo = { 0 };
    XCTAssertNotEqual(dladdr(&g_testCrashInfo, &dlinfo), 0);

    KSCrashInfoStrings strings = { 0 };
    XCTAssertTrue(ksdl_readCrashInfoFromTaskImage(mach_task_self(), (uintptr_t)dlinfo.dli_fbase, &strings));

    XCTAssertEqualObjects([NSString stringWithUTF8String:strings.message], @"test crash message");
    XCTAssertEqualObjects([NSString stringWithUTF8String:strings.message2], @"second message");
    XCTAssertEqual(strings.signature, NULL);
    XCTAssertEqual(strings.backtrace, NULL);

    ksdl_freeCrashInfoStrings(&strings);
    XCTAssertEqual(strings.message, NULL);
    XCTAssertEqual(strings.message2, NULL);
}

/** Reads g_testCrashInfo's message through the task reader with the message swapped for a
 *  string of @c length 'x's, and restores the original. Returns the length read, or -1 for none.
 */
static long taskReadMessageLength(size_t length)
{
    Dl_info dlinfo = { 0 };
    if (dladdr(&g_testCrashInfo, &dlinfo) == 0) {
        return -2;
    }
    char *longMessage = malloc(length + 1);
    memset(longMessage, 'x', length);
    longMessage[length] = 0;
    const char *original = g_testCrashInfo.message;
    g_testCrashInfo.message = longMessage;

    KSCrashInfoStrings strings = { 0 };
    ksdl_readCrashInfoFromTaskImage(mach_task_self(), (uintptr_t)dlinfo.dli_fbase, &strings);
    long read = strings.message == NULL ? -1 : (long)strlen(strings.message);

    ksdl_freeCrashInfoStrings(&strings);
    g_testCrashInfo.message = original;
    free(longMessage);
    return read;
}

- (void)testTaskReaderReadsAMessageFarPastTheInProcessCap
{
    // CoreFoundation's uncaught-exception message carries the app's reason, which has no limit.
    XCTAssertEqual(taskReadMessageLength(10000), 10000);
}

- (void)testTaskReaderKeepsAMessageThatFillsItsBoundExactly
{
    // 64 KiB including the terminator.
    XCTAssertEqual(taskReadMessageLength(64 * 1024 - 1), 64 * 1024 - 1);
}

- (void)testTaskReaderDropsAMessageThatNeverTerminatesWithinItsBound
{
    XCTAssertEqual(taskReadMessageLength(64 * 1024), -1);
}

- (void)testBothReadersAcceptLaterCrashInfoVersions
{
    // Version 7 is what iOS 27 and macOS 27 ship. Later versions only grow the struct past the
    // fields read, so every version from 4 up is read the same way.
    Dl_info dlinfo = { 0 };
    XCTAssertNotEqual(dladdr(&g_testCrashInfo, &dlinfo), 0);
    unsigned original = g_testCrashInfo.version;
    g_testCrashInfo.version = 7;

    KSCrashInfoStrings strings = { 0 };
    XCTAssertTrue(ksdl_readCrashInfoFromTaskImage(mach_task_self(), (uintptr_t)dlinfo.dli_fbase, &strings));
    XCTAssertEqualObjects([NSString stringWithUTF8String:strings.message], @"test crash message");
    ksdl_freeCrashInfoStrings(&strings);

    KSBinaryImage image = { 0 };
    XCTAssertTrue(ksdl_binaryImageForHeader(dlinfo.dli_fbase, dlinfo.dli_fname, &image));
    XCTAssertTrue(image.crashInfoMessage != NULL);
    if (image.crashInfoMessage != NULL) {
        XCTAssertEqualObjects([NSString stringWithUTF8String:image.crashInfoMessage], @"test crash message");
    }

    g_testCrashInfo.version = original;
}

- (void)testBothReadersRejectCrashInfoVersionsBeforeFour
{
    Dl_info dlinfo = { 0 };
    XCTAssertNotEqual(dladdr(&g_testCrashInfo, &dlinfo), 0);
    unsigned original = g_testCrashInfo.version;
    g_testCrashInfo.version = 3;

    KSCrashInfoStrings strings = { 0 };
    XCTAssertFalse(ksdl_readCrashInfoFromTaskImage(mach_task_self(), (uintptr_t)dlinfo.dli_fbase, &strings));

    KSBinaryImage image = { 0 };
    XCTAssertTrue(ksdl_binaryImageForHeader(dlinfo.dli_fbase, dlinfo.dli_fname, &image));
    XCTAssertTrue(image.crashInfoMessage == NULL);

    g_testCrashInfo.version = original;
}

- (void)testReadCrashInfoFromTaskImageWithoutSection
{
    // Find an image with no __crash_info section (using the in-process reader as the oracle)
    // and check the cross-task reader agrees.
    uint32_t count = 0;
    const ks_dyld_image_info *images = ksbic_getImages(&count);
    for (uint32_t i = 0; i < count; i++) {
        KSBinaryImage image = { 0 };
        if (!ksdl_binaryImageForHeader(images[i].imageLoadAddress, images[i].imageFilePath, &image)) {
            continue;
        }
        if (image.crashInfoMessage != NULL || image.crashInfoMessage2 != NULL || image.crashInfoBacktrace != NULL ||
            image.crashInfoSignature != NULL) {
            continue;
        }
        KSCrashInfoStrings strings = { 0 };
        XCTAssertFalse(
            ksdl_readCrashInfoFromTaskImage(mach_task_self(), (uintptr_t)images[i].imageLoadAddress, &strings));
        return;
    }
    XCTFail(@"No image without crash info found");
}

- (void)testReadCrashInfoFromTaskImageBogusAddress
{
    KSCrashInfoStrings strings = { 0 };
    XCTAssertFalse(ksdl_readCrashInfoFromTaskImage(mach_task_self(), 0x1000, &strings));
    XCTAssertEqual(strings.message, NULL);
}

@end
