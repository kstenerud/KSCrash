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
#import "Unwind/KSDwarfUnwind.h"
#import "Unwind/KSStackCursor_Unwind.h"
#import "Unwind/KSUnwindCache.h"

static void ks_dwarf_test_helper(void) __attribute__((noinline));
static void ks_dwarf_test_helper(void) {}

static void writeU32LE(uint8_t *dst, uint32_t value)
{
    dst[0] = (uint8_t)(value & 0xFF);
    dst[1] = (uint8_t)((value >> 8) & 0xFF);
    dst[2] = (uint8_t)((value >> 16) & 0xFF);
    dst[3] = (uint8_t)((value >> 24) & 0xFF);
}

static void writeU64LE(uint8_t *dst, uint64_t value)
{
    dst[0] = (uint8_t)(value & 0xFF);
    dst[1] = (uint8_t)((value >> 8) & 0xFF);
    dst[2] = (uint8_t)((value >> 16) & 0xFF);
    dst[3] = (uint8_t)((value >> 24) & 0xFF);
    dst[4] = (uint8_t)((value >> 32) & 0xFF);
    dst[5] = (uint8_t)((value >> 40) & 0xFF);
    dst[6] = (uint8_t)((value >> 48) & 0xFF);
    dst[7] = (uint8_t)((value >> 56) & 0xFF);
}

static void appendU8(uint8_t *buf, size_t *offset, uint8_t value) { buf[(*offset)++] = value; }

static void appendULEB(uint8_t *buf, size_t *offset, uint64_t value)
{
    do {
        uint8_t byte = (uint8_t)(value & 0x7F);
        value >>= 7;
        if (value != 0) {
            byte |= 0x80;
        }
        buf[(*offset)++] = byte;
    } while (value != 0);
}

static void appendSLEB(uint8_t *buf, size_t *offset, int64_t value)
{
    bool more = true;
    while (more) {
        uint8_t byte = (uint8_t)(value & 0x7F);
        value >>= 7;
        bool signBitSet = (byte & 0x40) != 0;
        if ((value == 0 && !signBitSet) || (value == -1 && signBitSet)) {
            more = false;
        } else {
            byte |= 0x80;
        }
        buf[(*offset)++] = byte;
    }
}

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

// =============================================================================
// MARK: - x86_64 Frameless Compact Unwind Tests
// =============================================================================
// These tests verify the frameless stack size handling for x86_64.
// The encoded stack size represents the `sub rsp, X` immediate value,
// EXCLUDING the return address pushed by CALL.

#if defined(__x86_64__)

- (void)testCompactUnwind_x86_64_FramelessLeaf
{
    // Test: encodedSize=0 means leaf function where return address is at [RSP]
    // Expected: RA read from [RSP], new SP = RSP + 8

    // Encoding: STACK_IMMD mode with stack size = 0
    compact_unwind_encoding_t encoding = KSCU_UNWIND_X86_64_MODE_STACK_IMMD;
    // Stack size field (bits 16-23) = 0, so no additional bits needed

    // Create mock stack: return address at index 0
    uintptr_t mockStack[4];
    mockStack[0] = 0xDEADBEEFCAFEBABE;  // Return address at [SP]
    mockStack[1] = 0x1111111111111111;  // Padding
    mockStack[2] = 0x2222222222222222;  // Padding

    uintptr_t sp = (uintptr_t)&mockStack[0];
    uintptr_t bp = 0;  // No base pointer for frameless

    KSCompactUnwindResult result;
    bool success = kscu_x86_64_decode(encoding, 0x1000, sp, bp, &result);

    XCTAssertTrue(success, @"Frameless leaf decode should succeed");
    XCTAssertTrue(result.valid, @"Result should be valid");
    XCTAssertEqual(result.returnAddress, 0xDEADBEEFCAFEBABE, @"Return address should be read from [RSP]");
    XCTAssertEqual(result.stackPointer, (uintptr_t)&mockStack[1], @"New SP should be RSP + 8");
}

- (void)testCompactUnwind_x86_64_FramelessNonLeaf
{
    // Test: encodedSize=2 means `sub rsp, 16` was executed
    // Stack layout (from low to high address):
    //   [RSP+0]  = local variable 1
    //   [RSP+8]  = local variable 2
    //   [RSP+16] = return address (pushed by CALL before SUB)
    // Total frame = encodedSize*8 + 8 = 16 + 8 = 24
    // RA at RSP + 24 - 8 = RSP + 16

    // Encoding: STACK_IMMD mode with stack size = 2 (meaning 2*8 = 16 bytes)
    compact_unwind_encoding_t encoding =
        KSCU_UNWIND_X86_64_MODE_STACK_IMMD | (2 << KSCU_UNWIND_X86_64_FRAMELESS_STACK_SIZE_SHIFT);

    // Create mock stack
    uintptr_t mockStack[8];
    mockStack[0] = 0x1111111111111111;  // Local var at [SP+0]
    mockStack[1] = 0x2222222222222222;  // Local var at [SP+8]
    mockStack[2] = 0xDEADBEEFCAFEBABE;  // Return address at [SP+16]
    mockStack[3] = 0x3333333333333333;  // Caller's stack

    uintptr_t sp = (uintptr_t)&mockStack[0];
    uintptr_t bp = 0;

    KSCompactUnwindResult result;
    bool success = kscu_x86_64_decode(encoding, 0x1000, sp, bp, &result);

    XCTAssertTrue(success, @"Frameless non-leaf decode should succeed");
    XCTAssertTrue(result.valid, @"Result should be valid");
    XCTAssertEqual(result.returnAddress, 0xDEADBEEFCAFEBABE, @"Return address should be at RSP+16");
    XCTAssertEqual(result.stackPointer, (uintptr_t)&mockStack[3], @"New SP should be RSP + 24");
}

