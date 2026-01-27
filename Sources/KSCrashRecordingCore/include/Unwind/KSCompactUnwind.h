//
// KSCompactUnwind.h
//
// Created by Alexander Cohen on 2025-01-16.
//
// Copyright (c) 2012 Karl Stenerud. All rights reserved.
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

#ifndef KSCompactUnwind_h
#define KSCompactUnwind_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Compact Unwind Encoding Constants

// Apple's compact unwind encoding type
typedef uint32_t compact_unwind_encoding_t;

// Common mode mask (applies to all architectures)
#define KSCU_UNWIND_IS_NOT_FUNCTION_START 0x80000000
#define KSCU_UNWIND_HAS_LSDA 0x40000000
#define KSCU_UNWIND_PERSONALITY_MASK 0x30000000

// MARK: - ARM64 Compact Unwind Encoding

#define KSCU_UNWIND_ARM64_MODE_MASK 0x0F000000
#define KSCU_UNWIND_ARM64_MODE_FRAMELESS 0x02000000
#define KSCU_UNWIND_ARM64_MODE_DWARF 0x03000000
#define KSCU_UNWIND_ARM64_MODE_FRAME 0x04000000

// Frame-based unwinding: FP/LR pair + callee-saved registers
#define KSCU_UNWIND_ARM64_FRAME_X19_X20_PAIR 0x00000001
#define KSCU_UNWIND_ARM64_FRAME_X21_X22_PAIR 0x00000002
#define KSCU_UNWIND_ARM64_FRAME_X23_X24_PAIR 0x00000004
#define KSCU_UNWIND_ARM64_FRAME_X25_X26_PAIR 0x00000008
#define KSCU_UNWIND_ARM64_FRAME_X27_X28_PAIR 0x00000010
#define KSCU_UNWIND_ARM64_FRAME_D8_D9_PAIR 0x00000100
#define KSCU_UNWIND_ARM64_FRAME_D10_D11_PAIR 0x00000200
#define KSCU_UNWIND_ARM64_FRAME_D12_D13_PAIR 0x00000400
#define KSCU_UNWIND_ARM64_FRAME_D14_D15_PAIR 0x00000800

// Frameless unwinding: stack size encoding
#define KSCU_UNWIND_ARM64_FRAMELESS_STACK_SIZE_MASK 0x00FFF000

// MARK: - x86_64 Compact Unwind Encoding

#define KSCU_UNWIND_X86_64_MODE_MASK 0x0F000000
#define KSCU_UNWIND_X86_64_MODE_RBP_FRAME 0x01000000
#define KSCU_UNWIND_X86_64_MODE_STACK_IMMD 0x02000000
#define KSCU_UNWIND_X86_64_MODE_STACK_IND 0x03000000
#define KSCU_UNWIND_X86_64_MODE_DWARF 0x04000000

// RBP frame-based: offset to saved registers
#define KSCU_UNWIND_X86_64_RBP_FRAME_OFFSET_MASK 0x00FF0000
#define KSCU_UNWIND_X86_64_RBP_FRAME_OFFSET_SHIFT 16

// Frameless: stack size and register permutation
#define KSCU_UNWIND_X86_64_FRAMELESS_STACK_SIZE_MASK 0x00FF0000
#define KSCU_UNWIND_X86_64_FRAMELESS_STACK_SIZE_SHIFT 16
#define KSCU_UNWIND_X86_64_FRAMELESS_STACK_ADJUST_MASK 0x0000E000
#define KSCU_UNWIND_X86_64_FRAMELESS_STACK_ADJUST_SHIFT 13
#define KSCU_UNWIND_X86_64_FRAMELESS_STACK_REG_COUNT_MASK 0x00001C00
#define KSCU_UNWIND_X86_64_FRAMELESS_STACK_REG_COUNT_SHIFT 10
#define KSCU_UNWIND_X86_64_FRAMELESS_STACK_REG_PERMUTATION_MASK 0x000003FF

// MARK: - x86 (32-bit) Compact Unwind Encoding

#define KSCU_UNWIND_X86_MODE_MASK 0x0F000000
#define KSCU_UNWIND_X86_MODE_EBP_FRAME 0x01000000
#define KSCU_UNWIND_X86_MODE_STACK_IMMD 0x02000000
#define KSCU_UNWIND_X86_MODE_STACK_IND 0x03000000
#define KSCU_UNWIND_X86_MODE_DWARF 0x04000000

// EBP frame-based
#define KSCU_UNWIND_X86_EBP_FRAME_OFFSET_MASK 0x00FF0000
#define KSCU_UNWIND_X86_EBP_FRAME_OFFSET_SHIFT 16
#define KSCU_UNWIND_X86_EBP_FRAME_REGISTERS_MASK 0x00007FFF

// Frameless
#define KSCU_UNWIND_X86_FRAMELESS_STACK_SIZE_MASK 0x00FF0000
#define KSCU_UNWIND_X86_FRAMELESS_STACK_SIZE_SHIFT 16

// MARK: - ARM (32-bit) Compact Unwind Encoding

#define KSCU_UNWIND_ARM_MODE_MASK 0x0F000000
#define KSCU_UNWIND_ARM_MODE_FRAME 0x01000000
#define KSCU_UNWIND_ARM_MODE_FRAME_D 0x02000000
#define KSCU_UNWIND_ARM_MODE_DWARF 0x04000000

// MARK: - Data Structures

/**
 * Compact unwind entry for a function.
 * Contains the decoded information needed for unwinding.
 */
