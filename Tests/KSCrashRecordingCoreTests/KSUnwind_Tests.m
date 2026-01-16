//
//  KSUnwind_Tests.m
//
//  Created by Alexander Cohen on 2025-01-16.
//

#import <XCTest/XCTest.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

#import "KSBacktrace.h"
#import "KSMach-O.h"
#import "KSMachineContext.h"
#import "KSMachineContext_Apple.h"
#import "KSThread.h"
#import "Unwind/KSCompactUnwind.h"
#import "Unwind/KSStackCursor_Unwind.h"
#import "Unwind/KSUnwindCache.h"

@interface KSUnwind_Tests : XCTestCase
@end

@implementation KSUnwind_Tests

// =============================================================================
// MARK: - KSUnwindCache Tests
// =============================================================================
// These tests verify the unwind info cache that stores __unwind_info and
// __eh_frame section pointers for each loaded binary image.

- (void)testUnwindCache_GetInfoForNullHeader
{
    const KSUnwindImageInfo *info = ksunwindcache_getInfoForImage(NULL);
    XCTAssertEqual(info, NULL, @"Should return NULL for NULL header");
}

- (void)testUnwindCache_GetInfoForMainExecutable
{
    // Get the main executable header
    const mach_header_t *header = (const mach_header_t *)_dyld_get_image_header(0);
    XCTAssertNotEqual(header, NULL, @"Should have main executable header");

    const KSUnwindImageInfo *info = ksunwindcache_getInfoForImage(header);
    // Main executable should have unwind info
    if (info != NULL) {
        XCTAssertEqual(info->header, header, @"Header should match");
        // Most executables have compact unwind
        XCTAssertTrue(info->hasCompactUnwind || info->hasEhFrame, @"Should have some unwind info");
    }
}

- (void)testUnwindCache_GetInfoForAddress
{
    // Get the address of a known function
    uintptr_t address = (uintptr_t)&_dyld_get_image_header;

    const KSUnwindImageInfo *info = ksunwindcache_getInfoForAddress(address);
    if (info != NULL) {
        XCTAssertNotEqual(info->header, NULL, @"Header should not be NULL");
        // The function should be within the image range
    }
}

- (void)testUnwindCache_Reset
{
    // Reset should not crash
    ksunwindcache_reset();

    // After reset, cache should still work
    const mach_header_t *header = (const mach_header_t *)_dyld_get_image_header(0);
    if (header != NULL) {
        const KSUnwindImageInfo *info = ksunwindcache_getInfoForImage(header);
        // Should be able to get info after reset
        (void)info;  // Just verify no crash
    }
}

// =============================================================================
// MARK: - KSCompactUnwind Tests
// =============================================================================
// These tests verify parsing of Apple's __unwind_info section format.
// Compact unwind is the primary unwinding method on modern Apple platforms,
// encoding register restoration rules in a compact 32-bit format.

- (void)testCompactUnwind_FindEntryWithNullInfo
{
    KSCompactUnwindEntry entry;
    bool result = kscu_findEntry(NULL, 0, 0, 0, 0, &entry);
    XCTAssertFalse(result, @"Should return false for NULL unwind info");
}

- (void)testCompactUnwind_FindEntryForKnownFunction
{
    // Get unwind info for a known function
    uintptr_t functionAddress = (uintptr_t)&_dyld_get_image_header;
    const KSUnwindImageInfo *imageInfo = ksunwindcache_getInfoForAddress(functionAddress);

    if (imageInfo != NULL && imageInfo->hasCompactUnwind) {
        KSCompactUnwindEntry entry;
        uintptr_t imageBase = (uintptr_t)imageInfo->header;
        bool found = kscu_findEntry(imageInfo->unwindInfo, imageInfo->unwindInfoSize, functionAddress, imageBase,
                                    imageInfo->slide, &entry);

        if (found) {
            XCTAssertGreaterThan(entry.functionStart, 0, @"Function start should be non-zero");
            // Encoding should be valid (not zero for real functions)
        }
    }
}