- (void)testCompactUnwind_x86_64_FramelessLargerStack
{
    // Test: encodedSize=8 means `sub rsp, 64` was executed
    // RA at RSP + 64, new SP = RSP + 72

    compact_unwind_encoding_t encoding =
        KSCU_UNWIND_X86_64_MODE_STACK_IMMD | (8 << KSCU_UNWIND_X86_64_FRAMELESS_STACK_SIZE_SHIFT);

    // Create mock stack with 64 bytes of locals + return address
    uintptr_t mockStack[16];
    for (int i = 0; i < 8; i++) {
        mockStack[i] = 0x1000 + i;  // Local variables
    }
    mockStack[8] = 0xCAFEBABE12345678;  // Return address at [SP+64]
    mockStack[9] = 0x9999999999999999;  // Caller's stack

    uintptr_t sp = (uintptr_t)&mockStack[0];

    KSCompactUnwindResult result;
    bool success = kscu_x86_64_decode(encoding, 0x1000, sp, 0, &result);

    XCTAssertTrue(success, @"Frameless with larger stack should succeed");
    XCTAssertEqual(result.returnAddress, 0xCAFEBABE12345678, @"Return address should be at RSP+64");
    XCTAssertEqual(result.stackPointer, (uintptr_t)&mockStack[9], @"New SP should be RSP + 72");
}

#endif  // __x86_64__

// =============================================================================
// MARK: - x86 (32-bit) Frameless Compact Unwind Tests
// =============================================================================

#if defined(__i386__)

- (void)testCompactUnwind_x86_FramelessLeaf
{
    // Test: encodedSize=0 means leaf function where return address is at [ESP]
    // Expected: RA read from [ESP], new SP = ESP + 4

    compact_unwind_encoding_t encoding = KSCU_UNWIND_X86_MODE_STACK_IMMD;

    // Create mock stack
    uint32_t mockStack[4];
    mockStack[0] = 0xDEADBEEF;  // Return address at [SP]
    mockStack[1] = 0x11111111;  // Padding

    uintptr_t sp = (uintptr_t)&mockStack[0];

    KSCompactUnwindResult result;
    bool success = kscu_x86_decode(encoding, 0x1000, sp, 0, &result);

    XCTAssertTrue(success, @"Frameless leaf decode should succeed");
    XCTAssertTrue(result.valid, @"Result should be valid");
    XCTAssertEqual(result.returnAddress, 0xDEADBEEF, @"Return address should be read from [ESP]");
    XCTAssertEqual(result.stackPointer, (uintptr_t)&mockStack[1], @"New SP should be ESP + 4");
}

- (void)testCompactUnwind_x86_FramelessNonLeaf
{
    // Test: encodedSize=4 means `sub esp, 16` was executed
    // RA at ESP + 16, new SP = ESP + 20

    compact_unwind_encoding_t encoding =
        KSCU_UNWIND_X86_MODE_STACK_IMMD | (4 << KSCU_UNWIND_X86_FRAMELESS_STACK_SIZE_SHIFT);

    // Create mock stack
    uint32_t mockStack[8];
    mockStack[0] = 0x11111111;  // Local at [SP+0]
    mockStack[1] = 0x22222222;  // Local at [SP+4]
    mockStack[2] = 0x33333333;  // Local at [SP+8]
    mockStack[3] = 0x44444444;  // Local at [SP+12]
    mockStack[4] = 0xDEADBEEF;  // Return address at [SP+16]
    mockStack[5] = 0x55555555;  // Caller's stack

    uintptr_t sp = (uintptr_t)&mockStack[0];

    KSCompactUnwindResult result;
    bool success = kscu_x86_decode(encoding, 0x1000, sp, 0, &result);

    XCTAssertTrue(success, @"Frameless non-leaf decode should succeed");
    XCTAssertEqual(result.returnAddress, 0xDEADBEEF, @"Return address should be at ESP+16");
    XCTAssertEqual(result.stackPointer, (uintptr_t)&mockStack[5], @"New SP should be ESP + 20");
}

#endif  // __i386__

// =============================================================================
// MARK: - DWARF CFI Instruction Tests
// =============================================================================
// These tests verify DWARF CFI parsing using synthetic .eh_frame data.
// They test specific CFI instructions that need coverage.

