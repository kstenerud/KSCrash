//
// KSCompactUnwind_x86.c
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

#if defined(__i386__)

#include "KSLogger.h"
#include "KSMemory.h"
#include "Unwind/KSCompactUnwind.h"

// MARK: - Internal Functions

/**
 * Read a 32-bit pointer value safely from memory.
 */
static inline bool readPtr(uintptr_t addr, uintptr_t *outValue)
{
    uint32_t value;
    if (!ksmem_copySafely((const void *)addr, &value, sizeof(value))) {
        return false;
    }
    *outValue = value;
    return true;
}

// MARK: - x86 (32-bit) Compact Unwind Decoder

bool kscu_x86_decode(compact_unwind_encoding_t encoding, uintptr_t pc __attribute__((unused)), uintptr_t sp,
                     uintptr_t bp, KSCompactUnwindResult *result)
{
    if (result == NULL) {
        return false;
    }

    // Initialize result
    *result = (KSCompactUnwindResult) {
        .valid = false,
        .framePointerRestored = false,
        .returnAddress = 0,
        .stackPointer = 0,
        .framePointer = 0,
        .savedRegisterMask = 0,
    };

    uint32_t mode = encoding & KSCU_UNWIND_X86_MODE_MASK;

    KSLOG_TRACE("x86 decode: encoding=0x%x, mode=0x%x, pc=0x%lx, sp=0x%lx, bp=0x%lx", encoding, mode, (unsigned long)pc,
                (unsigned long)sp, (unsigned long)bp);

    if (mode == KSCU_UNWIND_X86_MODE_EBP_FRAME) {
        // EBP frame-based unwinding:
        // - EBP points to saved EBP: [EBP] = prev_EBP
        // - Return address is at [EBP+4]
        // - Caller's ESP = EBP + 8

        if (bp == 0) {
            KSLOG_TRACE("Base pointer is NULL, cannot unwind");
            return false;
        }

        // Read return address from [EBP+4]
        uintptr_t returnAddr;
        if (!readPtr(bp + 4, &returnAddr)) {
            KSLOG_TRACE("Failed to read return address from EBP+4 (0x%lx)", (unsigned long)(bp + 4));
            return false;
        }

        // Read previous frame pointer from [EBP]
        uintptr_t prevBP;
        if (!readPtr(bp, &prevBP)) {
            KSLOG_TRACE("Failed to read previous EBP from EBP (0x%lx)", (unsigned long)bp);
            return false;
        }

        result->returnAddress = returnAddr;
        result->framePointer = prevBP;
        result->framePointerRestored = true;  // EBP-frame: FP restored from stack
        result->stackPointer = bp + 8;

        result->valid = true;
        KSLOG_TRACE("EBP-frame unwind: returnAddr=0x%lx, newESP=0x%lx, newEBP=0x%lx",
                    (unsigned long)result->returnAddress, (unsigned long)result->stackPointer,
                    (unsigned long)result->framePointer);
        return true;
    } else if (mode == KSCU_UNWIND_X86_MODE_STACK_IMMD) {
        // Frameless with immediate stack size:
        // - Stack size is encoded in bits 16-23 (multiply by 4)
        // - The encoded size is the sub esp immediate, NOT including the return address
        // - We add 4 to account for the return address pushed by CALL
        // - Return address is then at sp + stackSize - 4

        uint32_t encodedSize =
            ((encoding & KSCU_UNWIND_X86_FRAMELESS_STACK_SIZE_MASK) >> KSCU_UNWIND_X86_FRAMELESS_STACK_SIZE_SHIFT) * 4;
        // Total stack frame includes the return address pushed by CALL
        uint32_t stackSize = encodedSize + 4;

        if (encodedSize == 0) {
            // No stack adjustment - leaf function, return address at [ESP]
            uintptr_t returnAddr;
            if (!readPtr(sp, &returnAddr)) {
                KSLOG_TRACE("Failed to read return address from ESP (0x%lx)", (unsigned long)sp);
                return false;
            }
            result->returnAddress = returnAddr;
            result->stackPointer = sp + 4;  // Pop return address
            result->framePointer = bp;
            result->valid = true;
            KSLOG_TRACE("Frameless leaf: returnAddr=0x%lx", (unsigned long)result->returnAddress);
            return true;
        }

        // Return address is at the top of the frame
        uintptr_t returnAddr;
        if (!readPtr(sp + stackSize - 4, &returnAddr)) {
            KSLOG_TRACE("Failed to read return address from ESP+stackSize-4 (0x%lx)",
                        (unsigned long)(sp + stackSize - 4));
            return false;
        }

        result->returnAddress = returnAddr;
        result->stackPointer = sp + stackSize;
        result->framePointer = bp;  // Preserve BP - frameless functions don't modify it
        result->valid = true;

        KSLOG_TRACE("Frameless immediate: returnAddr=0x%lx, stackSize=%u (encoded=%u)",
                    (unsigned long)result->returnAddress, stackSize, encodedSize);
        return true;
    } else if (mode == KSCU_UNWIND_X86_MODE_STACK_IND) {
        // Frameless with indirect stack size - requires instruction parsing
        KSLOG_TRACE("Frameless indirect mode - requires instruction parsing, falling back");
        return false;
    } else if (mode == KSCU_UNWIND_X86_MODE_DWARF) {
        // DWARF mode - cannot decode with compact unwind
        KSLOG_TRACE("DWARF mode, cannot decode with compact unwind");
        return false;
    } else if (mode == 0) {
        // No unwind info - likely a leaf function
        // On x86, return address is at [ESP]
        uintptr_t returnAddr;
        if (!readPtr(sp, &returnAddr)) {
            KSLOG_TRACE("Failed to read return address from ESP (0x%lx)", (unsigned long)sp);
            return false;
        }

        result->returnAddress = returnAddr;
        result->stackPointer = sp + 4;  // Pop return address
        result->framePointer = bp;
        result->valid = true;
        KSLOG_TRACE("No unwind info, assuming leaf: returnAddr=0x%lx", (unsigned long)result->returnAddress);
        return true;
    }

    KSLOG_TRACE("Unknown x86 unwind mode: 0x%x", mode);
    return false;
}

#endif  // __i386__
