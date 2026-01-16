//
// KSDwarfUnwind.h
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

#ifndef KSDwarfUnwind_h
#define KSDwarfUnwind_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - DWARF Register Rule Types

typedef enum {
    KSDwarfRuleUndefined = 0,  // Register value is undefined
    KSDwarfRuleSameValue,      // Register value is unchanged
    KSDwarfRuleOffset,         // Value at CFA + offset
    KSDwarfRuleValOffset,      // CFA + offset (not dereferenced)
    KSDwarfRuleRegister,       // Value in another register
    KSDwarfRuleExpression,     // Value computed by DWARF expression
    KSDwarfRuleValExpression,  // CFA computed by DWARF expression
    KSDwarfRuleArchitectural,  // Architecture-specific
} KSDwarfRuleType;

// MARK: - DWARF Register Numbers

// ARM64 DWARF register numbers
#define KSDWARF_ARM64_X0 0
#define KSDWARF_ARM64_X28 28
#define KSDWARF_ARM64_FP 29  // x29
#define KSDWARF_ARM64_LR 30  // x30
#define KSDWARF_ARM64_SP 31  // x31
#define KSDWARF_ARM64_PC 32  // Not a real register, but used in DWARF

// x86_64 DWARF register numbers
#define KSDWARF_X86_64_RAX 0
#define KSDWARF_X86_64_RDX 1
#define KSDWARF_X86_64_RCX 2
#define KSDWARF_X86_64_RBX 3
#define KSDWARF_X86_64_RSI 4
#define KSDWARF_X86_64_RDI 5
#define KSDWARF_X86_64_RBP 6
#define KSDWARF_X86_64_RSP 7
#define KSDWARF_X86_64_R8 8
#define KSDWARF_X86_64_R15 15
#define KSDWARF_X86_64_RIP 16  // Return address

// x86 (32-bit) DWARF register numbers
#define KSDWARF_X86_EAX 0
#define KSDWARF_X86_ECX 1
#define KSDWARF_X86_EDX 2
#define KSDWARF_X86_EBX 3
#define KSDWARF_X86_ESP 4
#define KSDWARF_X86_EBP 5
#define KSDWARF_X86_ESI 6
#define KSDWARF_X86_EDI 7
#define KSDWARF_X86_EIP 8  // Return address

// ARM (32-bit) DWARF register numbers
#define KSDWARF_ARM_R0 0
#define KSDWARF_ARM_R7 7    // Frame pointer (thumb)
#define KSDWARF_ARM_R11 11  // Frame pointer (arm)
#define KSDWARF_ARM_R13 13  // SP
#define KSDWARF_ARM_R14 14  // LR
#define KSDWARF_ARM_R15 15  // PC

// Maximum number of registers we track
#define KSDWARF_MAX_REGISTERS 64

// MARK: - Data Structures

/**
 * Rule for recovering a single register.
 */
typedef struct {
    KSDwarfRuleType type;
    int64_t offset;       // For OFFSET/VALOFFSET rules
    uint8_t regNum;       // For REGISTER rule
    const uint8_t *expr;  // For EXPRESSION rules (pointer to expression bytes)
    size_t exprLen;       // Length of expression
} KSDwarfRegisterRule;

/**
 * CFI row representing register recovery rules at a specific location.
 */
typedef struct {
    uintptr_t location;  // PC location this row applies to

    // CFA (Canonical Frame Address) rule
    KSDwarfRuleType cfaRule;
    uint8_t cfaRegister;  // Register for CFA calculation
    int64_t cfaOffset;    // Offset for CFA calculation
    const uint8_t *cfaExpression;
    size_t cfaExpressionLen;

    // Register rules
    KSDwarfRegisterRule registers[KSDWARF_MAX_REGISTERS];
} KSDwarfCFIRow;

/**
 * Result of DWARF unwinding.
 */
typedef struct {
    bool valid;
    uintptr_t returnAddress;
    uintptr_t stackPointer;
    uintptr_t framePointer;
} KSDwarfUnwindResult;

// MARK: - Public API

/**
 * Parse DWARF unwind info and unwind one frame.
 *
 * @param ehFrame Pointer to the .eh_frame section data.
 * @param ehFrameSize Size of the .eh_frame section.
 * @param pc Current program counter.
 * @param sp Current stack pointer.
 * @param fp Current frame pointer.
 * @param lr Link register (ARM only, 0 for x86).
 * @param imageBase Base address of the image.
 * @param result Output: the unwind result.
 * @return true if unwinding succeeded, false otherwise.
 */
bool ksdwarf_unwind(const void *ehFrame, size_t ehFrameSize, uintptr_t pc, uintptr_t sp, uintptr_t fp, uintptr_t lr,
                    uintptr_t imageBase, KSDwarfUnwindResult *result);

/**
 * Find the FDE (Frame Description Entry) for a given PC.
 *
 * @param ehFrame Pointer to the .eh_frame section data.
 * @param ehFrameSize Size of the .eh_frame section.
 * @param targetPC The PC to find unwind info for.
 * @param imageBase Base address of the image.
 * @param outFDE Output: pointer to the FDE if found.
 * @param outFDESize Output: size of the FDE.
 * @param outCIE Output: pointer to the CIE for this FDE.
 * @param outCIESize Output: size of the CIE.
 * @return true if FDE was found, false otherwise.
 */
bool ksdwarf_findFDE(const void *ehFrame, size_t ehFrameSize, uintptr_t targetPC, uintptr_t imageBase,
                     const uint8_t **outFDE, size_t *outFDESize, const uint8_t **outCIE, size_t *outCIESize);

/**
 * Execute CFI instructions to build a CFI row for a target PC.
 *
 * @param cie Pointer to CIE data (after length field).
 * @param cieSize Size of CIE.
 * @param fde Pointer to FDE data (after length field).
 * @param fdeSize Size of FDE.
 * @param targetPC The PC to build row for.
 * @param outRow Output: the CFI row.
 * @return true if CFI row was built successfully.
 */
bool ksdwarf_buildCFIRow(const uint8_t *cie, size_t cieSize, const uint8_t *fde, size_t fdeSize, uintptr_t targetPC,
                         KSDwarfCFIRow *outRow);

#ifdef __cplusplus
}
#endif

#endif  // KSDwarfUnwind_h