- (void)testDwarf_BuildCFIRow_OffsetWithNegativeDataAlign
{
    // Test: DW_CFA_offset with positive ULEB128 operand and negative data alignment factor
    // On x86_64, data_alignment_factor is typically -8
    // DW_CFA_offset r6, 1 with data_align=-8 should produce offset = 1 * -8 = -8
    //
    // This tests that the DWARF parser correctly handles negative data alignment
    // factors, which are common on x86_64 where saved registers are below the CFA.
    //
    // Note: We use 'zR' augmentation to specify DW_EH_PE_udata4 (0x03) pointer encoding
    // so that PC values use 4 bytes regardless of platform word size.

    const uint8_t cieData[] = {
        // CIE ID = 0 (this is a CIE)
        0x00, 0x00, 0x00, 0x00,
        // Version = 3
        0x03,
        // Augmentation = "zR" (null terminated) - enables pointer encoding
        'z', 'R', 0x00,
        // Code alignment factor = 1 (ULEB128)
        0x01,
        // Data alignment factor = -8 (SLEB128: 0x78)
        0x78,
        // Return address register = 16 (ULEB128)
        0x10,
        // Augmentation data length = 1 (ULEB128)
        0x01,
        // FDE pointer encoding = DW_EH_PE_udata4 (0x03) - 4-byte unsigned
        0x03,
        // Initial instructions:
        0x0C, 0x07, 0x08,  // DW_CFA_def_cfa r7, 8
        0x86, 0x01,        // DW_CFA_offset r6, 1 (offset = 1 * -8 = -8)
    };
    size_t cieSize = sizeof(cieData);

    const uint8_t fdeData[] = {
        // CIE pointer (placeholder, not used in buildCFIRow)
        0x00, 0x00, 0x00, 0x00,
        // PC start = 0x1000 (4 bytes, little-endian, per udata4 encoding)
        0x00, 0x10, 0x00, 0x00,
        // PC range = 0x100 (4 bytes, per udata4 encoding)
        0x00, 0x01, 0x00, 0x00,
        // Augmentation data length = 0 (no LSDA since no 'L' in augmentation)
        0x00,
        // No additional FDE instructions
    };
    size_t fdeSize = sizeof(fdeData);

    KSDwarfCFIRow row;
    bool success = ksdwarf_buildCFIRow(cieData, cieSize, fdeData, fdeSize, 0x1000, false, &row);

    XCTAssertTrue(success, @"Building CFI row should succeed");
    XCTAssertEqual(row.cfaRegister, 7, @"CFA register should be r7");
    XCTAssertEqual(row.cfaOffset, 8, @"CFA offset should be 8");

    // Register 6 should have offset rule with value = 1 * -8 = -8
    XCTAssertEqual(row.registers[6].type, KSDwarfRuleOffset, @"Register 6 should have offset rule");
    XCTAssertEqual(row.registers[6].offset, -8, @"Register 6 offset should be -8 (1 * data_align)");
}

- (void)testDwarf_BuildCFIRow_RestoreOpcode
{
    // Test: DW_CFA_restore should restore a register to its initial CIE state
    //
    // CIE sets r6 to CFA-8
    // FDE advances, changes r6, then restores it
    // After restore, r6 should be back to CFA-8

    const uint8_t cieData[] = {
        0x00, 0x00, 0x00, 0x00,  // CIE ID = 0
        0x03,                    // Version = 3
        'z', 'R', 0x00,          // Augmentation = "zR"
        0x01,                    // Code alignment = 1
        0x78,                    // Data alignment = -8
        0x10,                    // RA register = 16
        0x01,                    // Augmentation data length = 1
        0x03,                    // FDE pointer encoding = DW_EH_PE_udata4
        // Initial instructions:
        0x0C, 0x07, 0x10,  // DW_CFA_def_cfa r7, 16
        0x86, 0x01,        // DW_CFA_offset r6, 1 (offset = -8)
    };
    size_t cieSize = sizeof(cieData);

    const uint8_t fdeData[] = {
        0x00, 0x00, 0x00, 0x00,  // CIE pointer
        0x00, 0x10, 0x00, 0x00,  // PC start = 0x1000 (udata4)
        0x00, 0x02, 0x00, 0x00,  // PC range = 0x200 (udata4)
        0x00,                    // Augmentation data length = 0
        // FDE instructions:
        0x41,        // DW_CFA_advance_loc 1 (PC = 0x1001)
        0x86, 0x02,  // DW_CFA_offset r6, 2 (change to offset = -16)
        0x41,        // DW_CFA_advance_loc 1 (PC = 0x1002)
        0xC6,        // DW_CFA_restore r6 (restore to CIE initial state)
    };
    size_t fdeSize = sizeof(fdeData);

    // Build row at PC 0x1003 (after restore)
    KSDwarfCFIRow row;
    bool success = ksdwarf_buildCFIRow(cieData, cieSize, fdeData, fdeSize, 0x1003, false, &row);

    XCTAssertTrue(success, @"Building CFI row should succeed");

    // After DW_CFA_restore, r6 should be back to its CIE initial state (offset = -8)
    XCTAssertEqual(row.registers[6].type, KSDwarfRuleOffset, @"Register 6 should have offset rule");
    XCTAssertEqual(row.registers[6].offset, -8, @"Register 6 should be restored to initial offset -8");
}

