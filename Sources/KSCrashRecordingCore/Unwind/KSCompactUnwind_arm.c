//
// KSCompactUnwind_arm.c
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

#if defined(__arm__) && !defined(__arm64__)

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

// MARK: - ARM32 Compact Unwind Decoder

bool kscu_arm_decode(compact_unwind_encoding_t encoding, uintptr_t pc __attribute__((unused)), uintptr_t sp,
                     uintptr_t r7, uintptr_t lr, KSCompactUnwindResult *result)
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

    uint32_t mode = encoding & KSCU_UNWIND_ARM_MODE_MASK;

    KSLOG_TRACE("ARM32 decode: encoding=0x%x, mode=0x%x, pc=0x%lx, sp=0x%lx, r7=0x%lx, lr=0x%lx", encoding, mode,
                (unsigned long)pc, (unsigned long)sp, (unsigned long)r7, (unsigned long)lr);

    if (mode == KSCU_UNWIND_ARM_MODE_FRAME || mode == KSCU_UNWIND_ARM_MODE_FRAME_D) {
        // Frame-based unwinding (R7 is frame pointer on ARM32):
        // - R7 points to saved R7/LR pair: [R7] = prev_R7, [R7+4] = LR
        // - Caller's SP = R7 + 8

        if (r7 == 0) {
            KSLOG_TRACE("Frame pointer (R7) is NULL, cannot unwind");
            return false;
        }

        // Read return address from [R7+4]
        uintptr_t returnAddr;
        if (!readPtr(r7 + 4, &returnAddr)) {
            KSLOG_TRACE("Failed to read return address from R7+4 (0x%lx)", (unsigned long)(r7 + 4));
            return false;
        }

        // Read previous frame pointer from [R7]
        uintptr_t prevR7;
        if (!readPtr(r7, &prevR7)) {
            KSLOG_TRACE("Failed to read previous R7 from R7 (0x%lx)", (unsigned long)r7);
            return false;
        }

        // Clear Thumb bit from return address
        result->returnAddress = returnAddr & ~1UL;
        result->framePointer = prevR7;
        result->stackPointer = r7 + 8;

        result->valid = true;
        KSLOG_TRACE("Frame-based unwind: returnAddr=0x%lx, newSP=0x%lx, newR7=0x%lx",
                    (unsigned long)result->returnAddress, (unsigned long)result->stackPointer,
                    (unsigned long)result->framePointer);
        return true;
    } else if (mode == KSCU_UNWIND_ARM_MODE_DWARF) {
        // DWARF mode - cannot decode with compact unwind
        KSLOG_TRACE("DWARF mode, cannot decode with compact unwind");
        return false;
    } else if (mode == 0) {
        // No unwind info - assume leaf function
        result->returnAddress = lr & ~1UL;  // Clear Thumb bit
        result->stackPointer = sp;
        result->framePointer = r7;
        result->valid = true;
        KSLOG_TRACE("No unwind info, assuming leaf: returnAddr=0x%lx (from LR)", (unsigned long)result->returnAddress);
        return true;
    }

    KSLOG_TRACE("Unknown ARM32 unwind mode: 0x%x", mode);
    return false;
}

#endif  // __arm__ && !__arm64__
