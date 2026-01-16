//
// KSCompactUnwind_x86_64.c
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

#if defined(__x86_64__)

#include "KSLogger.h"
#include "KSMemory.h"
#include "Unwind/KSCompactUnwind.h"

// MARK: - x86_64 Register Indices

// Callee-saved registers
#define KSREG_X86_64_RBX 0
#define KSREG_X86_64_R12 1
#define KSREG_X86_64_R13 2
#define KSREG_X86_64_R14 3
#define KSREG_X86_64_R15 4
#define KSREG_X86_64_RBP 5

// MARK: - Internal Functions

/**
 * Read a pointer-sized value safely from memory.
 */
static inline bool readPtr(uintptr_t addr, uintptr_t *outValue)
{
    return ksmem_copySafely((const void *)addr, outValue, sizeof(uintptr_t));
}

// MARK: - x86_64 Compact Unwind Decoder

bool kscu_x86_64_decode(compact_unwind_encoding_t encoding, uintptr_t pc __attribute__((unused)), uintptr_t sp,
                        uintptr_t bp, KSCompactUnwindResult *result)
{
    if (result == NULL) {
        return false;
    }

    // Initialize result
    *result = (KSCompactUnwindResult) {
        .valid = false,
        .returnAddress = 0,
        .stackPointer = 0,
        .framePointer = 0,
        .savedRegisterMask = 0,
    };

    uint32_t mode = encoding & KSCU_UNWIND_X86_64_MODE_MASK;

    KSLOG_TRACE("x86_64 decode: encoding=0x%x, mode=0x%x, pc=0x%lx, sp=0x%lx, bp=0x%lx", encoding, mode,
                (unsigned long)pc, (unsigned long)sp, (unsigned long)bp);

    if (mode == KSCU_UNWIND_X86_64_MODE_RBP_FRAME) {
        // RBP frame-based unwinding:
        // - RBP points to saved RBP: [RBP] = prev_RBP
        // - Return address is at [RBP+8]
        // - Caller's RSP = RBP + 16

        if (bp == 0) {
            KSLOG_TRACE("Base pointer is NULL, cannot unwind");
            return false;
        }

        // Read return address from [RBP+8]
        uintptr_t returnAddr;
        if (!readPtr(bp + 8, &returnAddr)) {
            KSLOG_TRACE("Failed to read return address from RBP+8 (0x%lx)", (unsigned long)(bp + 8));
            return false;
        }

        // Read previous frame pointer from [RBP]
        uintptr_t prevBP;
        if (!readPtr(bp, &prevBP)) {
            KSLOG_TRACE("Failed to read previous RBP from RBP (0x%lx)", (unsigned long)bp);
            return false;
        }

        result->returnAddress = returnAddr;
        result->framePointer = prevBP;
        result->stackPointer = bp + 16;  // Caller's RSP

        // Decode saved callee-saved registers
        // The offset field indicates how many registers are saved
        // They are stored below RBP: [RBP-8], [RBP-16], etc.
        uint32_t regOffset =
            (encoding & KSCU_UNWIND_X86_64_RBP_FRAME_OFFSET_MASK) >> KSCU_UNWIND_X86_64_RBP_FRAME_OFFSET_SHIFT;

        // The registers are saved in a specific order based on the encoding
        // For simplicity, we check which registers might be saved
        if (regOffset > 0) {
            uintptr_t regAddr = bp - 8;

            // Attempt to read any saved registers
            // The exact registers depend on the lower bits of encoding
            // For now, we'll skip detailed register recovery as it's complex
            // and rarely needed for basic backtrace purposes
            (void)regAddr;  // Suppress unused warning
        }

        result->valid = true;
        KSLOG_TRACE("RBP-frame unwind: returnAddr=0x%lx, newRSP=0x%lx, newRBP=0x%lx",
                    (unsigned long)result->returnAddress, (unsigned long)result->stackPointer,
                    (unsigned long)result->framePointer);
        return true;
    } else if (mode == KSCU_UNWIND_X86_64_MODE_STACK_IMMD) {
        // Frameless with immediate stack size:
        // - Stack size is encoded in bits 16-23 (multiply by 8)
        // - The encoded size is the sub rsp immediate, NOT including the return address
        // - We add 8 to account for the return address pushed by CALL
        // - Return address is then at sp + stackSize - 8

        uint32_t encodedSize = ((encoding & KSCU_UNWIND_X86_64_FRAMELESS_STACK_SIZE_MASK) >>
                                KSCU_UNWIND_X86_64_FRAMELESS_STACK_SIZE_SHIFT) *
                               8;
        // Total stack frame includes the return address pushed by CALL
        uint32_t stackSize = encodedSize + 8;

        if (encodedSize == 0) {
            // No stack adjustment - leaf function, return address at [RSP]
            uintptr_t returnAddr;
            if (!readPtr(sp, &returnAddr)) {
                KSLOG_TRACE("Failed to read return address from RSP (0x%lx)", (unsigned long)sp);
                return false;
            }
            result->returnAddress = returnAddr;
            result->stackPointer = sp + 8;  // Pop return address
            result->framePointer = bp;
            result->valid = true;
            KSLOG_TRACE("Frameless leaf: returnAddr=0x%lx", (unsigned long)result->returnAddress);
            return true;
        }

        // Return address is at the top of the frame
        uintptr_t returnAddr;
        if (!readPtr(sp + stackSize - 8, &returnAddr)) {
            KSLOG_TRACE("Failed to read return address from SP+stackSize-8 (0x%lx)",
                        (unsigned long)(sp + stackSize - 8));
            return false;
        }

        result->returnAddress = returnAddr;
        result->stackPointer = sp + stackSize;
        result->framePointer = 0;  // No frame pointer
        result->valid = true;

        KSLOG_TRACE("Frameless immediate: returnAddr=0x%lx, stackSize=%u (encoded=%u)",
                    (unsigned long)result->returnAddress, stackSize, encodedSize);
        return true;
    } else if (mode == KSCU_UNWIND_X86_64_MODE_STACK_IND) {
        // Frameless with indirect stack size:
        // - Stack size is read from the function prologue
        // - This is complex and requires reading the instruction stream
        // - For now, we fall back to DWARF for these cases

        KSLOG_TRACE("Frameless indirect mode - requires instruction parsing, falling back");
        return false;
    } else if (mode == KSCU_UNWIND_X86_64_MODE_DWARF) {
        // DWARF mode - cannot decode with compact unwind
        KSLOG_TRACE("DWARF mode, cannot decode with compact unwind");
        return false;
    } else if (mode == 0) {
        // No unwind info - likely a leaf function
        // On x86_64, return address is at [RSP]
        uintptr_t returnAddr;
        if (!readPtr(sp, &returnAddr)) {
            KSLOG_TRACE("Failed to read return address from RSP (0x%lx)", (unsigned long)sp);
            return false;
        }

        result->returnAddress = returnAddr;
        result->stackPointer = sp + 8;  // Pop return address
        result->framePointer = bp;
        result->valid = true;
        KSLOG_TRACE("No unwind info, assuming leaf: returnAddr=0x%lx", (unsigned long)result->returnAddress);
        return true;
    }

    KSLOG_TRACE("Unknown x86_64 unwind mode: 0x%x", mode);
    return false;
}

#endif  // __x86_64__