- (void)testDwarf_BuildCFIRow_RestoreExtendedOpcode
{
    // Test: DW_CFA_restore_extended for registers > 31
    // Uses ULEB128 encoding for register number

    const uint8_t cieData[] = {
        0x00, 0x00, 0x00, 0x00,  // CIE ID = 0
        0x03,                    // Version = 3
        'z', 'R', 0x00,          // Augmentation = "zR"
        0x01,                    // Code alignment = 1
        0x78,                    // Data alignment = -8
        0x10,                    // RA register = 16
        0x01,                    // Augmentation data length = 1
        0x03,                    // FDE pointer encoding = DW_EH_PE_udata4
        // Initial instructions:
        0x0C, 0x07, 0x10,  // DW_CFA_def_cfa r7, 16
        0x05, 0x20, 0x01,  // DW_CFA_offset_extended r32, 1 (offset = -8)
    };
    size_t cieSize = sizeof(cieData);

    const uint8_t fdeData[] = {
        0x00, 0x00, 0x00, 0x00,  // CIE pointer
        0x00, 0x10, 0x00, 0x00,  // PC start = 0x1000 (udata4)
        0x00, 0x02, 0x00, 0x00,  // PC range = 0x200 (udata4)
        0x00,                    // Augmentation data length = 0
        // FDE instructions:
        0x41,              // DW_CFA_advance_loc 1
        0x05, 0x20, 0x02,  // DW_CFA_offset_extended r32, 2 (change to -16)
        0x41,              // DW_CFA_advance_loc 1
        0x06, 0x20,        // DW_CFA_restore_extended r32
    };
    size_t fdeSize = sizeof(fdeData);

    KSDwarfCFIRow row;
    bool success = ksdwarf_buildCFIRow(cieData, cieSize, fdeData, fdeSize, 0x1003, false, &row);

    XCTAssertTrue(success, @"Building CFI row should succeed");
    XCTAssertEqual(row.registers[32].type, KSDwarfRuleOffset, @"Register 32 should have offset rule");
    XCTAssertEqual(row.registers[32].offset, -8, @"Register 32 should be restored to initial offset");
}

- (void)testDwarf_BuildCFIRow_RememberRestoreState
{
    // Test: DW_CFA_remember_state and DW_CFA_restore_state
    // These are used in functions with exception handling or complex control flow

    const uint8_t cieData[] = {
        0x00, 0x00, 0x00, 0x00,  // CIE ID = 0
        0x03,                    // Version = 3
        'z',  'R',  0x00,        // Augmentation = "zR"
        0x01,                    // Code alignment = 1
        0x78,                    // Data alignment = -8
        0x10,                    // RA register = 16
        0x01,                    // Augmentation data length = 1
        0x03,                    // FDE pointer encoding = DW_EH_PE_udata4
        0x0C, 0x07, 0x08,        // DW_CFA_def_cfa r7, 8
        0x86, 0x01,              // DW_CFA_offset r6, 1 (offset = -8)
    };
    size_t cieSize = sizeof(cieData);

    const uint8_t fdeData[] = {
        0x00, 0x00, 0x00, 0x00,  // CIE pointer
        0x00, 0x10, 0x00, 0x00,  // PC start = 0x1000 (udata4)
        0x00, 0x04, 0x00, 0x00,  // PC range = 0x400 (udata4)
        0x00,                    // Augmentation data length = 0
        // FDE instructions:
        0x41,        // DW_CFA_advance_loc 1 (PC = 0x1001)
        0x0A,        // DW_CFA_remember_state (save current state)
        0x41,        // DW_CFA_advance_loc 1 (PC = 0x1002)
        0x86, 0x03,  // DW_CFA_offset r6, 3 (change to offset = -24)
        0x0E, 0x20,  // DW_CFA_def_cfa_offset 32 (change CFA offset)
        0x41,        // DW_CFA_advance_loc 1 (PC = 0x1003)
        0x0B,        // DW_CFA_restore_state (restore saved state)
    };
    size_t fdeSize = sizeof(fdeData);

    // Build row at PC 0x1004 (after restore_state)
    KSDwarfCFIRow row;
    bool success = ksdwarf_buildCFIRow(cieData, cieSize, fdeData, fdeSize, 0x1004, false, &row);

    XCTAssertTrue(success, @"Building CFI row should succeed");

    // After restore_state, should be back to state at remember_state
    XCTAssertEqual(row.cfaOffset, 8, @"CFA offset should be restored to 8");
    XCTAssertEqual(row.registers[6].offset, -8, @"Register 6 should be restored to offset -8");
}

// =============================================================================
// MARK: - DWARF Expression Evaluation Tests
// =============================================================================