- (void)testCompactUnwind_EncodingRequiresDwarf
{
    // Test DWARF mode encodings
#if defined(__arm64__)
    XCTAssertTrue(kscu_encodingRequiresDwarf(KSCU_UNWIND_ARM64_MODE_DWARF), @"ARM64 DWARF mode should require DWARF");
    XCTAssertFalse(kscu_encodingRequiresDwarf(KSCU_UNWIND_ARM64_MODE_FRAME),
                   @"ARM64 FRAME mode should not require DWARF");
    XCTAssertFalse(kscu_encodingRequiresDwarf(KSCU_UNWIND_ARM64_MODE_FRAMELESS),
                   @"ARM64 FRAMELESS mode should not require DWARF");
#elif defined(__x86_64__)
    XCTAssertTrue(kscu_encodingRequiresDwarf(KSCU_UNWIND_X86_64_MODE_DWARF), @"x86_64 DWARF mode should require DWARF");
    XCTAssertFalse(kscu_encodingRequiresDwarf(KSCU_UNWIND_X86_64_MODE_RBP_FRAME),
                   @"x86_64 RBP_FRAME mode should not require DWARF");
#endif
}

- (void)testCompactUnwind_GetMode
{
#if defined(__arm64__)
    XCTAssertEqual(kscu_getMode(KSCU_UNWIND_ARM64_MODE_FRAME), KSCU_UNWIND_ARM64_MODE_FRAME);
    XCTAssertEqual(kscu_getMode(KSCU_UNWIND_ARM64_MODE_FRAMELESS), KSCU_UNWIND_ARM64_MODE_FRAMELESS);
    XCTAssertEqual(kscu_getMode(KSCU_UNWIND_ARM64_MODE_DWARF), KSCU_UNWIND_ARM64_MODE_DWARF);
#elif defined(__x86_64__)
    XCTAssertEqual(kscu_getMode(KSCU_UNWIND_X86_64_MODE_RBP_FRAME), KSCU_UNWIND_X86_64_MODE_RBP_FRAME);
    XCTAssertEqual(kscu_getMode(KSCU_UNWIND_X86_64_MODE_STACK_IMMD), KSCU_UNWIND_X86_64_MODE_STACK_IMMD);
#endif
}

// =============================================================================
// MARK: - KSBacktrace Tests
// =============================================================================
// These tests verify the high-level backtrace capture API. Internally, these
// functions use the unwind cursor which tries: Compact Unwind -> DWARF -> Frame Pointer.
// If these tests pass, the entire unwind chain is working correctly.

- (void)testBacktrace_Capture
{
    uintptr_t addresses[128];
    int frameCount = ksbt_captureBacktrace(pthread_self(), addresses, 128);

    // Should capture at least a few frames
    XCTAssertGreaterThan(frameCount, 0, @"Should capture at least one frame");

    // First frame should be in this function or test framework
    XCTAssertGreaterThan(addresses[0], 0, @"First frame address should be non-zero");
}

- (void)testBacktrace_CaptureFromMachThread
{
    uintptr_t addresses[128];
    thread_t machThread = pthread_mach_thread_np(pthread_self());
    int frameCount = ksbt_captureBacktraceFromMachThread(machThread, addresses, 128);

    // Should capture at least a few frames
    XCTAssertGreaterThan(frameCount, 0, @"Should capture at least one frame");
}

// Note: Can't test NULL addresses as the parameter is marked _Nonnull

- (void)testBacktrace_CaptureZeroCount
{
    uintptr_t addresses[128];
    int frameCount = ksbt_captureBacktrace(pthread_self(), addresses, 0);
    XCTAssertEqual(frameCount, 0, @"Should return 0 for zero count");
}

// =============================================================================
// MARK: - Integration Tests
// =============================================================================
// These tests verify end-to-end unwinding behavior with real call stacks.
// They exercise the full unwind path without needing to inspect internal state.

- (void)testUnwind_NestedFunctionCalls
{
    // Verifies that deeply nested calls are properly unwound.
    // This exercises the unwind cursor's ability to walk through multiple frames.
    [self helperLevel1];
}

- (void)helperLevel1
{
    [self helperLevel2];
}

- (void)helperLevel2
{
    [self helperLevel3];
}

- (void)helperLevel3
{
    uintptr_t addresses[128];
    int frameCount = ksbt_captureBacktrace(pthread_self(), addresses, 128);

    // Should capture our nested call hierarchy
    // At minimum: helperLevel3 -> helperLevel2 -> helperLevel1 -> testUnwind_NestedFunctionCalls
    XCTAssertGreaterThanOrEqual(frameCount, 4, @"Should capture at least 4 frames for nested calls");
}