typedef struct {
    uintptr_t functionStart;             // Function start address (with slide)
    uintptr_t functionLength;            // Function length in bytes
    compact_unwind_encoding_t encoding;  // Raw compact encoding
    uintptr_t personalityFunction;       // Personality routine address (0 if none)
    uintptr_t lsda;                      // LSDA address (0 if none)
} KSCompactUnwindEntry;

/**
 * Result of unwinding a single frame using compact unwind.
 */
typedef struct {
    bool valid;               // True if unwinding succeeded
    uintptr_t returnAddress;  // Recovered return address
    uintptr_t stackPointer;   // Recovered stack pointer
    uintptr_t framePointer;   // Recovered frame pointer (0 if not applicable)

    // Recovered callee-saved registers (architecture-specific)
    // ARM64: X19-X28, D8-D15
    // x86_64: RBX, R12-R15
    // x86: EBX, ESI, EDI, EBP
    uintptr_t savedRegisters[16];
    uint32_t savedRegisterMask;  // Bitmask of which registers were recovered
} KSCompactUnwindResult;

// MARK: - API

/**
 * Look up compact unwind information for a PC address.
 *
 * This function searches the __unwind_info section to find the
 * compact unwind entry for the function containing the given PC.
 *
 * This function is async-signal-safe.
 *
 * @param unwindInfo Pointer to the __unwind_info section data.
 * @param unwindInfoSize Size of the __unwind_info section.
 * @param targetPC The PC address to look up (with slide applied).
 * @param imageBase The base address of the image (mach_header address).
 * @param slide The ASLR slide of the image.
 * @param outEntry If not NULL, receives the found compact unwind entry.
 * @return True if an entry was found, false otherwise.
 */
bool kscu_findEntry(const void *unwindInfo, size_t unwindInfoSize, uintptr_t targetPC, uintptr_t imageBase,
                    uintptr_t slide, KSCompactUnwindEntry *outEntry);

/**
 * Check if a compact unwind encoding indicates DWARF unwinding is needed.
 *
 * Some functions are too complex for compact unwind and fall back to DWARF.
 * This function checks if the encoding indicates such a fallback.
 *
 * @param encoding The compact unwind encoding to check.
 * @return True if DWARF unwinding is needed, false if compact unwind can be used.
 */
bool kscu_encodingRequiresDwarf(compact_unwind_encoding_t encoding);

/**
 * Get the unwind mode from a compact unwind encoding.
 *
 * @param encoding The compact unwind encoding.
 * @return The mode portion of the encoding (architecture-specific).
 */
uint32_t kscu_getMode(compact_unwind_encoding_t encoding);

// MARK: - Architecture-Specific Decoders

#if defined(__arm64__)
/**
 * Decode ARM64 compact unwind encoding and recover caller's registers.
 *
 * This function is async-signal-safe.
 *
 * @param encoding The compact unwind encoding.
 * @param pc Current program counter.
 * @param sp Current stack pointer.
 * @param fp Current frame pointer.
 * @param lr Current link register (return address in leaf functions).
 * @param result Output structure for recovered register values.
 * @return True if decoding succeeded, false if DWARF fallback is needed.
 */
bool kscu_arm64_decode(compact_unwind_encoding_t encoding, uintptr_t pc, uintptr_t sp, uintptr_t fp, uintptr_t lr,
                       KSCompactUnwindResult *result);
#endif

#if defined(__x86_64__)
/**
 * Decode x86_64 compact unwind encoding and recover caller's registers.
 *
 * This function is async-signal-safe.
 *
 * @param encoding The compact unwind encoding.
 * @param pc Current program counter.
 * @param sp Current stack pointer.
 * @param bp Current base pointer (frame pointer).
 * @param result Output structure for recovered register values.
 * @return True if decoding succeeded, false if DWARF fallback is needed.
 */
bool kscu_x86_64_decode(compact_unwind_encoding_t encoding, uintptr_t pc, uintptr_t sp, uintptr_t bp,
                        KSCompactUnwindResult *result);
#endif

#if defined(__arm__) && !defined(__arm64__)
/**
 * Decode ARM32 compact unwind encoding and recover caller's registers.
 *
 * This function is async-signal-safe.
 *
 * @param encoding The compact unwind encoding.
 * @param pc Current program counter.
 * @param sp Current stack pointer.
 * @param r7 Current frame pointer (R7 on ARM32).
 * @param lr Current link register.
 * @param result Output structure for recovered register values.
 * @return True if decoding succeeded, false if DWARF fallback is needed.
 */
bool kscu_arm_decode(compact_unwind_encoding_t encoding, uintptr_t pc, uintptr_t sp, uintptr_t r7, uintptr_t lr,
                     KSCompactUnwindResult *result);
#endif

#if defined(__i386__)
/**
 * Decode x86 (32-bit) compact unwind encoding and recover caller's registers.
 *
 * This function is async-signal-safe.
 *
 * @param encoding The compact unwind encoding.
 * @param pc Current program counter.
 * @param sp Current stack pointer.
 * @param bp Current base pointer (frame pointer).
 * @param result Output structure for recovered register values.
 * @return True if decoding succeeded, false if DWARF fallback is needed.
 */
bool kscu_x86_decode(compact_unwind_encoding_t encoding, uintptr_t pc, uintptr_t sp, uintptr_t bp,
                     KSCompactUnwindResult *result);
#endif

#ifdef __cplusplus
}
#endif

#endif /* KSCompactUnwind_h */