- (void)testDwarf_Unwind_ExpressionRule
{
#if defined(__arm64__)
    const uint8_t raReg = KSDWARF_ARM64_LR;
    const uint8_t cfaReg = KSDWARF_ARM64_SP;
#elif defined(__x86_64__)
    const uint8_t raReg = KSDWARF_X86_64_RIP;
    const uint8_t cfaReg = KSDWARF_X86_64_RSP;
#elif defined(__arm__)
    const uint8_t raReg = KSDWARF_ARM_R14;
    const uint8_t cfaReg = KSDWARF_ARM_R13;
#elif defined(__i386__)
    const uint8_t raReg = KSDWARF_X86_EIP;
    const uint8_t cfaReg = KSDWARF_X86_ESP;
#else
    XCTSkip(@"Unsupported architecture for DWARF expression test");
    return;
#endif

    const uint8_t ptrSize = (uint8_t)sizeof(uintptr_t);

    uint8_t cieContent[64];
    size_t cieLen = 0;
    appendU8(cieContent, &cieLen, 0x00);
    appendU8(cieContent, &cieLen, 0x00);
    appendU8(cieContent, &cieLen, 0x00);
    appendU8(cieContent, &cieLen, 0x00);  // CIE ID = 0
    appendU8(cieContent, &cieLen, 0x03);  // Version = 3
    appendU8(cieContent, &cieLen, 'z');
    appendU8(cieContent, &cieLen, 'R');
    appendU8(cieContent, &cieLen, 0x00);                 // Augmentation string
    appendULEB(cieContent, &cieLen, 1);                  // Code alignment factor
    appendSLEB(cieContent, &cieLen, -(int64_t)ptrSize);  // Data alignment factor
    appendULEB(cieContent, &cieLen, raReg);              // Return address register
    appendULEB(cieContent, &cieLen, 1);                  // Augmentation data length
    appendU8(cieContent, &cieLen, 0x03);                 // DW_EH_PE_udata4
    appendU8(cieContent, &cieLen, 0x0C);                 // DW_CFA_def_cfa
    appendULEB(cieContent, &cieLen, cfaReg);
    appendULEB(cieContent, &cieLen, ptrSize);

    // Expression: CFA + ptrSize = address where RA is stored
    // DW_CFA_expression produces an address; applyRegisterRule does the final deref
    uint8_t expr[8];
    size_t exprLen = 0;
    appendU8(expr, &exprLen, 0x9C);  // DW_OP_call_frame_cfa
    appendU8(expr, &exprLen, 0x23);  // DW_OP_plus_uconst
    appendULEB(expr, &exprLen, ptrSize);

    uint8_t fdeContent[64];
    size_t fdeLen = 0;
    appendU8(fdeContent, &fdeLen, 0x00);
    appendU8(fdeContent, &fdeLen, 0x00);
    appendU8(fdeContent, &fdeLen, 0x00);
    appendU8(fdeContent, &fdeLen, 0x00);  // CIE pointer (patched later)
    writeU32LE(&fdeContent[fdeLen], 0x1000);
    fdeLen += 4;
    writeU32LE(&fdeContent[fdeLen], 0x10);
    fdeLen += 4;
    appendU8(fdeContent, &fdeLen, 0x00);  // Augmentation data length
    appendU8(fdeContent, &fdeLen, 0x10);  // DW_CFA_expression
    appendULEB(fdeContent, &fdeLen, raReg);
    appendULEB(fdeContent, &fdeLen, exprLen);
    memcpy(&fdeContent[fdeLen], expr, exprLen);
    fdeLen += exprLen;

    uint8_t ehFrame[256];
    size_t ehLen = 0;
    writeU32LE(&ehFrame[ehLen], (uint32_t)cieLen);
    ehLen += 4;
    memcpy(&ehFrame[ehLen], cieContent, cieLen);
    ehLen += cieLen;
    writeU32LE(&ehFrame[ehLen], (uint32_t)fdeLen);
    ehLen += 4;
    size_t fdeStart = ehLen;
    memcpy(&ehFrame[ehLen], fdeContent, fdeLen);
    ehLen += fdeLen;
    writeU32LE(&ehFrame[ehLen], 0x00);  // Terminator
    ehLen += 4;

    writeU32LE(&ehFrame[fdeStart], (uint32_t)(fdeStart));

    // Stack layout:
    // stack[0] = sp (unused)
    // stack[1] = CFA = sp + ptrSize
    // stack[2] = expression result address (CFA + ptrSize), stores expectedRA
    uintptr_t stack[4] = { 0 };
#if __LP64__
    uintptr_t expectedRA = (uintptr_t)0xDEADBEEFCAFEBABEULL;
#else
    uintptr_t expectedRA = (uintptr_t)0xDEADBEEF;
#endif
    stack[2] = expectedRA;
    uintptr_t sp = (uintptr_t)&stack[0];

    KSDwarfUnwindResult result;
    bool success = ksdwarf_unwind(ehFrame, ehLen, 0x1000, sp, 0, 0, 0, &result);
    XCTAssertTrue(success, @"DWARF unwind with expression should succeed");
    XCTAssertTrue(result.valid, @"Result should be valid");
    XCTAssertEqual(result.returnAddress, expectedRA, @"Return address should be loaded via expression");
    XCTAssertEqual(result.stackPointer, sp + ptrSize, @"CFA should be SP + ptrSize");
}