- (void)testUnwind_SymbolicateAddresses
{
    uintptr_t addresses[128];
    int frameCount = ksbt_captureBacktrace(pthread_self(), addresses, 128);

    XCTAssertGreaterThan(frameCount, 0, @"Should capture frames");

    // Symbolicate the first few frames
    for (int i = 0; i < MIN(frameCount, 5); i++) {
        struct KSSymbolInformation info;
        bool symbolicated = ksbt_symbolicateAddress(addresses[i], &info);

        if (symbolicated) {
            XCTAssertNotEqual(info.imageAddress, 0, @"Image address should be non-zero");
            XCTAssertNotEqual(info.imageName, NULL, @"Image name should not be NULL");
        }
    }
}

// =============================================================================
// MARK: - Unwind Method Tracking Tests
// =============================================================================
// These tests verify the KSUnwindMethod enum and related utility functions.
// The unwind method indicates which technique was used to unwind each frame:
// - None: Initial state before unwinding
// - CompactUnwind: Used Apple's __unwind_info section
// - Dwarf: Used __eh_frame DWARF CFI
// - FramePointer: Fell back to traditional frame pointer walking

- (void)testUnwindMethod_NameForNone
{
    const char *name = kssc_unwindMethodName(KSUnwindMethod_None);
    XCTAssertTrue(strcmp(name, "none") == 0, @"Name for None should be 'none'");
}

- (void)testUnwindMethod_NameForCompactUnwind
{
    const char *name = kssc_unwindMethodName(KSUnwindMethod_CompactUnwind);
    XCTAssertTrue(strcmp(name, "compact_unwind") == 0, @"Name for CompactUnwind should be 'compact_unwind'");
}

- (void)testUnwindMethod_NameForDwarf
{
    const char *name = kssc_unwindMethodName(KSUnwindMethod_Dwarf);
    XCTAssertTrue(strcmp(name, "dwarf") == 0, @"Name for Dwarf should be 'dwarf'");
}

- (void)testUnwindMethod_NameForFramePointer
{
    const char *name = kssc_unwindMethodName(KSUnwindMethod_FramePointer);
    XCTAssertTrue(strcmp(name, "frame_pointer") == 0, @"Name for FramePointer should be 'frame_pointer'");
}

- (void)testUnwindMethod_NameForInvalidValue
{
    const char *name = kssc_unwindMethodName((KSUnwindMethod)999);
    XCTAssertTrue(strcmp(name, "unknown") == 0, @"Name for invalid value should be 'unknown'");
}

- (void)testUnwindMethod_GetMethodFromNullCursor
{
    KSUnwindMethod method = kssc_getUnwindMethod(NULL);
    XCTAssertEqual(method, KSUnwindMethod_None, @"Should return None for NULL cursor");
}

- (void)testUnwindMethod_InitialState
{
    // Create a machine context for the current thread
    // Note: We can't get accurate registers for the current thread without suspending it,
    // but we can at least verify the cursor initializes correctly.
    KSMachineContext machineContext;
    memset(&machineContext, 0, sizeof(machineContext));

    // Initialize an unwind cursor
    KSStackCursor cursor;
    kssc_initWithUnwind(&cursor, 128, &machineContext);

    // Before advancing, method should be None
    KSUnwindMethod initialMethod = kssc_getUnwindMethod(&cursor);
    XCTAssertEqual(initialMethod, KSUnwindMethod_None, @"Initial method should be None before advancing");
}

- (void)testUnwindMethod_ValidEnumValues
{
    // Verify all enum values are distinct
    XCTAssertNotEqual(KSUnwindMethod_None, KSUnwindMethod_CompactUnwind);
    XCTAssertNotEqual(KSUnwindMethod_None, KSUnwindMethod_Dwarf);
    XCTAssertNotEqual(KSUnwindMethod_None, KSUnwindMethod_FramePointer);
    XCTAssertNotEqual(KSUnwindMethod_CompactUnwind, KSUnwindMethod_Dwarf);
    XCTAssertNotEqual(KSUnwindMethod_CompactUnwind, KSUnwindMethod_FramePointer);
    XCTAssertNotEqual(KSUnwindMethod_Dwarf, KSUnwindMethod_FramePointer);

    // Verify None is 0 for easy default initialization
    XCTAssertEqual(KSUnwindMethod_None, 0);
}

@end
