//
// KSCompactUnwind_arm64.c
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

#if defined(__arm64__)

#include "KSLogger.h"
#include "KSMemory.h"
#include "Unwind/KSCompactUnwind.h"

// MARK: - ARM64 Register Indices

// Callee-saved general purpose registers (X19-X28)
#define KSREG_ARM64_X19 0
#define KSREG_ARM64_X20 1
#define KSREG_ARM64_X21 2
#define KSREG_ARM64_X22 3
#define KSREG_ARM64_X23 4
#define KSREG_ARM64_X24 5
#define KSREG_ARM64_X25 6
#define KSREG_ARM64_X26 7
#define KSREG_ARM64_X27 8
#define KSREG_ARM64_X28 9

// Note: D8-D15 floating point registers are omitted for simplicity
// The savedRegisters array only has 16 slots which is enough for X19-X28 (10 regs)
// If needed in the future, increase savedRegisters array size

// MARK: - Internal Functions

/**
 * Read a pointer-sized value safely from memory.
 */
static inline bool readPtr(uintptr_t addr, uintptr_t *outValue)
{
    return ksmem_copySafely((const void *)addr, outValue, sizeof(uintptr_t));
}

// MARK: - ARM64 Compact Unwind Decoder

bool kscu_arm64_decode(compact_unwind_encoding_t encoding, uintptr_t pc __attribute__((unused)), uintptr_t sp,
                       uintptr_t fp, uintptr_t lr, KSCompactUnwindResult *result)
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

    uint32_t mode = encoding & KSCU_UNWIND_ARM64_MODE_MASK;

    KSLOG_TRACE("ARM64 decode: encoding=0x%x, mode=0x%x, pc=0x%lx, sp=0x%lx, fp=0x%lx, lr=0x%lx", encoding, mode,
                (unsigned long)pc, (unsigned long)sp, (unsigned long)fp, (unsigned long)lr);

    if (mode == KSCU_UNWIND_ARM64_MODE_FRAME) {
        // Frame-based unwinding:
        // - FP points to saved FP/LR pair: [FP] = prev_FP, [FP+8] = LR (return address)
        // - Caller's SP = FP + 16
        // - Callee-saved registers X19-X28, D8-D15 are below FP

        if (fp == 0) {
            KSLOG_TRACE("Frame pointer is NULL, cannot unwind");
            return false;
        }

        // Read return address from [FP+8]
        uintptr_t returnAddr;
        if (!readPtr(fp + 8, &returnAddr)) {
            KSLOG_TRACE("Failed to read return address from FP+8 (0x%lx)", (unsigned long)(fp + 8));
            return false;
        }

        // Read previous frame pointer from [FP]
        uintptr_t prevFP;
        if (!readPtr(fp, &prevFP)) {
            KSLOG_TRACE("Failed to read previous FP from FP (0x%lx)", (unsigned long)fp);
            return false;
        }

        result->returnAddress = returnAddr;
        result->framePointer = prevFP;
        result->framePointerRestored = true;  // Frame-based: FP restored from stack
        result->stackPointer = fp + 16;       // Caller's SP

        // Decode saved callee-saved registers
        // They are stored below FP in pairs, growing downward
        uintptr_t regSaveAddr = fp - 8;

        // X19/X20 pair
        if (encoding & KSCU_UNWIND_ARM64_FRAME_X19_X20_PAIR) {
            uintptr_t regs[2];
            if (ksmem_copySafely((const void *)(regSaveAddr - 8), regs, sizeof(regs))) {
                result->savedRegisters[KSREG_ARM64_X19] = regs[0];
                result->savedRegisters[KSREG_ARM64_X20] = regs[1];
                result->savedRegisterMask |= (1 << KSREG_ARM64_X19) | (1 << KSREG_ARM64_X20);
            }
            regSaveAddr -= 16;
        }

        // X21/X22 pair
        if (encoding & KSCU_UNWIND_ARM64_FRAME_X21_X22_PAIR) {
            uintptr_t regs[2];
            if (ksmem_copySafely((const void *)(regSaveAddr - 8), regs, sizeof(regs))) {
                result->savedRegisters[KSREG_ARM64_X21] = regs[0];
                result->savedRegisters[KSREG_ARM64_X22] = regs[1];
                result->savedRegisterMask |= (1 << KSREG_ARM64_X21) | (1 << KSREG_ARM64_X22);
            }
            regSaveAddr -= 16;
        }

        // X23/X24 pair
        if (encoding & KSCU_UNWIND_ARM64_FRAME_X23_X24_PAIR) {
            uintptr_t regs[2];
            if (ksmem_copySafely((const void *)(regSaveAddr - 8), regs, sizeof(regs))) {
                result->savedRegisters[KSREG_ARM64_X23] = regs[0];
                result->savedRegisters[KSREG_ARM64_X24] = regs[1];
                result->savedRegisterMask |= (1 << KSREG_ARM64_X23) | (1 << KSREG_ARM64_X24);
            }
            regSaveAddr -= 16;
        }

        // X25/X26 pair
        if (encoding & KSCU_UNWIND_ARM64_FRAME_X25_X26_PAIR) {
            uintptr_t regs[2];
            if (ksmem_copySafely((const void *)(regSaveAddr - 8), regs, sizeof(regs))) {
                result->savedRegisters[KSREG_ARM64_X25] = regs[0];
                result->savedRegisters[KSREG_ARM64_X26] = regs[1];
                result->savedRegisterMask |= (1 << KSREG_ARM64_X25) | (1 << KSREG_ARM64_X26);
            }
            regSaveAddr -= 16;
        }

        // X27/X28 pair
        if (encoding & KSCU_UNWIND_ARM64_FRAME_X27_X28_PAIR) {
            uintptr_t regs[2];
            if (ksmem_copySafely((const void *)(regSaveAddr - 8), regs, sizeof(regs))) {
                result->savedRegisters[KSREG_ARM64_X27] = regs[0];
                result->savedRegisters[KSREG_ARM64_X28] = regs[1];
                result->savedRegisterMask |= (1 << KSREG_ARM64_X27) | (1 << KSREG_ARM64_X28);
            }
            regSaveAddr -= 16;
        }

        // Note: D8-D15 floating point register recovery is not implemented
        // as they are rarely needed for backtrace purposes. The register
        // save area is still properly accounted for in stack layout.
        (void)regSaveAddr;  // Suppress unused warning; kept for future D8-D15 support

        result->valid = true;
        KSLOG_TRACE("Frame-based unwind: returnAddr=0x%lx, newSP=0x%lx, newFP=0x%lx",
                    (unsigned long)result->returnAddress, (unsigned long)result->stackPointer,
                    (unsigned long)result->framePointer);
        return true;
    } else if (mode == KSCU_UNWIND_ARM64_MODE_FRAMELESS) {
        // Frameless unwinding:
        // - Stack size is encoded in bits 12-23 (multiply by 16)
        // - Return address is at the top of the frame

        uint32_t stackSize = ((encoding & KSCU_UNWIND_ARM64_FRAMELESS_STACK_SIZE_MASK) >> 12) * 16;

        if (stackSize == 0) {
            // Leaf function - return address is in LR
            result->returnAddress = lr;
            result->stackPointer = sp;
            result->framePointer = fp;  // Preserve FP - frameless functions don't modify it
            result->valid = true;
            KSLOG_TRACE("Frameless leaf: returnAddr=0x%lx (from LR)", (unsigned long)result->returnAddress);
            return true;
        }

        // Non-leaf frameless function - return address is saved at the top of the frame
        uintptr_t returnAddr;
        if (!readPtr(sp + stackSize - 8, &returnAddr)) {
            KSLOG_TRACE("Failed to read return address from SP+stackSize-8 (0x%lx)",
                        (unsigned long)(sp + stackSize - 8));
            return false;
        }

        result->returnAddress = returnAddr;
        result->stackPointer = sp + stackSize;
        result->framePointer = fp;  // Preserve FP - frameless functions don't modify it
        result->valid = true;

        KSLOG_TRACE("Frameless non-leaf: returnAddr=0x%lx, stackSize=%u", (unsigned long)result->returnAddress,
                    stackSize);
        return true;
    } else if (mode == KSCU_UNWIND_ARM64_MODE_DWARF) {
        // DWARF mode - cannot decode with compact unwind
        KSLOG_TRACE("DWARF mode, cannot decode with compact unwind");
        return false;
    } else if (mode == 0) {
        // No unwind info - assume leaf function
        result->returnAddress = lr;
        result->stackPointer = sp;
        result->framePointer = fp;
        result->valid = true;
        KSLOG_TRACE("No unwind info, assuming leaf: returnAddr=0x%lx (from LR)", (unsigned long)result->returnAddress);
        return true;
    }

    KSLOG_TRACE("Unknown ARM64 unwind mode: 0x%x", mode);
    return false;
}

#endif  // __arm64__