- (void)testDwarf_Unwind_CFAExpression
{
#if defined(__arm64__)
    const uint8_t raReg = KSDWARF_ARM64_LR;
    const uint8_t cfaReg = KSDWARF_ARM64_SP;
#elif defined(__x86_64__)
    const uint8_t raReg = KSDWARF_X86_64_RIP;
    const uint8_t cfaReg = KSDWARF_X86_64_RSP;
#elif defined(__arm__)
    const uint8_t raReg = KSDWARF_ARM_R14;
    const uint8_t cfaReg = KSDWARF_ARM_R13;
#elif defined(__i386__)
    const uint8_t raReg = KSDWARF_X86_EIP;
    const uint8_t cfaReg = KSDWARF_X86_ESP;
#else
    XCTSkip(@"Unsupported architecture for CFA expression test");
    return;
#endif

    const uint8_t ptrSize = (uint8_t)sizeof(uintptr_t);

    uint8_t cfaExpr[8];
    size_t cfaExprLen = 0;
    appendU8(cfaExpr, &cfaExprLen, (uint8_t)(0x70 + cfaReg));  // DW_OP_breg0 + cfaReg
    appendSLEB(cfaExpr, &cfaExprLen, (int64_t)ptrSize);

    uint8_t cieContent[64];
    size_t cieLen = 0;
    appendU8(cieContent, &cieLen, 0x00);
    appendU8(cieContent, &cieLen, 0x00);
    appendU8(cieContent, &cieLen, 0x00);
    appendU8(cieContent, &cieLen, 0x00);  // CIE ID = 0
    appendU8(cieContent, &cieLen, 0x03);  // Version = 3
    appendU8(cieContent, &cieLen, 'z');
    appendU8(cieContent, &cieLen, 'R');
    appendU8(cieContent, &cieLen, 0x00);  // Augmentation string
    appendULEB(cieContent, &cieLen, 1);   // Code alignment factor
    appendSLEB(cieContent, &cieLen, 1);   // Data alignment factor
    appendULEB(cieContent, &cieLen, raReg);
    appendULEB(cieContent, &cieLen, 1);   // Augmentation data length
    appendU8(cieContent, &cieLen, 0x03);  // DW_EH_PE_udata4
    appendU8(cieContent, &cieLen, 0x0F);  // DW_CFA_def_cfa_expression
    appendULEB(cieContent, &cieLen, cfaExprLen);
    memcpy(&cieContent[cieLen], cfaExpr, cfaExprLen);
    cieLen += cfaExprLen;

    uint8_t fdeContent[32];
    size_t fdeLen = 0;
    appendU8(fdeContent, &fdeLen, 0x00);
    appendU8(fdeContent, &fdeLen, 0x00);
    appendU8(fdeContent, &fdeLen, 0x00);
    appendU8(fdeContent, &fdeLen, 0x00);  // CIE pointer (patched later)
    writeU32LE(&fdeContent[fdeLen], 0x1000);
    fdeLen += 4;
    writeU32LE(&fdeContent[fdeLen], 0x10);
    fdeLen += 4;
    appendU8(fdeContent, &fdeLen, 0x00);                     // Augmentation data length
    appendU8(fdeContent, &fdeLen, (uint8_t)(0x80 | raReg));  // DW_CFA_offset
    appendULEB(fdeContent, &fdeLen, 0);

    uint8_t ehFrame[256];
    size_t ehLen = 0;
    writeU32LE(&ehFrame[ehLen], (uint32_t)cieLen);
    ehLen += 4;
    memcpy(&ehFrame[ehLen], cieContent, cieLen);
    ehLen += cieLen;
    writeU32LE(&ehFrame[ehLen], (uint32_t)fdeLen);
    ehLen += 4;
    size_t fdeStart = ehLen;
    memcpy(&ehFrame[ehLen], fdeContent, fdeLen);
    ehLen += fdeLen;
    writeU32LE(&ehFrame[ehLen], 0x00);  // Terminator
    ehLen += 4;

    writeU32LE(&ehFrame[fdeStart], (uint32_t)(fdeStart));

    uintptr_t stack[2] = { 0 };
    uintptr_t expectedRA = (uintptr_t)0xABCDEF01;
    stack[1] = expectedRA;
    uintptr_t sp = (uintptr_t)&stack[0];

    KSDwarfUnwindResult result;
    bool success = ksdwarf_unwind(ehFrame, ehLen, 0x1000, sp, 0, 0, 0, &result);
    XCTAssertTrue(success, @"DWARF unwind with CFA expression should succeed");
    XCTAssertTrue(result.valid, @"Result should be valid");
    XCTAssertEqual(result.returnAddress, expectedRA, @"Return address should be loaded at CFA");
    XCTAssertEqual(result.stackPointer, sp + ptrSize, @"CFA should be SP + ptrSize");
}

- (void)testDwarf_Unwind_ExpressionStackValue
{
#if defined(__arm64__)
    const uint8_t raReg = KSDWARF_ARM64_LR;
    const uint8_t cfaReg = KSDWARF_ARM64_SP;
#elif defined(__x86_64__)
    const uint8_t raReg = KSDWARF_X86_64_RIP;
    const uint8_t cfaReg = KSDWARF_X86_64_RSP;
#elif defined(__arm__)
    const uint8_t raReg = KSDWARF_ARM_R14;
    const uint8_t cfaReg = KSDWARF_ARM_R13;
#elif defined(__i386__)
    const uint8_t raReg = KSDWARF_X86_EIP;
    const uint8_t cfaReg = KSDWARF_X86_ESP;
#else
    XCTSkip(@"Unsupported architecture for DWARF stack_value test");
    return;
#endif

    const uint8_t ptrSize = (uint8_t)sizeof(uintptr_t);
    const uintptr_t expectedRA = (uintptr_t)0x12345678;

    uint8_t cieContent[64];
    size_t cieLen = 0;
    appendU8(cieContent, &cieLen, 0x00);
    appendU8(cieContent, &cieLen, 0x00);
    appendU8(cieContent, &cieLen, 0x00);
    appendU8(cieContent, &cieLen, 0x00);  // CIE ID = 0
    appendU8(cieContent, &cieLen, 0x03);  // Version = 3
    appendU8(cieContent, &cieLen, 'z');
    appendU8(cieContent, &cieLen, 'R');
    appendU8(cieContent, &cieLen, 0x00);  // Augmentation string
    appendULEB(cieContent, &cieLen, 1);   // Code alignment factor
    appendSLEB(cieContent, &cieLen, 1);   // Data alignment factor
    appendULEB(cieContent, &cieLen, raReg);
    appendULEB(cieContent, &cieLen, 1);   // Augmentation data length
    appendU8(cieContent, &cieLen, 0x03);  // DW_EH_PE_udata4
    appendU8(cieContent, &cieLen, 0x0C);  // DW_CFA_def_cfa
    appendULEB(cieContent, &cieLen, cfaReg);
    appendULEB(cieContent, &cieLen, ptrSize);

    uint8_t expr[16];
    size_t exprLen = 0;
    appendU8(expr, &exprLen, 0x10);  // DW_OP_constu
    appendULEB(expr, &exprLen, (uint64_t)expectedRA);
    appendU8(expr, &exprLen, 0x9F);  // DW_OP_stack_value

    uint8_t fdeContent[64];
    size_t fdeLen = 0;
    appendU8(fdeContent, &fdeLen, 0x00);
    appendU8(fdeContent, &fdeLen, 0x00);
    appendU8(fdeContent, &fdeLen, 0x00);
    appendU8(fdeContent, &fdeLen, 0x00);  // CIE pointer (patched later)
    writeU32LE(&fdeContent[fdeLen], 0x1000);
    fdeLen += 4;
    writeU32LE(&fdeContent[fdeLen], 0x10);
    fdeLen += 4;
    appendU8(fdeContent, &fdeLen, 0x00);  // Augmentation data length
    appendU8(fdeContent, &fdeLen, 0x10);  // DW_CFA_expression
    appendULEB(fdeContent, &fdeLen, raReg);
    appendULEB(fdeContent, &fdeLen, exprLen);
    memcpy(&fdeContent[fdeLen], expr, exprLen);
    fdeLen += exprLen;

    uint8_t ehFrame[256];
    size_t ehLen = 0;
    writeU32LE(&ehFrame[ehLen], (uint32_t)cieLen);
    ehLen += 4;
    memcpy(&ehFrame[ehLen], cieContent, cieLen);
    ehLen += cieLen;
    writeU32LE(&ehFrame[ehLen], (uint32_t)fdeLen);
    ehLen += 4;
    size_t fdeStart = ehLen;
    memcpy(&ehFrame[ehLen], fdeContent, fdeLen);
    ehLen += fdeLen;
    writeU32LE(&ehFrame[ehLen], 0x00);  // Terminator
    ehLen += 4;

    writeU32LE(&ehFrame[fdeStart], (uint32_t)(fdeStart));

    uintptr_t stack[2] = { 0 };
    uintptr_t sp = (uintptr_t)&stack[0];

    KSDwarfUnwindResult result;
    bool success = ksdwarf_unwind(ehFrame, ehLen, 0x1000, sp, 0, 0, 0, &result);
    XCTAssertTrue(success, @"DWARF unwind with stack_value should succeed");
    XCTAssertTrue(result.valid, @"Result should be valid");
    XCTAssertEqual(result.returnAddress, expectedRA, @"Return address should match stack_value expression");
    XCTAssertEqual(result.stackPointer, sp + ptrSize, @"CFA should be SP + ptrSize");
}

// =============================================================================
// MARK: - 64-bit DWARF Format Tests
// =============================================================================

- (void)testDwarf_FindFDE_64BitFormat
{
#if defined(__arm64__)
    const uint8_t raReg = KSDWARF_ARM64_LR;
    const uint8_t cfaReg = KSDWARF_ARM64_SP;
#elif defined(__x86_64__)
    const uint8_t raReg = KSDWARF_X86_64_RIP;
    const uint8_t cfaReg = KSDWARF_X86_64_RSP;
#elif defined(__arm__)
    const uint8_t raReg = KSDWARF_ARM_R14;
    const uint8_t cfaReg = KSDWARF_ARM_R13;
#elif defined(__i386__)
    const uint8_t raReg = KSDWARF_X86_EIP;
    const uint8_t cfaReg = KSDWARF_X86_ESP;
#else
    XCTSkip(@"Unsupported architecture for 64-bit DWARF test");
    return;
#endif

    const uint8_t ptrSize = (uint8_t)sizeof(uintptr_t);

    uint8_t cieContent[64];
    size_t cieLen = 0;
    for (int i = 0; i < 8; i++) {
        appendU8(cieContent, &cieLen, 0x00);
    }
    appendU8(cieContent, &cieLen, 0x03);  // Version = 3
    appendU8(cieContent, &cieLen, 'z');
    appendU8(cieContent, &cieLen, 'R');
    appendU8(cieContent, &cieLen, 0x00);                 // Augmentation string
    appendULEB(cieContent, &cieLen, 1);                  // Code alignment factor
    appendSLEB(cieContent, &cieLen, -(int64_t)ptrSize);  // Data alignment factor
    appendULEB(cieContent, &cieLen, raReg);
    appendULEB(cieContent, &cieLen, 1);   // Augmentation data length
    appendU8(cieContent, &cieLen, 0x03);  // DW_EH_PE_udata4
    appendU8(cieContent, &cieLen, 0x0C);  // DW_CFA_def_cfa
    appendULEB(cieContent, &cieLen, cfaReg);
    appendULEB(cieContent, &cieLen, ptrSize);

    uint8_t fdeContent[32];
    size_t fdeLen = 0;
    for (int i = 0; i < 8; i++) {
        appendU8(fdeContent, &fdeLen, 0x00);
    }
    writeU32LE(&fdeContent[fdeLen], 0x1000);
    fdeLen += 4;
    writeU32LE(&fdeContent[fdeLen], 0x10);
    fdeLen += 4;
    appendU8(fdeContent, &fdeLen, 0x00);  // Augmentation data length

    uint8_t ehFrame[256];
    size_t ehLen = 0;
    writeU32LE(&ehFrame[ehLen], 0xFFFFFFFF);
    ehLen += 4;
    writeU64LE(&ehFrame[ehLen], (uint64_t)cieLen);
    ehLen += 8;
    memcpy(&ehFrame[ehLen], cieContent, cieLen);
    ehLen += cieLen;

    writeU32LE(&ehFrame[ehLen], 0xFFFFFFFF);
    ehLen += 4;
    writeU64LE(&ehFrame[ehLen], (uint64_t)fdeLen);
    ehLen += 8;
    size_t fdeStart = ehLen;
    memcpy(&ehFrame[ehLen], fdeContent, fdeLen);
    ehLen += fdeLen;
    writeU32LE(&ehFrame[ehLen], 0x00);
    ehLen += 4;

    writeU64LE(&ehFrame[fdeStart], (uint64_t)(fdeStart));

    const uint8_t *fde = NULL;
    size_t fdeSize = 0;
    const uint8_t *cie = NULL;
    size_t cieSize = 0;
    bool is64bit = false;

    bool found = ksdwarf_findFDE(ehFrame, ehLen, 0x1000, 0, &fde, &fdeSize, &cie, &cieSize, &is64bit);
    XCTAssertTrue(found, @"Should find FDE in 64-bit DWARF data");
    XCTAssertTrue(is64bit, @"Should report 64-bit DWARF format");

    KSDwarfCFIRow row;
    bool success = ksdwarf_buildCFIRow(cie, cieSize, fde, fdeSize, 0x1000, is64bit, &row);
    XCTAssertTrue(success, @"Building CFI row should succeed for 64-bit format");
    XCTAssertEqual(row.cfaRegister, cfaReg, @"CFA register should match");
    XCTAssertEqual(row.cfaOffset, ptrSize, @"CFA offset should match pointer size");
}

// =============================================================================
// MARK: - Real __eh_frame Integration Test
// =============================================================================

- (void)testDwarf_FindFDE_RealEhFrame
{
    uintptr_t address = (uintptr_t)&ks_dwarf_test_helper;
    const KSUnwindImageInfo *info = ksunwindcache_getInfoForAddress(address);
    if (info == NULL || !info->hasEhFrame) {
        XCTSkip(@"No __eh_frame available for test binary");
        return;
    }

    const uint8_t *fde = NULL;
    size_t fdeSize = 0;
    const uint8_t *cie = NULL;
    size_t cieSize = 0;
    bool is64bit = false;

    bool found = ksdwarf_findFDE(info->ehFrame, info->ehFrameSize, address, (uintptr_t)info->header, &fde, &fdeSize,
                                 &cie, &cieSize, &is64bit);
    if (!found) {
        // The test function might not have FDE (e.g., leaf function with no unwind info)
        XCTSkip(@"No FDE found for test helper function - this is expected for simple leaf functions");
        return;
    }

    KSDwarfCFIRow row;
    bool built = ksdwarf_buildCFIRow(cie, cieSize, fde, fdeSize, address, is64bit, &row);
    XCTAssertTrue(built, @"Should build CFI row from real __eh_frame data");
}

@end
